import 'dart:convert';
import 'dart:io';

import 'package:companion/anime/anime_backup.dart';
import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_library.dart';
import 'package:companion/books/models/book.dart';
import 'package:companion/books/services/library_model.dart';
import 'package:companion/books/services/storage_service.dart';
import 'package:companion/books/services/theme_notifier.dart';
import 'package:companion/film/app_state.dart' as film;
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/main.dart';
import 'package:companion/manga/app_state.dart' as manga;
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Four modes, real persistence, typed backups and native channels',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final testRoot = await Directory('${support.path}/integration')
          .create(recursive: true);
      final directory = await testRoot.createTemp('run-');
      final preferences = await SharedPreferences.getInstance();
      final mangaKey =
          'integration-manga-${DateTime.now().microsecondsSinceEpoch}';
      final bookStorage = StorageService(
        directory: Directory('${directory.path}/books'),
      );
      final books = LibraryModel(storage: bookStorage)..autoSnapshots = false;
      await books.load();
      final settings = ThemeNotifier(storage: bookStorage)
        ..loaded = true
        ..autoSnapshots = false;
      final mangaState = manga.AppState(
        MangaStore(preferences, key: mangaKey, sortKey: '$mangaKey-sort'),
      );
      final filmState = film.AppState(
        await ShelfStore.open(directory: Directory('${directory.path}/film')),
      );
      final anime = AnimeLibrary(Directory('${directory.path}/anime'));
      await anime.load();
      await books.addBook(
        Book(id: 'book', title: 'Integration book', totalPages: 300),
      );
      await mangaState.add(
        MangaEntry(
          id: 'manga',
          title: 'Integration manga',
          currentChapter: 14,
          totalChapters: 100,
          addedAt: 1,
          lastUpdated: 1,
        ),
      );
      await filmState.add(
        ShelfEntry(
          id: 'film',
          title: 'Integration film',
          runtime: 110,
          addedAt: 1,
          lastUpdated: 1,
        ),
      );
      await anime.save(
        AnimeEntry(
          id: 'anime',
          title: 'Integration anime',
          currentEpisode: 3,
          totalEpisodes: 12,
          episodeMinutes: 24,
          status: AnimeStatus.watching,
        ),
      );
      final deps = CompanionDependencies(
        books: books,
        settings: settings,
        manga: mangaState,
        film: filmState,
        anime: anime,
        preferences: preferences,
      );
      await tester.pumpWidget(CompanionApp(dependencies: deps));
      await tester.pumpAndSettle();
      Future<void> select(String label) async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.text(label),
              )
              .last,
        );
        await tester.pumpAndSettle();
      }

      await select('Manga');
      expect(find.text('Integration manga'), findsWidgets);
      await select('Film');
      expect(find.text('Integration film'), findsOneWidget);
      await select('Anime');
      await tester.tap(
        find.byTooltip('Increase episodes for Integration anime'),
      );
      await tester.pumpAndSettle();
      expect(anime.entries.single.currentEpisode, 4);
      await tester.tap(find.text('Integration anime'));
      await tester.pumpAndSettle();
      expect(find.text('Edit anime'), findsOneWidget);
      await select('Manga');
      expect(find.text('Integration manga'), findsWidgets);
      await select('Anime');
      expect(find.text('Edit anime'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await select('Settings');
      expect(find.text('App settings'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final exported = File('${directory.path}/anime-export.json');
      await exported.writeAsString(AnimeBackup.encode(anime.entries));
      final imported = AnimeBackup.parse(await exported.readAsBytes());
      expect(imported.single.toJson(), anime.entries.single.toJson());
      final reopened = AnimeLibrary(Directory('${directory.path}/anime'));
      await reopened.load();
      expect(reopened.entries.single.currentEpisode, 4);
      expect(
        MangaStore(preferences, key: mangaKey).load().single.currentChapter,
        14,
      );
      final reopenedFilm = await ShelfStore.open(
        directory: Directory('${directory.path}/film'),
      );
      expect(reopenedFilm.load().single.runtime, 110);
      expect((await bookStorage.loadBooks()).single.totalPages, 300);
      expect(
        ShelfStore.parseDocument(await exported.readAsString()).valid,
        isFalse,
      );
      expect(MangaStore.parseExport(await exported.readAsString()), isNull);
      final bookBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(bookStorage.envelope(books.books))),
      );
      expect(() => AnimeBackup.parse(bookBytes), throwsFormatException);
      // Both old device channels and the new shared export channel are registered
      // on the same FragmentActivity; bad arguments must return a native error.
      expect(
        await LibraryModel.platform.invokeMethod<bool>('appLockEnabled'),
        isFalse,
      );
      const filmDevice = MethodChannel('dev.ionel.movie_companion/device');
      expect(
        await filmDevice.invokeMapMethod<String, dynamic>('backupStatus'),
        isA<Map>(),
      );
      await expectLater(
        const MethodChannel('io.github.yuuge7.companion/export')
            .invokeMethod<String>('saveFile'),
        throwsA(isA<PlatformException>()),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      reopened.dispose();
      deps.dispose();
      await preferences.remove(mangaKey);
      await preferences.remove('$mangaKey-sort');
      await directory.delete(recursive: true);
    },
  );
}
