import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:companion/core/title_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
Map<String, dynamic> claim(Object value, {String rank = 'normal'}) => {
  'rank': rank,
  'mainsnak': {
    'datavalue': {'value': value},
  },
};
Map<String, dynamic> animeRow({String type = 'TV'}) => {
  'mal_id': 52991,
  'title': 'Sousou no Frieren',
  'type': type,
  'url': 'https://myanimelist.net/anime/52991',
  'images': {
    'jpg': {'image_url': 'https://cdn.myanimelist.net/frieren.jpg'},
  },
  'studios': [
    {'name': 'Madhouse'},
  ],
  'year': 2023,
  'season': 'fall',
  'episodes': 28,
  'duration': type == 'Movie' ? '1 hr 42 min' : '24 min per ep',
};

void main() {
  test('blank queries do not contact any catalog', () async {
    final service = TitleLookup(
      fetch: (_) async => throw StateError('Unexpected network'),
    );
    for (final catalog in TitleCatalog.values) {
      expect(await service.search(catalog, '   '), isEmpty);
    }
    await expectLater(
      service.search(TitleCatalog.anime, 'a' * 201),
      throwsFormatException,
    );
  });

  test(
    'anime search and selection parse metadata and cache requests',
    () async {
      final calls = <Uri>[];
      final service = TitleLookup(
        fetch: (uri) async {
          calls.add(uri);
          return bytes({
            'data': uri.path.endsWith('52991') ? animeRow() : [animeRow()],
          });
        },
      );
      final rows = await service.search(
        TitleCatalog.anime,
        'Frieren & friends',
      );
      expect(calls.single.queryParameters['q'], 'Frieren & friends');
      final selected = await service.details(rows.single);
      expect(selected.title, 'Sousou no Frieren');
      expect(selected.creator, 'Madhouse');
      expect(selected.year, 2023);
      expect(selected.episodes, 28);
      expect(selected.minutes, 24);
      expect(selected.season, 'fall');
      expect(selected.coverUrl, startsWith('https://'));
      await service.search(TitleCatalog.anime, 'Frieren & friends');
      await service.details(rows.single);
      expect(calls.length, 2);
    },
  );

  test(
    'movie anime duration includes hours and unknown counts stay unknown',
    () async {
      final service = TitleLookup(
        fetch: (_) async => bytes({
          'data': [
            {
              ...animeRow(type: 'Movie'),
              'episodes': null,
              'year': null,
              'aired': {'from': '2001-07-20T00:00:00+00:00'},
            },
          ],
        }),
      );
      final row = (await service.search(
        TitleCatalog.anime,
        'Spirited Away',
      )).single;
      expect(row.minutes, 102);
      expect(row.episodes, isNull);
      expect(row.year, 2001);
    },
  );

  test(
    'manga uses its own endpoint, authors, chapter and volume counts',
    () async {
      final service = TitleLookup(
        fetch: (uri) async {
          expect(uri.path, '/v4/manga');
          return bytes({
            'data': [
              {
                'mal_id': 13,
                'title': 'One Piece',
                'chapters': 0,
                'volumes': null,
                'authors': [
                  {'name': 'Oda, Eiichiro'},
                ],
                'published': {'from': '1997-07-22'},
                'images': {
                  'jpg': {'image_url': 'javascript:bad'},
                },
              },
            ],
          });
        },
      );
      final row = (await service.search(
        TitleCatalog.manga,
        'One Piece',
      )).single;
      expect(row.creator, 'Oda, Eiichiro');
      expect(row.year, 1997);
      expect(row.chapters, isNull);
      expect(row.volumes, isNull);
      expect(row.coverUrl, isEmpty);
    },
  );

  test('Wikidata movie search resolves director and runtime units', () async {
    final calls = <Uri>[];
    final service = TitleLookup(
      fetch: (uri) async {
        calls.add(uri);
        if (uri.queryParameters['action'] == 'query') {
          expect(
            uri.queryParameters['srsearch'],
            contains('haswbstatement:P31=Q11424'),
          );
          return bytes({
            'query': {
              'search': [
                {'title': 'Q20382729'},
              ],
            },
          });
        }
        if (uri.queryParameters['ids'] == 'Q282110') {
          return bytes({
            'entities': {
              'Q282110': {
                'labels': {
                  'en': {'value': 'Denis Villeneuve'},
                },
              },
            },
          });
        }
        return bytes({
          'entities': {
            'Q20382729': {
              'labels': {
                'en': {'value': 'Arrival'},
              },
              'claims': {
                'P57': [
                  claim({'id': 'Q282110'}),
                ],
                'P2047': [
                  claim({
                    'amount': '+116',
                    'unit': 'http://www.wikidata.org/entity/Q7727',
                  }),
                ],
                'P577': [
                  claim({'time': '+2016-09-01T00:00:00Z'}),
                ],
                'P18': [claim('Arrival title.jpg')],
              },
            },
          },
        });
      },
    );
    final row = (await service.search(TitleCatalog.film, 'Arrival')).single;
    final details = await service.details(row);
    expect(details.creator, 'Denis Villeneuve');
    expect(details.minutes, 116);
    expect(details.year, 2016);
    expect(
      Uri.decodeComponent(Uri.parse(details.coverUrl).path),
      '/wiki/Special:FilePath/Arrival title.jpg',
    );
    expect(calls.length, 3);
  });

  test('ended series count complete season orders, ongoing series total is unknown', () async {
    var ongoing = false;
    Future<Uint8List> fetch(Uri uri) async {
      final show = {
        'id': 17861,
        'name': 'Dark',
        'status': ongoing ? 'Running' : 'Ended',
        'premiered': '2017-12-01',
        'averageRuntime': 56,
        'runtime': null,
        'url': 'https://www.tvmaze.com/shows/17861/dark',
      };
      if (uri.path == '/search/shows') {
        return bytes([
          {'show': show},
        ]);
      }
      if (uri.path.endsWith('/seasons')) {
        return bytes([
          {'episodeOrder': 10},
          {'episodeOrder': 8},
          {'episodeOrder': 8},
        ]);
      }
      return bytes(show);
    }

    var service = TitleLookup(fetch: fetch);
    var row = await service.details(
      (await service.search(TitleCatalog.series, 'Dark')).single,
    );
    expect(row.episodes, 26);
    expect(row.minutes, 56);
    expect(row.year, 2017);
    ongoing = true;
    service = TitleLookup(fetch: fetch);
    row = await service.details(
      (await service.search(TitleCatalog.series, 'Dark')).single,
    );
    expect(row.episodes, isNull);
  });

  test('partial series season counts do not become a false total', () async {
    final service = TitleLookup(
      fetch: (uri) async => bytes(
        uri.path.endsWith('/seasons')
            ? [
                {'episodeOrder': 10},
                {'episodeOrder': null},
              ]
            : {'id': 1, 'name': 'Series', 'status': 'Ended'},
      ),
    );
    final row = await service.details(
      const TitleMetadata(
        catalog: TitleCatalog.series,
        id: '1',
        title: 'Series',
        sourceUrl: '',
      ),
    );
    expect(row.episodes, isNull);
  });

  test('network failures become actionable errors', () async {
    for (final error in [
      const SocketException('offline'),
      TimeoutException('timeout'),
    ]) {
      final service = TitleLookup(fetch: (_) async => throw error);
      await expectLater(
        service.search(TitleCatalog.series, 'Dark'),
        throwsFormatException,
      );
    }
  });

  test('oversized and API error responses are rejected', () async {
    for (final value in [
      bytes({
        'error': {'code': 'maxlag'},
      }),
      Uint8List(TitleLookup.maxBytes + 1),
    ]) {
      final service = TitleLookup(fetch: (_) async => value);
      await expectLater(
        service.search(TitleCatalog.film, 'Arrival'),
        throwsFormatException,
      );
    }
  });

  test('invalid JSON does not become a cached successful search', () async {
    var calls = 0;
    final service = TitleLookup(
      fetch: (_) async {
        calls++;
        return calls == 1 ? Uint8List.fromList([1, 2, 3]) : bytes([]);
      },
    );
    await expectLater(
      service.search(TitleCatalog.series, 'Dark'),
      throwsFormatException,
    );
    expect(await service.search(TitleCatalog.series, 'Dark'), isEmpty);
    expect(calls, 2);
  });

  test('unavailable Jikan falls back to Kitsu and subsequent searches skip the outage', () async {
    final calls = <Uri>[];
    final row = {
      'id': '46474',
      'attributes': {
        'canonicalTitle': 'Sousou no Frieren',
        'slug': 'sousou-no-frieren',
        'startDate': '2023-09-29',
        'subtype': 'TV',
        'episodeCount': 28,
        'episodeLength': 24,
        'chapterCount': null,
        'posterImage': {'medium': 'https://media.kitsu.app/frieren.jpg'},
      },
    };
    final service = TitleLookup(
      fetch: (uri) async {
        calls.add(uri);
        if (uri.host == 'api.jikan.moe') {
          throw const SocketException('unavailable');
        }
        expect(uri.host, 'kitsu.io');
        return bytes({
          'data': uri.path.endsWith('46474') ? row : [row],
        });
      },
    );
    final results = await service.search(TitleCatalog.anime, 'Frieren');
    final selected = await service.details(results.single);
    expect(selected.title, 'Sousou no Frieren');
    expect(selected.sourceName, 'Kitsu');
    expect(selected.episodes, 28);
    expect(selected.minutes, 24);
    expect(selected.year, 2023);
    await service.search(TitleCatalog.anime, 'Another title');
    expect(calls.where((uri) => uri.host == 'api.jikan.moe'), hasLength(1));
  });
}
