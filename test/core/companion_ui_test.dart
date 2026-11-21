import 'package:companion/books/screens/add_edit_book_screen.dart';

import 'dart:io';

import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_library.dart';
import 'package:companion/anime/library_controller.dart';
import 'package:companion/books/library_controller.dart';
import 'package:companion/books/models/book.dart';
import 'package:companion/books/models/reading_session.dart';
import 'package:companion/books/screens/book_lookup_screen.dart';
import 'package:companion/books/services/book_lookup.dart';
import 'package:companion/books/services/library_model.dart';
import 'package:companion/core/app_frame.dart';
import 'package:companion/core/companion_data.dart';
import 'package:companion/core/automatic_backup.dart';
import 'package:companion/core/companion_backup_screen.dart';
import 'package:companion/core/companion_hub.dart';
import 'package:companion/core/library.dart';
import 'package:companion/core/physical_collection.dart';
import 'package:companion/film/app_state.dart' as film;
import 'package:companion/film/library_controller.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/models/viewing.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/manga/app_state.dart' as manga;
import 'package:companion/manga/library_controller.dart';
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../books/support/fakes.dart';

class _Lookup extends BookLookup {
  bool fail = false;
  @override
  Future<List<BookMetadata>> search(String query) async {
    if (fail) throw const FormatException('Connection unavailable. Try again.');
    return query == 'missing'
        ? []
        : [
            const BookMetadata(
              title: 'Matilda',
              author: 'Roald Dahl',
              isbn: '9780140328721',
              pages: 240,
            ),
          ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final (family, assets) in [
      ('Roboto', ['NotoSans-Regular.ttf']),
      (
        'PlexSans',
        [
          'IBMPlexSans-Regular.ttf',
          'IBMPlexSans-Medium.ttf',
          'IBMPlexSans-SemiBold.ttf',
        ],
      ),
      ('PlexMono', ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Medium.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final asset in assets) {
        loader.addFont(rootBundle.load('assets/fonts/$asset'));
      }
      await loader.load();
    }
  });
  late CompanionData data;
  late Directory directory;
  late List<LibraryController> controllers;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LibraryModel.platform, (_) async => null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('companion-ui-');
    final storage = MemoryStorage()
      ..saved = [
        Book(
          id: 'b',
          title: 'The Left Hand of Darkness',
          author: 'Ursula K. Le Guin',
          status: BookStatus.onHold,
          totalPages: 300,
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 5, 3),
          collection: const PhysicalCollection(
            ownership: Ownership.owned,
            shelf: 'Living room · shelf 2',
            lentTo: 'Ana',
          ),
          sessions: [
            ReadingSession(
              id: 's',
              startDate: DateTime(2025, 5, 1),
              currentPage: 240,
              progress: [
                ProgressEntry(
                  date: DateTime(2025, 5, 3),
                  page: 240,
                  fromPage: 210,
                ),
              ],
            ),
          ],
        ),
      ];
    final books = LibraryModel(storage: storage);
    await books.load();
    final mangaState = manga.AppState(MangaStore(prefs));
    await mangaState.add(
      MangaEntry(
        id: 'm',
        title: 'Witch Hat Atelier',
        addedAt: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        lastUpdated: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        collection: const PhysicalCollection(
          ownership: Ownership.owned,
          totalVolumes: 5,
          volumes: [1, 2, 4],
        ),
        history: [
          ReadEvent(
            at: DateTime(2025, 5, 3).millisecondsSinceEpoch,
            from: 10,
            to: 14,
          ),
        ],
      ),
    );
    final filmState = film.AppState(await ShelfStore.open(memoryOnly: true));
    final movie = ShelfEntry.blank()
      ..title = 'Arrival'
      ..runtime = 116;
    movie.addViewing(
      Viewing(
        at: DateTime(2025, 5, 3).millisecondsSinceEpoch,
        precision: 'day',
      ),
    );
    await filmState.add(movie);
    final anime = AnimeLibrary(directory);
    await anime.save(
      AnimeEntry(
        id: 'a',
        title: 'Frieren: Beyond Journey’s End',
        currentEpisode: 26,
        totalEpisodes: 28,
        status: AnimeStatus.onHold,
        addedAt: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        updatedAt: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      ),
    );
    data = CompanionData(
      books: books,
      settings: TestSettings(storage: storage),
      mangaLibrary: mangaState,
      filmLibrary: filmState,
      anime: anime,
      preferences: prefs,
    );
    controllers = [
      BookLibraryController(books, data.settings),
      MangaLibraryController(mangaState),
      FilmLibraryController(filmState),
      AnimeLibraryController(anime),
    ];
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    data.dispose();
    data.books.dispose();
    data.settings.dispose();
    data.mangaLibrary.dispose();
    data.filmLibrary.dispose();
    data.anime.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> mount(WidgetTester tester, {int tab = 0}) async {
    await tester.pumpWidget(
      CompanionFrame(
        library: data.books,
        settings: data.settings,
        home: CompanionHub(
          data: data,
          libraries: controllers,
          initialTab: tab,
          initialDay: DateTime(2025, 5, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'automatic backup controls show success, change schedule and retain failure details',
    (tester) async {
      final calls = <MethodCall>[];
      final status = <String, dynamic>{
        'enabled': true,
        'scheduled': true,
        'folder': 'Companion backups',
        'hours': 168,
        'lastBackup': DateTime(2026, 11, 21, 12).millisecondsSinceEpoch,
        'error': '',
        'running': false,
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AutomaticBackup.channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'status':
                return status;
              case 'setFrequency':
                status['hours'] = call.arguments;
                return null;
              case 'backupNow':
                status['error'] =
                    'Folder unavailable. Older backups were kept.';
                throw PlatformException(
                  code: 'backup_failed',
                  message: status['error'] as String,
                );
              case 'disable':
                status['enabled'] = false;
                return null;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AutomaticBackup.channel, null),
      );
      await tester.pumpWidget(
        CompanionFrame(
          library: data.books,
          settings: data.settings,
          home: CompanionBackupScreen(data: data),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<int>),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.method == 'setFrequency').single.arguments,
        24,
      );
      await tester.scrollUntilVisible(find.text('Back up now'), 180);
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      expect(
        find.text('Folder unavailable. Older backups were kept.'),
        findsWidgets,
      );
      expect(find.textContaining('Last successful backup:'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Turn off automatic backups'),
        180,
      );
      await tester.tap(find.text('Turn off automatic backups'));
      await tester.pumpAndSettle();
      expect(find.text('Choose automatic backup folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling the automatic folder picker does not enable or write a backup',
    (tester) async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AutomaticBackup.channel, (call) async {
            methods.add(call.method);
            return call.method == 'status'
                ? {'enabled': false, 'running': false}
                : false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AutomaticBackup.channel, null),
      );
      await tester.pumpWidget(
        CompanionFrame(
          library: data.books,
          settings: data.settings,
          home: CompanionBackupScreen(data: data),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Choose automatic backup folder'),
        180,
      );
      await tester.tap(find.text('Choose automatic backup folder'));
      await tester.pumpAndSettle();
      expect(methods, contains('chooseFolder'));
      expect(methods, isNot(contains('backupNow')));
      expect(find.text('Back up now'), findsNothing);
    },
  );

  testWidgets('diary date selection, mode filter, and combined review work', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester);
    expect(find.text('A day in your library'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Film'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Arrival'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Witch Hat Atelier'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Year in review'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Year in review'));
    await tester.pumpAndSettle();
    expect(find.text('Your year, across every shelf'), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new shared screens stay usable on narrow screens with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester);
      expect(tester.takeException(), isNull);
      for (final label in ['Rediscover', 'Collection', 'Activity']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Complete backup'));
      await tester.pumpAndSettle();
      expect(find.text('One file. Every shelf.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'collection entries open editors and volume validation prevents saving invalid ranges',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, tab: 2);
      await tester.tap(find.text('Witch Hat Atelier'));
      await tester.pumpAndSettle();
      expect(find.text('Edit manga'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Physical collection'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Physical collection'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Volumes on your shelf'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Volumes on your shelf'),
        '9-2',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit manga'), findsOneWidget);
      expect(find.textContaining('Volumes must be between'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'lookup reviews a result and handles no results and retryable errors',
    (tester) async {
      final lookup = _Lookup();
      await tester.pumpWidget(
        MaterialApp(home: BookLookupScreen(lookup: lookup)),
      );
      await tester.enterText(find.byType(TextField), 'Matilda');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Matilda'));
      await tester.pumpAndSettle();
      expect(find.text('Review edition'), findsOneWidget);
      expect(find.text('Use these details'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No books found'), findsOneWidget);
      lookup.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable. Try again.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('shared feature screens render in light and dark', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in ['light', 'dark']) {
      data.settings.mode = brightness == 'light'
          ? ThemeMode.light
          : ThemeMode.dark;
      await mount(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/diary_$brightness.png'),
      );
      await tester.tap(find.text('Year in review'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/review_$brightness.png'),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rediscover'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rediscover_$brightness.png'),
      );
      await tester.tap(find.text('Collection'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/collection_$brightness.png'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  }, tags: ['golden']);

  testWidgets(
    'lookup fills the editor and does not save until the book is reviewed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CompanionFrame(
          library: data.books,
          settings: data.settings,
          home: AddEditBookScreen(lookup: _Lookup()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find by title or scan ISBN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Matilda');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Matilda'));
      await tester.pumpAndSettle();
      expect(data.books.books, hasLength(1));
      await tester.ensureVisible(find.text('Use these details'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Use these details'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Add book'), findsOneWidget);
      expect(data.books.books, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, 'Title'))
            .controller!
            .text,
        'Matilda',
      );
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Save').first);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(
        data.books.books,
        hasLength(2),
        reason: '${data.books.saveError}, saving: ${data.books.saving}',
      );
      final saved = data.books.books.firstWhere((b) => b.title == 'Matilda');
      expect(saved.author, 'Roald Dahl');
      expect(saved.isbn, '9780140328721');
      expect(saved.totalPages, 240);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
