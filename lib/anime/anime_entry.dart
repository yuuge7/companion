import 'package:uuid/uuid.dart';

enum AnimeFormat {
  tv('TV'),
  movie('Movie'),
  ova('OVA'),
  ona('ONA'),
  special('Special');

  const AnimeFormat(this.label);
  final String label;
}

enum AnimeStatus {
  watching('Watching'),
  planned('Plan to watch'),
  completed('Completed'),
  onHold('On hold'),
  dropped('Dropped');

  const AnimeStatus(this.label);
  final String label;
}

class AnimeEntry {
  AnimeEntry({
    String? id,
    required this.title,
    this.animeFormat = AnimeFormat.tv,
    this.status = AnimeStatus.planned,
    this.currentEpisode = 0,
    this.totalEpisodes,
    this.episodeMinutes,
    this.watchedMinutes = 0,
    this.studio = '',
    this.year,
    this.season = '',
    this.rating = 0,
    this.note = '',
    List<String> tags = const [],
    this.posterUrl = '',
    this.watchUrl = '',
    this.startedDate = '',
    this.finishedDate = '',
    this.rewatches = 0,
    this.malId,
    int? addedAt,
    int? updatedAt,
    List<Map<String, dynamic>> history = const [],
  }) : tags = List.unmodifiable(tags),
       history = List.unmodifiable(
         history.map((event) => Map<String, dynamic>.unmodifiable(event)),
       ),
       id = id ?? const Uuid().v4(),
       addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id,
      title,
      studio,
      season,
      note,
      posterUrl,
      watchUrl,
      startedDate,
      finishedDate;
  final AnimeFormat animeFormat;
  final AnimeStatus status;
  final int currentEpisode,
      watchedMinutes,
      rating,
      rewatches,
      addedAt,
      updatedAt;
  final int? totalEpisodes, episodeMinutes, year, malId;
  final List<String> tags;

  /// Only explicit progress actions get a date. Imported progress has no invented history.
  final List<Map<String, dynamic>> history;

  bool get isMovie => animeFormat == AnimeFormat.movie;
  int get position => isMovie ? watchedMinutes : currentEpisode;
  int? get total => isMovie ? episodeMinutes : totalEpisodes;
  String get unit => isMovie ? 'min' : 'ep';
  String get progressLabel => '$position / ${total ?? "?"} $unit';
  double? get progress =>
      total == null ? null : (position / total!).clamp(0, 1);
  int? get minutesSpent => isMovie
      ? watchedMinutes
      : episodeMinutes == null
      ? null
      : currentEpisode * episodeMinutes!;
  String get identity =>
      '${title.trim().toLowerCase()}|${animeFormat.name}|${year ?? ""}';

  AnimeEntry withProgress(int value, {bool log = true}) {
    final next = value.clamp(0, total ?? 100000);
    final json = toJson();
    json[isMovie ? 'watchedMinutes' : 'currentEpisode'] = next;
    json['status'] = total != null && next == total
        ? 'completed'
        : next > 0 || status == AnimeStatus.completed
        ? 'watching'
        : status.name;
    json['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    if (log && next != position) {
      json['history'] = [
        ...history,
        {
          'at': json['updatedAt'],
          'unit': isMovie ? 'minutes' : 'episodes',
          'from': position,
          'to': next,
        },
      ];
    }
    return AnimeEntry.fromJson(json);
  }

  AnimeEntry rewatch() {
    final json = toJson()
      ..['status'] = 'watching'
      ..['currentEpisode'] = 0
      ..['watchedMinutes'] = 0
      ..['rewatches'] = rewatches + 1
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    return AnimeEntry.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'animeFormat': animeFormat.name,
    'status': status.name,
    'currentEpisode': currentEpisode,
    'totalEpisodes': totalEpisodes,
    'episodeMinutes': episodeMinutes,
    'watchedMinutes': watchedMinutes,
    'studio': studio,
    'year': year,
    'season': season,
    'rating': rating,
    'note': note,
    'tags': tags,
    'posterUrl': posterUrl,
    'watchUrl': watchUrl,
    'startedDate': startedDate,
    'finishedDate': finishedDate,
    'rewatches': rewatches,
    'malId': malId,
    'addedAt': addedAt,
    'updatedAt': updatedAt,
    'history': history,
  };

