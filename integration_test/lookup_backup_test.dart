import 'dart:io';

import 'package:companion/anime/anime_entry.dart';
import 'package:companion/books/models/book.dart';
import 'package:companion/core/automatic_backup.dart';
import 'package:companion/core/companion_backup.dart';
import 'package:companion/core/companion_data.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/main.dart';
import 'package:companion/manga/models/manga_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

// Use an isolated emulator with scripts/test_native_backups.py. The host drives
// Android's actual folder picker and checks the exported archive bytes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native scheduled complete backups, retention, failure and restore',
    (tester) async {
      final deps = await CompanionDependencies.load();
      final data = CompanionData(
        books: deps.books,
        settings: deps.settings,
        mangaLibrary: deps.manga,
        filmLibrary: deps.film,
        anime: deps.anime,
        preferences: deps.preferences,
      );
      final cover = await deps.books.storage.storeCover(
        Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 12))),
      );
      await deps.books.addBook(
        Book(
          id: 'native-book',
          title: 'Native backup book',
          coverImagePath: cover,
        ),
      );
      await deps.manga.add(
        MangaEntry(
          id: 'native-manga',
          title: 'Native backup manga',
          currentChapter: 7,
          addedAt: 1,
          lastUpdated: 1,
        ),
      );
      await deps.film.add(
        ShelfEntry.blank()
          ..title = 'Native backup film'
          ..runtime = 116,
      );
      await deps.anime.save(
        AnimeEntry(
          id: 'native-anime',
          title: 'Native backup anime',
          currentEpisode: 3,
        ),
      );
      await tester.pumpWidget(CompanionApp(dependencies: deps));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        debugPrint('AUTO_BACKUP_CHOOSE_FOLDER');
        expect(await AutomaticBackup.chooseFolder(), isTrue);
        final configured = await AutomaticBackup.status();
        expect(configured['enabled'], isTrue);
        expect(configured['scheduled'], isTrue);
        await AutomaticBackup.setFrequency(24);
        expect((await AutomaticBackup.status())['hours'], 24);
        for (var i = 0; i < 4; i++) {
          await AutomaticBackup.backupNow();
        }
        final good = await AutomaticBackup.status();
        expect(good['lastBackup'] as int, greaterThan(0));
        expect(good['error'], '');
        deps.books.saveError = 'Integration failure';
        await expectLater(
          AutomaticBackup.backupNow(),
          throwsA(isA<PlatformException>()),
        );
        final failed = await AutomaticBackup.status();
        expect(failed['lastBackup'], good['lastBackup']);
        expect(failed['error'], isNotEmpty);
        deps.books.saveError = null;
        debugPrint('AUTO_BACKUP_VERIFY');
        final received = File(
          '${(await getApplicationSupportDirectory()).path}/native-roundtrip.companion',
        );
        final timer = Stopwatch()..start();
        while (!await received.exists() &&
            timer.elapsed < const Duration(seconds: 60)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(await received.exists(), isTrue);
        final backup = CompanionBackup(data);
        final preview = backup.decode(await received.readAsBytes());
        expect(preview.counts, {'Books': 1, 'Manga': 1, 'Film': 1, 'Anime': 1});
        expect(preview.books.covers, isNotEmpty);
        await deps.manga.restoreCompanion([]);
        await backup.restore(preview);
        expect(deps.manga.entries.single.currentChapter, 7);
        expect(
          await File(deps.books.books.single.coverImagePath!).exists(),
          isTrue,
        );
        await received.delete();
        await AutomaticBackup.backupNow();
      });
      await tester.pumpWidget(const SizedBox());
      data.dispose();
      deps.dispose();
      debugPrint('AUTO_BACKUP_FOREGROUND_PASSED');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
