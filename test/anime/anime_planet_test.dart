import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:companion/anime/anime_backup.dart';
import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_library.dart';
import 'package:companion/books/services/storage_service.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/manga/importers.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final fixture = File('test/anime/fixtures/anime-planet-anime.json')
      .readAsStringSync();
  Map<String, dynamic> document() =>
      jsonDecode(fixture) as Map<String, dynamic>;

  test('Anime-Planet anime JSON preserves every status, half stars and watch counts', () {
    final entries = AnimeBackup.parse(bytes(fixture));
    expect(entries, hasLength(6));
    expect(entries.map((e) => e.status), [
      AnimeStatus.watching,
      AnimeStatus.completed,
      AnimeStatus.planned,
      AnimeStatus.onHold,
      AnimeStatus.dropped,
      AnimeStatus.wontWatch,
    ]);
    expect(entries.first.title, 'Watching & learning');
    expect(entries.first.currentEpisode, 14);
    expect(entries.first.rating, 4.5);
    expect(entries.first.rewatches, 1);
    expect(entries[1].rewatches, 0);
    expect(entries[2].rating, 0);
    expect(entries[3].rating, 2.5);
    expect(entries[3].currentEpisode, 3);
    expect(entries.every((e) => e.history.isEmpty), isTrue);
    final roundTrip = AnimeBackup.parse(bytes(AnimeBackup.encode(entries)));
    expect(roundTrip.map((e) => e.toJson()), entries.map((e) => e.toJson()));
  });

  test('Anime-Planet dates preserve unknown parts without inventing length or runtime', () {
    final entries = AnimeBackup.parse(bytes(fixture));
    expect(entries.first.startedDate, '2023-09');
    expect(entries.first.finishedDate, '');
    expect(entries[1].startedDate, '2021-01-10');
    expect(entries[1].finishedDate, '2021-05-01');
    expect(entries[3].startedDate, '2022');
    expect(entries[3].finishedDate, '');
    for (final entry in entries) {
      expect(entry.animeFormat, AnimeFormat.unknown);
      expect(entry.totalEpisodes, isNull);
      expect(entry.episodeMinutes, isNull);
      expect(entry.minutesSpent, isNull);
    }
  });

  test('Anime-Planet plain, BOM and gzip files produce stable IDs', () {
    final plain = AnimeBackup.parse(bytes(fixture));
    final bom = AnimeBackup.parse(bytes('\uFEFF$fixture'));
    final zipped = AnimeBackup.parse(
      Uint8List.fromList(gzip.encode(bytes(fixture))),
    );
    expect(bom.map((e) => e.id), plain.map((e) => e.id));
    expect(zipped.map((e) => e.id), plain.map((e) => e.id));
    expect(
      zipped.map((e) => e.currentEpisode),
      plain.map((e) => e.currentEpisode),
    );
    final changed = document();
    changed['entries'][0]['name'] = ' WATCHING & LEARNING ';
    expect(
      AnimeBackup.parse(bytes(jsonEncode(changed))).first.id,
      plain.first.id,
    );
    expect(() => AnimeBackup.decodeDocument(document()), throwsFormatException);
  });

  test('Anime-Planet anime stays out of Book, Manga and Film imports', () {
    expect(parseBackupFile(bytes(fixture)), isNull);
    expect(ShelfStore.parseDocument(fixture).valid, isFalse);
    expect(
      () => StorageService().parseJson(fixture),
      throwsA(isA<LibraryFormatException>()),
    );
    final manga = {
      'entries': [
        {'name': 'Manga', 'status': 'read', 'ch': 100, 'vol': 10},
      ],
    };
    expect(
      () => AnimeBackup.parse(bytes(jsonEncode(manga))),
      throwsFormatException,
    );
    final mixed = document();
    (mixed['entries'] as List).add(manga['entries']!.single);
    expect(
      () => AnimeBackup.parse(bytes(jsonEncode(mixed))),
      throwsFormatException,
    );
  });

  test(
    'Malformed Anime-Planet rows are rejected as a whole with their row number',
    () {
      for (final invalid in <Map<String, dynamic>>[
        {'name': ''},
        {'eps': -1},
        {'eps': 2.5},
        {'rating': 6},
        {'rating': 'NaN'},
        {'rating': 2.25},
        {'times': -1},
        {'status': 'something else'},
        {'started': '2024-02-30'},
        {'completed': 'not a date'},
        {'eps': 1, 'ch': 1},
      ]) {
        final data = document();
        (data['entries'][1] as Map).addAll(invalid);
        expect(
          () => AnimeBackup.parse(bytes(jsonEncode(data))),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'row',
              startsWith('Anime-Planet row 2:'),
            ),
          ),
          reason: '$invalid',
        );
      }
      for (final rows in <List<Object?>>[
        [],
        [null],
        [
          {'name': 'No progress marker', 'status': 'watching'},
        ],
      ]) {
        expect(
          () => AnimeBackup.parse(bytes(jsonEncode({'entries': rows}))),
          throwsFormatException,
        );
      }
      final duplicate = document();
      (duplicate['entries'] as List).add(duplicate['entries'][0]);
      expect(
        () => AnimeBackup.parse(bytes(jsonEncode(duplicate))),
        throwsFormatException,
      );
    },
  );

  test('Anime-Planet imports respect entry and compressed file limits', () {
    final row = document()['entries'][0];
    expect(
      () => AnimeBackup.parse(
        bytes(
          jsonEncode({'entries': List.filled(AnimeBackup.maxEntries + 1, row)}),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AnimeBackup.parse(Uint8List(AnimeBackup.maxBytes + 1)),
      throwsFormatException,
    );
    final bomb = gzip.encode(List.filled(AnimeBackup.maxBytes + 1, 32));
    expect(
      () => AnimeBackup.parse(Uint8List.fromList(bomb)),
      throwsFormatException,
    );
  });

  test('Anime-Planet import persists, merges without duplicates and restores its snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('companion-ap-');
    final library = AnimeLibrary(directory);
    addTearDown(() async {
      library.dispose();
      await directory.delete(recursive: true);
    });
    final entries = AnimeBackup.parse(bytes(fixture));
    await library.importEntries(entries, replace: false);
    final reopened = AnimeLibrary(directory);
    await reopened.load();
    expect(
      reopened.entries.map((e) => e.toJson()),
      library.entries.map((e) => e.toJson()),
    );
    reopened.dispose();
    final modified = document();
    modified['entries'][0]['eps'] = 16;
    await library.importEntries(
      AnimeBackup.parse(bytes(jsonEncode(modified))),
      replace: false,
    );
    expect(library.entries, hasLength(6));
    expect(library.entries.first.currentEpisode, 16);
    expect(library.entries.first.rating, 4.5);
    await library.restoreSnapshot();
    expect(library.entries.first.currentEpisode, 14);
  });

  test(
    'Anime-Planet merge preserves local metadata and dated history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'companion-ap-merge-',
      );
      final library = AnimeLibrary(directory);
      addTearDown(() async {
        library.dispose();
        await directory.delete(recursive: true);
      });
      final local = AnimeEntry(
        id: 'local',
        title: 'Watching & learning',
        totalEpisodes: 24,
        episodeMinutes: 23,
        studio: 'Local studio',
        year: 2023,
        note: 'Keep this note',
        tags: ['fantasy'],
        updatedAt: 1,
        history: [
          {'at': 1000, 'from': 0, 'to': 1, 'unit': 'episodes'},
        ],
      );
      await library.save(local);
      final imported = AnimeBackup.parse(bytes(fixture)).first;
      expect(imported.importMatch(library.entries)?.id, 'local');
      await library.importEntries([imported], replace: false);
      final merged = library.entries.single;
      expect(merged.id, 'local');
      expect(merged.currentEpisode, 14);
      expect(merged.rating, 4.5);
      expect(merged.animeFormat, AnimeFormat.tv);
      expect(merged.totalEpisodes, 24);
      expect(merged.episodeMinutes, 23);
      expect(merged.studio, 'Local studio');
      expect(merged.year, 2023);
      expect(merged.note, 'Keep this note');
      expect(merged.tags, ['fantasy']);
      expect(merged.history, local.history);
      // A complete Companion backup remains authoritative for all its fields.
      final own = AnimeEntry.fromJson(
        merged.toJson()
          ..['note'] = 'Updated in a full backup'
          ..['updatedAt'] = merged.updatedAt + 1,
      );
      await library.importEntries([own], replace: false);
      expect(library.entries.single.note, 'Updated in a full backup');
      expect(own.fromAnimePlanetExport, isFalse);
    },
  );

  test('Anime-Planet merge never converts episodes into movie minutes or guesses ambiguous titles', () {
    final imported = AnimeBackup.parse(bytes(fixture)).first;
    final movie = AnimeEntry(
      title: imported.title,
      animeFormat: AnimeFormat.movie,
      episodeMinutes: 110,
      watchedMinutes: 50,
    );
    final merged = imported.importOver(movie);
    expect(merged.animeFormat, AnimeFormat.movie);
    expect(merged.watchedMinutes, 50);
    expect(merged.currentEpisode, 0);
    expect(imported.importMatch([movie]), movie);
    expect(
      imported.importMatch([movie, AnimeEntry(title: movie.title)]),
      isNull,
    );
    final overflow = imported.importOver(
      AnimeEntry(title: imported.title, totalEpisodes: 12),
    );
    expect(overflow.currentEpisode, 14);
    expect(overflow.totalEpisodes, isNull);
  });
}
