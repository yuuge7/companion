import 'dart:io';

import 'package:companion/main.dart';
import 'package:companion/core/library.dart';
import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_library.dart';
import 'package:companion/books/models/book.dart';
import 'package:companion/books/services/library_model.dart';
import 'package:companion/film/app_state.dart' as film;
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/manga/app_state.dart' as manga;
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'books/support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final (family, assets) in [
      ('Roboto', ['NotoSans-Regular.ttf']),
      ('sans-serif-condensed', ['Oswald-Medium.ttf', 'Oswald-SemiBold.ttf']),
      ('monospace', ['DMMono-Regular.ttf', 'DMMono-Medium.ttf']),
      ('Marquee', ['Oswald-Medium.ttf', 'Oswald-SemiBold.ttf']),
      (
        'Grotesk',
        ['Archivo-Regular.ttf', 'Archivo-Medium.ttf', 'Archivo-SemiBold.ttf'],
      ),
      ('Readout', ['DMMono-Regular.ttf', 'DMMono-Medium.ttf']),
      ('PlexSerif', ['IBMPlexSerif-Medium.ttf', 'IBMPlexSerif-SemiBold.ttf']),
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
  late Directory directory;
  late CompanionDependencies deps;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LibraryModel.platform, (_) async => null);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('companion-shell-');
    final storage = MemoryStorage()
      ..saved = [
        Book(
          id: 'b',
          title: 'The Left Hand of Darkness',
          author: 'Ursula K. Le Guin',
          totalPages: 304,
        ),
      ];
    final books = LibraryModel(storage: storage);
    await books.load();
    final mangaState = manga.AppState(MangaStore(preferences));
    await mangaState.add(
      MangaEntry(
        id: 'm',
        title: 'Witch Hat Atelier',
        currentChapter: 14,
        totalChapters: 80,
        addedAt: 1,
        lastUpdated: 0,
      ),
    );
    final filmState = film.AppState(await ShelfStore.open(memoryOnly: true));
    await filmState.add(
      ShelfEntry.fromJson({
        'id': 'f',
        'title': 'Arrival',
        'year': 2016,
        'kind': 'film',
        'runtime': 116,
        'director': 'Denis Villeneuve',
      }),
    );
    final anime = AnimeLibrary(directory);
    await anime.save(
      AnimeEntry(
        id: 'a',
        title: 'Frieren: Beyond Journey’s End',
        studio: 'Madhouse',
        year: 2023,
        season: 'Fall',
        currentEpisode: 14,
        totalEpisodes: 28,
        episodeMinutes: 24,
        status: AnimeStatus.watching,
        rating: 5,
      ),
    );
    deps = CompanionDependencies(
      books: books,
      settings: TestSettings(storage: storage),
      manga: mangaState,
      film: filmState,
      anime: anime,
      preferences: preferences,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.ionel.movie_companion/device'),
          (_) async => <String, dynamic>{},
        );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<void> select(WidgetTester tester, String label) async {
    final navigation = find.byType(NavigationBar);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text(label)).last,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Modes isolate libraries, preserve routes and share settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CompanionApp(dependencies: deps));
    await tester.pumpAndSettle();
    await select(tester, 'Manga');
    expect(find.text('Witch Hat Atelier'), findsWidgets);
    expect(find.text('Arrival'), findsNothing);
    await select(tester, 'Film');
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Witch Hat Atelier'), findsNothing);
    await select(tester, 'Anime');
    expect(find.text('Frieren: Beyond Journey’s End'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(
        find.byTooltip('Increase episodes for Frieren: Beyond Journey’s End'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      while (deps.anime.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(deps.anime.entries.single.currentEpisode, 15);
    await tester.pumpAndSettle();
    expect(deps.anime.entries.single.currentEpisode, 15);
    expect(deps.manga.entries.single.currentChapter, 14);
    expect(deps.film.entries.single.runtime, 116);
    expect(deps.books.books.single.totalPages, 304);
    await tester.tap(find.text('Frieren: Beyond Journey’s End'));
    await tester.pumpAndSettle();
    expect(find.text('Edit anime'), findsOneWidget);
    await select(tester, 'Manga');
    expect(find.text('Witch Hat Atelier'), findsWidgets);
    await select(tester, 'Anime');
    expect(find.text('Edit anime'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await select(tester, 'Settings');
    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('reading preferences'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Four mode screens render at phone size in light and dark', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CompanionApp(dependencies: deps));
    await tester.pumpAndSettle();
    for (final brightness in ['light', 'dark']) {
      deps.settings.mode = brightness == 'light'
          ? ThemeMode.light
          : ThemeMode.dark;
      // Settings is a ChangeNotifier; update uses the shared persistence path.
      await tester.runAsync(() => deps.settings.update({'theme': brightness}));
      await tester.pumpAndSettle();
      for (final label in ['Books', 'Manga', 'Film', 'Anime']) {
        await select(tester, label);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${label.toLowerCase()}_$brightness.png'),
        );
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  }, tags: ['golden']);

  testWidgets('Anime remains usable on narrow screens and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CompanionApp(dependencies: deps));
    await tester.pumpAndSettle();
    await select(tester, 'Anime');
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Shared rows keep page, chapter, viewing and episode actions separate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Create the queued book model in the widget test's async zone.
      final books = LibraryModel(storage: deps.books.storage);
      await books.load();
      deps.books.dispose();
      deps = CompanionDependencies(
        books: books,
        settings: deps.settings,
        manga: deps.manga,
        film: deps.film,
        anime: deps.anime,
        preferences: deps.preferences,
      );
      await tester.pumpWidget(CompanionApp(dependencies: deps));
      await tester.pumpAndSettle();
      Future<void> saveAction(Finder target, bool Function() saved) async {
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(saved(), isTrue);
      }

      await saveAction(
        find.text('Start reading'),
        () => deps.books.books.single.openSession != null && !deps.books.saving,
      );
      expect(
        deps.books.books.single.openSession,
        isNotNull,
        reason: deps.books.saveError,
      );
      await tester.tap(find.text('Set progress'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('progress-input')),
        '30',
      );
      await saveAction(
        find.text('Save page'),
        () =>
            deps.books.books.single.openSession?.currentPage == 30 &&
            !deps.books.saving,
      );
      expect(deps.books.books.single.openSession?.currentPage, 30);
      await select(tester, 'Manga');
      await saveAction(
        find.byTooltip('Increase chapters for Witch Hat Atelier'),
        () => deps.manga.entries.single.currentChapter == 15,
      );
      expect(deps.manga.entries.single.currentChapter, 15);
      await select(tester, 'Film');
      await saveAction(
        find.text('Mark seen'),
        () => deps.film.entries.single.plays == 1,
      );
      expect(deps.film.entries.single.plays, 1);
      expect(deps.film.entries.single.runtime, 116);
      expect(deps.books.books.single.openSession?.currentPage, 30);
      expect(deps.manga.entries.single.currentChapter, 15);
      expect(deps.anime.entries.single.currentEpisode, 14);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Every mode uses the same library, data and statistics interface',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(CompanionApp(dependencies: deps));
      await tester.pumpAndSettle();
      ThemeData? sharedTheme;
      for (final label in ['Books', 'Manga', 'Film', 'Anime']) {
        await select(tester, label);
        expect(find.byType(LibraryScreen), findsOneWidget);
        expect(find.byType(LibraryItemRow), findsOneWidget);
        expect(find.text('Add title'), findsOneWidget);
        expect(find.text('Filters'), findsOneWidget);
        final theme = Theme.of(tester.element(find.byType(LibraryItemRow)));
        sharedTheme ??= theme;
        expect(theme, sharedTheme);
        expect(theme.textTheme.titleLarge?.fontFamily, 'PlexSans');
        await tester.enterText(
          find.byKey(const ValueKey('library-search')),
          'no matching title',
        );
        await tester.pumpAndSettle();
        expect(find.text('No matching titles'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryItemRow), findsOneWidget);
        await tester.tap(find.byTooltip('$label tools'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Import & export'));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryDataPage), findsOneWidget);
        expect(find.text('Import backup'), findsOneWidget);
        expect(find.text('Export backup'), findsOneWidget);
        expect(find.text('Export CSV'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('$label statistics'));
        await tester.pumpAndSettle();
        expect(find.text('$label statistics'), findsOneWidget);
        expect(find.text('Titles'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'All editors share typography and controls while retaining their fields',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(CompanionApp(dependencies: deps));
      await tester.pumpAndSettle();
      for (final label in ['Books', 'Manga', 'Film', 'Anime']) {
        await select(tester, label);
        await tester.tap(find.byType(LibraryItemRow));
        await tester.pumpAndSettle();
        final bar = find.byType(AppBar).last;
        final theme = Theme.of(tester.element(bar));
        expect(
          theme.inputDecorationTheme.enabledBorder,
          isA<OutlineInputBorder>(),
        );
        expect(theme.textTheme.titleLarge?.fontFamily, 'PlexSans');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${label.toLowerCase()}_editor.png'),
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
    tags: ['golden'],
  );
}
