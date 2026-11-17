import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:companion/anime/anime_backup.dart';
import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_library.dart';
import 'package:companion/books/models/book.dart';
import 'package:companion/books/services/storage_service.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/manga/importers.dart';
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/storage.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('Anime JSON preserves every field and unknown dates', () {
    final entry = AnimeEntry(
      title: 'Frieren',
      animeFormat: AnimeFormat.tv,
      status: AnimeStatus.watching,
      currentEpisode: 14,
      totalEpisodes: 28,
      episodeMinutes: 24,
      studio: 'Madhouse',
      year: 2023,
      season: 'Fall',
      note: 'A quiet journey',
      tags: ['fantasy', 'adventure'],
      rating: 5,
      posterUrl: 'https://example.com/frieren.jpg',
      watchUrl: 'https://example.com/watch',
      startedDate: '2023-09',
      rewatches: 1,
      malId: 52991,
      history: [
        {'at': 1000, 'from': 12, 'to': 14, 'unit': 'episodes'},
      ],
    );
    final result = AnimeBackup.parse(bytes(AnimeBackup.encode([entry]))).single;
    expect(result.toJson(), entry.toJson());
    expect(result.finishedDate, '');
    expect(result.minutesSpent, 336);
  });

  test('Episodes and movie minutes remain different progress units', () {
    final tv = AnimeEntry(title: 'TV', totalEpisodes: 12).withProgress(12);
    expect(tv.status, AnimeStatus.completed);
    expect(tv.withProgress(11).status, AnimeStatus.watching);
    expect(tv.withProgress(100).currentEpisode, 12);
    expect(tv.history.single['unit'], 'episodes');
    final movie = AnimeEntry(
      title: 'Anime film',
      animeFormat: AnimeFormat.movie,
      episodeMinutes: 106,
    ).withProgress(50);
    expect(movie.watchedMinutes, 50);
    expect(movie.currentEpisode, 0);
    expect(movie.minutesSpent, 50);
    expect(movie.history.single['unit'], 'minutes');
    expect(movie.withProgress(106).status, AnimeStatus.completed);
    final ongoing = AnimeEntry(title: 'Ongoing').withProgress(1000);
    expect(ongoing.total, isNull);
    expect(ongoing.status, AnimeStatus.watching);
    expect(ongoing.minutesSpent, isNull);
  });

  test('Anime rewatch retains history while resetting current progress', () {
    final complete = AnimeEntry(
      title: 'Rewatch',
      totalEpisodes: 12,
    ).withProgress(12);
    final again = complete.rewatch();
    expect(again.currentEpisode, 0);
    expect(again.rewatches, 1);
    expect(again.history, complete.history);
    expect(again.status, AnimeStatus.watching);
  });

  test('Anime metadata and progress history cannot mutate saved entries indirectly', () {
    final tags = ['space'];
    final event = <String, dynamic>{
      'at': 1000,
      'from': 0,
      'to': 1,
      'unit': 'episodes',
    };
    final entry = AnimeEntry(title: 'Immutable', tags: tags, history: [event]);
    tags.add('changed');
    event['to'] = 20;
    expect(entry.tags, ['space']);
    expect(entry.history.single['to'], 1);
    expect(() => entry.tags.add('mutate'), throwsUnsupportedError);
    expect(() => entry.history.single['to'] = 50, throwsUnsupportedError);
  });

  test('All four backup formats refuse every recognizable foreign type', () {
    final book = Book(id: 'book', title: 'A book', totalPages: 300);
    final manga = MangaEntry(
      id: 'manga',
      title: 'A manga',
      addedAt: 1,
      lastUpdated: 1,
    );
    final film = ShelfEntry.fromJson({
      'id': 'film',
      'title': 'A film',
      'kind': 'film',
      'runtime': 100,
    });
    final anime = AnimeEntry(title: 'An anime');
    final formats = [
      jsonEncode(StorageService().envelope([book])),
      MangaStore.toExportJson([manga]),
      ShelfStore.toExportJson([film]),
      AnimeBackup.encode([anime]),
    ];
    expect(StorageService().parseJson(formats[0]).single.title, 'A book');
    expect(MangaStore.parseExport(formats[1])!.single.title, 'A manga');
    expect(ShelfStore.parseDocument(formats[2]).valid, isTrue);
    expect(AnimeBackup.parse(bytes(formats[3])).single.title, 'An anime');
    for (var i = 0; i < formats.length; i++) {
      if (i != 0) {
        expect(
          () => StorageService().parseJson(formats[i]),
          throwsA(isA<LibraryFormatException>()),
        );
      }
      if (i != 1) {
        expect(MangaStore.parseExport(formats[i]), isNull);
        expect(parseBackupFile(bytes(formats[i])), isNull);
      }
      if (i != 2) expect(ShelfStore.parseDocument(formats[i]).valid, isFalse);
      if (i != 3) {
        expect(
          () => AnimeBackup.parse(bytes(formats[i])),
          throwsFormatException,
        );
      }
    }
  });

  test('Malformed, duplicate, mixed and future anime backups are rejected', () {
    final entry = AnimeEntry(title: 'Anime');
    final envelope = jsonDecode(AnimeBackup.encode([entry]));
    expect(
      () => AnimeBackup.parse(
        bytes(jsonEncode({...envelope, 'schemaVersion': 99})),
      ),
      throwsFormatException,
    );
    expect(
      () => AnimeBackup.parse(bytes(AnimeBackup.encode([entry, entry]))),
      throwsFormatException,
    );
    final invalid = entry.toJson()..['currentEpisode'] = -1;
    expect(() => AnimeEntry.fromJson(invalid), throwsFormatException);
    expect(
      () => AnimeEntry.fromJson(entry.toJson()..['startedDate'] = '2024-02-30'),
      throwsFormatException,
    );
    expect(
      () => AnimeEntry.fromJson(entry.toJson()..['rating'] = 10),
      throwsFormatException,
    );
    final mixed = {
      ...envelope,
      'count': 2,
      'entries': [
        entry.toJson(),
        {'title': 'Film', 'kind': 'film'},
      ],
    };
    expect(
      () => AnimeBackup.parse(bytes(jsonEncode(mixed))),
      throwsFormatException,
    );
  });

  test('MAL anime XML preserves date precision and imports gzipped files', () {
    const xml = '''<?xml version="1.0"?><myanimelist><anime>
      <series_animedb_id>42</series_animedb_id><series_title><![CDATA[Anime & title]]></series_title>
      <series_type>TV</series_type><series_episodes>12</series_episodes>
      <my_watched_episodes>5</my_watched_episodes><my_status>Watching</my_status>
      <my_score>8</my_score><my_start_date>2024-02-00</my_start_date>
      <my_finish_date>0000-00-00</my_finish_date><my_tags>space, drama</my_tags>
      </anime></myanimelist>''';
    final entry = AnimeBackup.parse(Uint8List.fromList(gzip.encode(bytes(xml))))
        .single;
    expect(entry.title, 'Anime & title');
    expect(entry.currentEpisode, 5);
    expect(entry.startedDate, '2024-02');
    expect(entry.finishedDate, '');
    expect(entry.history, isEmpty);
    expect(entry.rating, 4);
    expect(entry.id, 'mal-42');
    expect(
      () => AnimeBackup.parse(bytes('<myanimelist><manga /></myanimelist>')),
      throwsFormatException,
    );
    expect(parseBackupFile(bytes(xml)), isNull);
  });

  group('Anime persistence and recovery', () {
    late Directory directory;
    late AnimeLibrary library;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('companion-anime-');
      library = AnimeLibrary(directory);
      await library.load();
    });
    tearDown(() async {
      library.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'Concurrent progress, trash, restore and restart keep full data',
      () async {
        final entry = AnimeEntry(title: 'Persistent', totalEpisodes: 12);
        await library.save(entry);
        await Future.wait([
          library.save(entry.withProgress(1)),
          library.save(entry.withProgress(2)),
        ]);
        expect(library.entries.single.currentEpisode, 2);
        await library.remove(entry.id);
        expect(library.entries, isEmpty);
        expect(library.trash.single.currentEpisode, 2);
        await library.restore(entry.id);
        final restarted = AnimeLibrary(directory);
        await restarted.load();
        expect(
          restarted.entries.single.toJson(),
          library.entries.single.toJson(),
        );
        restarted.dispose();
      },
    );

    test(
      'Merge is newer-wins and replace has trash plus pre-import snapshot',
      () async {
        final local = AnimeEntry(
          id: 'local',
          title: 'Same',
          currentEpisode: 5,
          updatedAt: 100,
        );
        await library.save(local);
        final older = AnimeEntry(
          id: 'foreign-id',
          title: 'Same',
          currentEpisode: 1,
          updatedAt: 50,
        );
        await library.importEntries([older], replace: false);
        expect(library.entries.single.currentEpisode, 5);
        final newer = AnimeEntry(
          id: 'foreign-id',
          title: 'Same',
          currentEpisode: 7,
          updatedAt: 200,
        );
        await library.importEntries([newer], replace: false);
        expect(library.entries.single.currentEpisode, 7);
        expect(library.entries.single.id, 'local');
        await library.importEntries([
          AnimeEntry(title: 'Replacement'),
        ], replace: true);
        expect(library.trash.single.title, 'Same');
        await library.restoreSnapshot();
        expect(library.entries.single.currentEpisode, 7);
        await library.restoreSnapshot();
        expect(library.entries.single.title, 'Replacement');
      },
    );

    test(
      'A damaged primary recovers previous; failed saves roll memory back',
      () async {
        final entry = AnimeEntry(title: 'Recover');
        await library.save(entry);
        await library.save(entry.withProgress(2));
        await File('${directory.path}/anime-v1.json').writeAsString('broken');
        final restarted = AnimeLibrary(directory);
        await restarted.load();
        expect(restarted.recovered, isTrue);
        expect(restarted.entries.single.currentEpisode, 0);
        restarted.dispose();
        final blocker = File('${directory.path}/not-a-directory');
        await blocker.writeAsString('block');
        final failing = AnimeLibrary(Directory(blocker.path));
        await expectLater(
          failing.save(entry),
          throwsA(isA<FileSystemException>()),
        );
        expect(failing.entries, isEmpty);
        expect(failing.error, isNotNull);
        failing.dispose();
      },
    );
  });
}
