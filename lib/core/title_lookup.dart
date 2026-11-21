import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum TitleCatalog {
  film('film', 'Wikidata'),
  series('series', 'TVmaze'),
  manga('manga', 'Jikan / MyAnimeList'),
  anime('anime', 'Jikan / MyAnimeList');

  const TitleCatalog(this.label, this.source);
  final String label, source;
}

/// Catalog metadata only: personal progress, ratings and history are never fetched.
class TitleMetadata {
  const TitleMetadata({
    required this.catalog,
    required this.id,
    required this.title,
    required this.sourceUrl,
    this.creator = '',
    this.coverUrl = '',
    this.format = '',
    this.season = '',
    this.year,
    this.minutes,
    this.episodes,
    this.chapters,
    this.volumes,
  });
  final TitleCatalog catalog;
  final String id, title, sourceUrl, creator, coverUrl, format, season;
  final int? year, minutes, episodes, chapters, volumes;
  String get sourceName => id.startsWith('kitsu:') ? 'Kitsu' : catalog.source;
}

class TitleLookup {
  TitleLookup({this.fetch});
  final Future<Uint8List> Function(Uri)? fetch;
  final _cache = <String, dynamic>{};
  DateTime? _lastRequest;
  bool _preferKitsu = false;
  static const maxBytes = 4 * 1024 * 1024;