  factory AnimeEntry.fromJson(Map<String, dynamic> json) {
    int? number(String key, {int min = 0, int max = 100000}) {
      final raw = json[key];
      if (raw == null) return null;
      final n = raw is int ? raw : int.tryParse('$raw');
      if (n == null || n < min || n > max) {
        throw FormatException('Invalid $key.');
      }
      return n;
    }

    String text(String key, [int limit = 10000]) {
      final value = json[key] ?? '';
      if (value is! String || value.length > limit) {
        throw FormatException('Invalid $key.');
      }
      return value;
    }

    final title = text('title', 1000).trim();
    if (title.isEmpty) throw const FormatException('Anime title is required.');
    final format = AnimeFormat.values.byName(text('animeFormat'));
    final status = AnimeStatus.values.byName(text('status'));
    final current = number('currentEpisode') ?? 0;
    final total = number('totalEpisodes', min: 1);
    final minutes = number('episodeMinutes', min: 1);
    final watched = number('watchedMinutes') ?? 0;
    if ((total != null && current > total) ||
        (format == AnimeFormat.movie && minutes != null && watched > minutes)) {
      throw const FormatException('Progress exceeds the total.');
    }
    List<String> tags() {
      final value = json['tags'] ?? <String>[];
      if (value is! List ||
          value.length > 100 ||
          value.any((e) => e is! String)) {
        throw const FormatException('Invalid tags.');
      }
      return List<String>.from(value);
    }

    final history = json['history'] ?? [];
    if (history is! List || history.length > 50000) {
      throw const FormatException('Invalid history.');
    }
    final events = history.map((e) {
      if (e is! Map ||
          e['at'] is! int ||
          e['at'] < 0 ||
          e['at'] > 8640000000000000 ||
          !['episodes', 'minutes'].contains(e['unit']) ||
          e['from'] is! int ||
          e['to'] is! int ||
          e['from'] < 0 ||
          e['to'] < 0 ||
          e['from'] > 100000 ||
          e['to'] > 100000) {
        throw const FormatException('Invalid progress event.');
      }
      return Map<String, dynamic>.from(e);
    }).toList();
    String date(String key) {
      final value = text(key, 10);
      if (value.isNotEmpty) {
        if (!RegExp(r'^\d{4}(-\d{2}(-\d{2})?)?$').hasMatch(value)) {
          throw FormatException(
            'Invalid $key. Use YYYY, YYYY-MM or YYYY-MM-DD.',
          );
        }
        final parts = value.split('-').map(int.parse).toList();
        if (parts[0] < 1 ||
            (parts.length > 1 && (parts[1] < 1 || parts[1] > 12)) ||
            (parts.length > 2 &&
                (parts[2] < 1 ||
                    parts[2] > DateTime(parts[0], parts[1] + 1, 0).day))) {
          throw FormatException('Invalid $key.');
        }
      }
      return value;
    }

    return AnimeEntry(
      id: text('id', 200).isEmpty ? null : text('id', 200),
      title: title,
      animeFormat: format,
      status: status,
      currentEpisode: current,
      totalEpisodes: total,
      episodeMinutes: minutes,
      watchedMinutes: watched,
      studio: text('studio', 1000),
      year: number('year', min: 1, max: 9999),
      season: text('season', 100),
      rating: number('rating', max: 5) ?? 0,
      note: text('note'),
      tags: tags(),
      posterUrl: text('posterUrl', 4000),
      watchUrl: text('watchUrl', 4000),
      startedDate: date('startedDate'),
      finishedDate: date('finishedDate'),
      rewatches: number('rewatches', max: 10000) ?? 0,
      malId: number('malId', min: 1),
      addedAt: number('addedAt', max: 8640000000000000),
      updatedAt: number('updatedAt', max: 8640000000000000),
      history: events,
    );
  }
}
