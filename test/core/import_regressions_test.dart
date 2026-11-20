import 'dart:convert';

import 'package:companion/anime/anime_backup.dart';
import 'package:companion/anime/anime_entry.dart';
import 'package:companion/film/app_state.dart' as film;
import 'package:companion/film/library_controller.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/models/viewing.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/core/library.dart';
import 'package:companion/core/physical_collection.dart';
import 'package:companion/manga/app_state.dart' as manga;
import 'package:companion/manga/importers.dart';
import 'package:companion/manga/library_controller.dart';
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Recent in the film controller uses the latest viewing, with undated entries last', () async {
    final state = film.AppState(await ShelfStore.open(memoryOnly: true));
    final entries = [
      ShelfEntry(
        id: 'edited',
        title: 'Old viewing, edited today',
        addedAt: 1,
        lastUpdated: 999999,
        status: 'seen',
        viewings: [Viewing(at: 1000, precision: 'day')],
      ),
      ShelfEntry(
        id: 'new',
        title: 'Latest viewing',
        addedAt: 2,
        lastUpdated: 1,
        status: 'seen',
        viewings: [
          Viewing(at: 100, precision: 'day'),
          Viewing(at: 5000, precision: 'day'),
        ],
      ),
      ShelfEntry(
        id: 'unknown',
        title: 'Undated',
        addedAt: 9999999,
        lastUpdated: 9999999,
        status: 'seen',
        viewings: [Viewing.undated()],
      ),
    ];
    for (final entry in entries) {
      await state.add(entry);
    }
    final controller = FilmLibraryController(state);
    final query = LibraryDisplayQuery()..shelf = 'seen';
    expect(controller.rows(query).map((e) => e.id), [
      'new',
      'edited',
      'unknown',
    ]);
    query.descending = true;
    expect(controller.rows(query).map((e) => e.id), [
      'unknown',
      'edited',
      'new',
    ]);
    query.descending = false;
    query.sort = 'edited';
    expect(controller.rows(query).first.id, 'unknown');
    controller.dispose();
    state.dispose();
  });

  test('manga ratings update the visible edit date and persist it; undo keeps its original date', () async {
    final store = await MangaStore.open();
    await store.save([
      MangaEntry(id: 'm', title: 'Manga', addedAt: 1, lastUpdated: 1),
    ]);
    final state = manga.AppState(store);
    final controller = MangaLibraryController(state);
    expect(
      controller.rows(LibraryDisplayQuery()).single.updatedLabel,
      contains('1970'),
    );
    await state.setRating('m', 4);
    expect(state.entries.single.lastUpdated, greaterThan(1));
    expect(store.load().single.lastUpdated, state.entries.single.lastUpdated);
    expect(
      controller.rows(LibraryDisplayQuery()).single.updatedLabel,
      startsWith('Last edited: '),
    );
    final before = await state.setStatus('m', ShelfStatus.dropped);
    await state.update(before!);
    expect(state.entries.single.lastUpdated, before.lastUpdated);
    controller.dispose();
    state.dispose();
  });

  test(
    'external manga merges keep local physical collection details',
    () async {
      final store = await MangaStore.open();
      await store.save([
        MangaEntry(
          id: 'm',
          title: 'Manga',
          addedAt: 1,
          lastUpdated: 1,
          collection: const PhysicalCollection(
            ownership: Ownership.owned,
            shelf: 'Desk',
            lentTo: 'Alex',
          ),
        ),
      ]);
      final state = manga.AppState(store);
      final incoming = MangaEntry(
        id: 'external',
        title: 'Manga',
        currentChapter: 10,
        addedAt: 1,
        lastUpdated: 2,
      );
      await state.applyMerge(state.planMerge([incoming]));
      expect(state.entries.single.collection.lentTo, 'Alex');
      expect(state.entries.single.currentChapter, 10);
      state.dispose();
    },
  );

  test(
    'Anime-Planet JSON remains readable when downloaded as HTML-wrapped JSON',
    () {
      final json = jsonEncode({
        'export': {'type': 'anime'},
        'entries': [
          {
            'name': 'Example & title',
            'status': 'watched',
            'eps': 12,
            'rating': 4.5,
            'times': 2,
            'started': '2020-12-09 06:22:58+00',
            'completed': '2021-01-02 22:00:00+00',
          },
        ],
      });
      final escaped = const HtmlEscape().convert(json);
      for (final text in [
        json,
        '<!doctype html><html><body><pre>$escaped</pre></body></html>',
        '<html><script type="application/json">$json</script></html>',
      ]) {
        final entry = AnimeBackup.parse(Uint8List.fromList(utf8.encode(text)))
            .single;
        expect(entry.title, 'Example & title');
        expect(entry.rating, 4.5);
        expect(entry.rewatches, 1);
        expect(entry.finishedDate, '2021-01-02');
      }
    },
  );

  test('HTML tables import in the matching library and never create false activity', () {
    const anime =
        '<html><table><tr><th>Title</th><th>Status</th><th>Episodes</th><th>Rating</th></tr>'
        '<tr><td>Example &amp; title</td><td>stalled</td><td>10</td><td>4.5</td></tr></table></html>';
    const manga =
        '<html><table><tr><th>Name</th><th>Status</th><th>Chapters</th><th>Rating</th></tr>'
        '<tr><td>Manga title</td><td>reading</td><td>69</td><td>4</td></tr></table></html>';
    final a = AnimeBackup.parse(Uint8List.fromList(utf8.encode(anime))).single;
    expect(a.status, AnimeStatus.onHold);
    expect(a.currentEpisode, 10);
    expect(a.history, isEmpty);
    final m = parseBackupFile(Uint8List.fromList(utf8.encode(manga)))!
        .entries
        .single;
    expect(m.currentChapter, 69);
    expect(m.history, isEmpty);
    expect(
      () => AnimeBackup.parse(Uint8List.fromList(utf8.encode(manga))),
      throwsFormatException,
    );
    expect(parseBackupFile(Uint8List.fromList(utf8.encode(anime))), isNull);
    expect(
      () => AnimeBackup.parse(
        Uint8List.fromList(utf8.encode('<html>Sign in</html>')),
      ),
      throwsFormatException,
    );
  });
}