  Future<dynamic> _json(Uri uri) async {
    final key = uri.toString();
    if (_cache.containsKey(key)) return _cache[key];
    // Respect Jikan's burst limit, including an immediate result selection.
    if (uri.host == 'api.jikan.moe' && _lastRequest != null) {
      final wait =
          const Duration(milliseconds: 450) -
          DateTime.now().difference(_lastRequest!);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequest = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..userAgent = 'Companion/1.2 (https://github.com/yuuge7/companion)';
    try {
      final bytes = await (() async {
        if (fetch != null) return fetch!(uri);
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode == 429) {
          throw const FormatException(
            'The catalog is busy. Wait a moment before trying again.',
          );
        }
        if (response.statusCode != 200) {
          throw const FormatException(
            'The catalog could not answer. Try again.',
          );
        }
        final result = BytesBuilder();
        await for (final chunk in response) {
          if (result.length + chunk.length > maxBytes) {
            throw const FormatException('The catalog response was too large.');
          }
          result.add(chunk);
        }
        return result.takeBytes();
      })().timeout(const Duration(seconds: 12));
      if (bytes.length > maxBytes) {
        throw const FormatException('The catalog response was too large.');
      }
      final result = jsonDecode(utf8.decode(bytes));
      if (result is Map &&
          (result['error'] != null || result['errors'] != null)) {
        throw const FormatException('The catalog could not answer. Try again.');
      }
      if (_cache.length >= 30) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    } on TimeoutException {
      throw const FormatException(
        'Search timed out. Try again or add manually.',
      );
    } on IOException {
      throw const FormatException(
        'Could not connect. Check your connection or add the title manually.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<TitleMetadata>> search(TitleCatalog catalog, String query) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    if (text.length > 200) {
      throw const FormatException('Use a title of 200 characters or fewer.');
    }
    switch (catalog) {
      case TitleCatalog.film:
        final response = await _json(
          _wiki({
            'action': 'query',
            'list': 'search',
            'srsearch': '$text haswbstatement:P31=Q11424',
            'srnamespace': '0',
            'srlimit': '12',
          }),
        );
        final rows = (response['query']?['search'] as List? ?? []);
        final ids = rows
            .map((e) => _text(e['title']))
            .where(_entityId.hasMatch);
        final entities = await _entities(ids, claims: true);
        return ids
            .where((id) => entities[id] is Map)
            .map((id) => _film(id, entities[id]))
            .where((e) => e.title.isNotEmpty)
            .toList();
      case TitleCatalog.series:
        final rows = await _json(
          Uri.https('api.tvmaze.com', '/search/shows', {'q': text}),
        );
        return (rows as List)
            .take(12)
            .where((e) => e is Map && e['show'] is Map)
            .map((e) => _series(e['show']))
            .where((e) => e.title.isNotEmpty && e.id.isNotEmpty)
            .toList();
      case TitleCatalog.manga:
      case TitleCatalog.anime:
        if (_preferKitsu) return _searchKitsu(catalog, text);
        try {
          final response = await _json(
            Uri.https('api.jikan.moe', '/v4/${catalog.name}', {
              'q': text,
              'limit': '12',
            }),
          );
          return (response['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => _jikan(catalog, e))
              .where((e) => e.title.isNotEmpty && e.id.isNotEmpty)
              .toList();
        } on FormatException {
          _preferKitsu = true;
          return _searchKitsu(catalog, text);
        }
    }
  }

  Future<TitleMetadata> details(TitleMetadata item) async {
    switch (item.catalog) {
      case TitleCatalog.film:
        final entities = await _entities([item.id], claims: true);
        final entity = entities[item.id];
        if (entity is! Map) {
          throw const FormatException('This film is no longer available.');
        }
        final directorIds = _claims(
          entity,
          'P57',
        ).whereType<Map>().map((e) => _text(e['id'])).where(_entityId.hasMatch);
        final directors = await _entities(directorIds);
        return _film(
          item.id,
          entity,
          creator: directorIds
              .map((id) => _label(directors[id]))
              .where((name) => name.isNotEmpty)
              .join(', '),
        );
      case TitleCatalog.series:
        final show = await _json(
          Uri.https('api.tvmaze.com', '/shows/${item.id}'),
        );
        // Counts for ongoing shows are deliberately unknown: aired episodes are
        // not a reliable total and must not imply completion in the editor.
        int? episodes;
        if (show['status'] == 'Ended') {
          final seasons = await _json(
            Uri.https('api.tvmaze.com', '/shows/${item.id}/seasons'),
          ) as List;
          final counts = seasons
              .map((e) => _positive(e['episodeOrder']))
              .toList();
          if (counts.isNotEmpty && counts.every((e) => e != null)) {
            episodes = counts.fold<int>(0, (sum, n) => sum + n!);
          }
        }
        return _series(show, episodes: episodes);
      case TitleCatalog.manga:
      case TitleCatalog.anime:
        if (item.id.startsWith('kitsu:')) {
          final response = await _json(
            Uri.https(
              'kitsu.io',
              '/api/edge/${item.catalog.name}/${item.id.substring(6)}',
            ),
          );
          return _kitsu(item.catalog, response['data']);
        }
        final response = await _json(
          Uri.https('api.jikan.moe', '/v4/${item.catalog.name}/${item.id}'),
        );
        if (response['data'] is! Map) {
          throw const FormatException('This title is no longer available.');
        }
        return _jikan(item.catalog, response['data']);
    }
  }

  Future<List<TitleMetadata>> _searchKitsu(
    TitleCatalog catalog,
    String text,
  ) async {
    final response = await _json(
      Uri.https('kitsu.io', '/api/edge/${catalog.name}', {
        'filter[text]': text,
        'page[limit]': '12',
      }),
    );
    return (response['data'] as List? ?? [])
        .whereType<Map>()
        .map((row) => _kitsu(catalog, row))
        .where((row) => row.title.isNotEmpty && row.id != 'kitsu:')
        .toList();
  }

  static TitleMetadata _kitsu(TitleCatalog catalog, Map row) {
    final a = row['attributes'] as Map? ?? {};
    return TitleMetadata(
      catalog: catalog,
      id: 'kitsu:${row['id'] ?? ''}',
      title: _text(a['canonicalTitle']),
      sourceUrl: Uri.https(
        'kitsu.io',
        '/${catalog.name}/${_text(a['slug'])}',
      ).toString(),
      coverUrl: _url(a['posterImage']?['medium']),
      format: _text(a['subtype']),
      year: _year(a['startDate']),
      minutes: _positive(a['episodeLength']),
      episodes: _positive(a['episodeCount']),
      chapters: _positive(a['chapterCount']),
      volumes: _positive(a['volumeCount']),
    );
  }

  static final _entityId = RegExp(r'^Q[1-9][0-9]*$');
  static String _text(dynamic value) => value is String ? value.trim() : '';
  static int? _positive(dynamic value) =>
      value is int && value > 0 ? value : null;
  static int? _year(dynamic value) {
    final match = RegExp(r'^\+?(\d{4})-').firstMatch(_text(value));
    return match == null ? null : int.tryParse(match[1]!);
  }

  static String _url(dynamic value) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? text
        : '';
  }

  static Uri _wiki(Map<String, String> params) => Uri.https(
    'www.wikidata.org',
    '/w/api.php',
    {...params, 'format': 'json', 'maxlag': '5'},
  );
  Future<Map> _entities(Iterable<String> ids, {bool claims = false}) async {
    if (ids.isEmpty) return {};
    final response = await _json(
      _wiki({
        'action': 'wbgetentities',
        'ids': ids.take(50).join('|'),
        'props': claims ? 'labels|claims' : 'labels',
        'languages': 'en',
      }),
    );
    return response['entities'] as Map? ?? {};
  }

  static String _label(dynamic entity) =>
      entity is Map ? _text(entity['labels']?['en']?['value']) : '';
  static List<dynamic> _claims(Map entity, String property) =>
      (entity['claims']?[property] as List? ?? [])
          .where((e) => e['rank'] != 'deprecated')
          .map((e) => e['mainsnak']?['datavalue']?['value'])
          .where((e) => e != null)
          .toList();
  static TitleMetadata _film(String id, Map entity, {String creator = ''}) {
    final time = _claims(entity, 'P2047').whereType<Map>().firstOrNull;
    final amount = num.tryParse(_text(time?['amount']));
    final unit = _text(time?['unit']);
    final minutes = amount == null
        ? null
        : unit.endsWith('/Q7727')
        ? amount.round()
        : unit.endsWith('/Q11574')
        ? (amount / 60).round()
        : unit.endsWith('/Q25235')
        ? (amount * 60).round()
        : null;
    final image = _claims(entity, 'P18').whereType<String>().firstOrNull;
    return TitleMetadata(
      catalog: TitleCatalog.film,
      id: id,
      title: _label(entity),
      creator: creator,
      sourceUrl: 'https://www.wikidata.org/wiki/$id',
      year: _year(
        _claims(entity, 'P577').whereType<Map>().firstOrNull?['time'],
      ),
      minutes: minutes != null && minutes > 0 ? minutes : null,
      coverUrl: image == null
          ? ''
          : Uri.https(
              'commons.wikimedia.org',
              '/wiki/Special:FilePath/$image',
              {'width': '400'},
            ).toString(),
    );
  }

  static TitleMetadata _series(Map show, {int? episodes}) => TitleMetadata(
    catalog: TitleCatalog.series,
    id: '${show['id'] ?? ''}',
    title: _text(show['name']),
    sourceUrl: _url(show['url']),
    coverUrl: _url(show['image']?['medium']),
    year: _year(show['premiered']),
    minutes: _positive(show['averageRuntime']) ?? _positive(show['runtime']),
    episodes: episodes,
  );
  static TitleMetadata _jikan(TitleCatalog catalog, Map row) {
    final names =
        row[catalog == TitleCatalog.anime ? 'studios' : 'authors'] as List? ??
        [];
    final duration = _text(row['duration']);
    final hours =
        int.tryParse(RegExp(r'(\d+)\s*hr').firstMatch(duration)?[1] ?? '') ?? 0;
    final mins =
        int.tryParse(RegExp(r'(\d+)\s*min').firstMatch(duration)?[1] ?? '') ??
        0;
    return TitleMetadata(
      catalog: catalog,
      id: '${row['mal_id'] ?? ''}',
      title: _text(row['title']),
      sourceUrl: _url(row['url']),
      creator: names
          .map((e) => _text(e['name']))
          .where((e) => e.isNotEmpty)
          .join(', '),
      coverUrl: _url(row['images']?['jpg']?['image_url']),
      format: _text(row['type']),
      season: _text(row['season']),
      year:
          _positive(row['year']) ??
          _year(
            row[catalog == TitleCatalog.anime ? 'aired' : 'published']?['from'],
          ),
      minutes: hours + mins > 0 ? hours * 60 + mins : null,
      episodes: _positive(row['episodes']),
      chapters: _positive(row['chapters']),
      volumes: _positive(row['volumes']),
    );
  }
}
