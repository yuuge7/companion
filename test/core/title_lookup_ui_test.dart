import 'dart:async';

import 'package:companion/anime/anime_entry.dart';
import 'package:companion/anime/anime_screen.dart';
import 'package:companion/core/theme.dart';
import 'package:companion/core/title_lookup.dart';
import 'package:companion/core/title_lookup_screen.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/screens/edit_sheet.dart' as film_editor;
import 'package:companion/manga/app_state.dart' as manga;
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/screens/edit_sheet.dart' as manga_editor;
import 'package:companion/manga/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Lookup extends TitleLookup {
  bool fail = false, missing = false;
  Completer<void>? pending;
  @override
  Future<List<TitleMetadata>> search(TitleCatalog catalog, String query) async {
    if (pending != null) await pending!.future;
    if (fail) throw const FormatException('Catalog unavailable. Try again.');
    return missing
        ? []
        : [
            TitleMetadata(
              catalog: catalog,
              id: '1',
              title: 'Catalog title',
              sourceUrl: '',
              creator: 'Catalog creator',
              year: 2023,
              minutes: 24,
              chapters: 100,
              episodes: 28,
              format: 'ONA',
            ),
          ];
  }

  @override
  Future<TitleMetadata> details(TitleMetadata item) async {
    if (fail) throw const FormatException('Details unavailable. Try again.');
    return item;
  }
}

void main() {
  Future<void> select(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Catalog title'));
    await tester.pumpAndSettle();
    expect(find.text('Review title'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Use these details'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use these details'));
    await tester.pumpAndSettle();
  }

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCompanionTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final catalog in TitleCatalog.values) {
    testWidgets(
      '${catalog.name} lookup requires review before returning metadata',
      (tester) async {
        TitleMetadata? result;
        await host(tester, (context) async {
          result = await Navigator.push<TitleMetadata>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TitleLookupScreen(catalog: catalog, lookup: _Lookup()),
            ),
          );
        });
        expect(result, isNull);
        expect(find.text('Use these details'), findsNothing);
        await select(tester);
        expect(result?.catalog, catalog);
        expect(result?.title, 'Catalog title');
      },
    );
  }

  testWidgets(
    'loading, empty, failed search, retry and failed selection remain usable',
    (tester) async {
      final lookup = _Lookup()..pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: TitleLookupScreen(catalog: TitleCatalog.anime, lookup: lookup),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Search'))
            .onPressed,
        isNull,
      );
      lookup.missing = true;
      lookup.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('No titles found.'), findsOneWidget);
      lookup
        ..pending = null
        ..fail = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      expect(find.text('Catalog unavailable. Try again.'), findsOneWidget);
      lookup
        ..fail = false
        ..missing = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      lookup.fail = true;
      await tester.tap(find.widgetWithText(ListTile, 'Catalog title'));
      await tester.pumpAndSettle();
      expect(find.text('Details unavailable. Try again.'), findsOneWidget);
      expect(find.text('Use these details'), findsNothing);
      lookup.fail = false;
      await tester.tap(find.widgetWithText(ListTile, 'Catalog title'));
      await tester.pumpAndSettle();
      expect(find.text('Review title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving an in-flight lookup does not update a disposed screen', (
    tester,
  ) async {
    final lookup = _Lookup()..pending = Completer<void>();
    await host(
      tester,
      (context) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TitleLookupScreen(catalog: TitleCatalog.film, lookup: lookup),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pump();
    await tester.tap(find.text('Add manually'));
    await tester.pump(const Duration(milliseconds: 400));
    lookup.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'anime metadata fills the editor and preserves progress, notes and rating',
    (tester) async {
      AnimeEntry? saved;
      await host(tester, (context) async {
        saved = await Navigator.push<AnimeEntry>(
          context,
          MaterialPageRoute(
            builder: (_) => AnimeEditor(
              lookup: _Lookup(),
              initial: AnimeEntry(
                title: 'Draft',
                currentEpisode: 7,
                status: AnimeStatus.watching,
                rating: 4.5,
                note: 'Keep my notes',
                rewatches: 2,
              ),
            ),
          ),
        );
      });
      await tester.tap(find.text('Find an anime'));
      await tester.pumpAndSettle();
      await select(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Catalog title');
      expect(saved?.animeFormat, AnimeFormat.ona);
      expect(saved?.studio, 'Catalog creator');
      expect(saved?.currentEpisode, 7);
      expect(saved?.totalEpisodes, 28);
      expect(saved?.status, AnimeStatus.watching);
      expect(saved?.rating, 4.5);
      expect(saved?.rewatches, 2);
      expect(saved?.note, 'Keep my notes');
    },
  );

  testWidgets(
    'manga metadata fills title and chapters without changing reading history',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = manga.AppState(
        MangaStore(await SharedPreferences.getInstance()),
      );
      addTearDown(state.dispose);
      final initial = MangaEntry(
        id: 'm',
        title: 'Draft',
        currentChapter: 7,
        addedAt: 1,
        lastUpdated: 1,
        history: const [ReadEvent(at: 1, from: 0, to: 7)],
      );
      MangaEntry? saved;
      await host(tester, (context) async {
        saved = await manga_editor.showEditSheet(
          context,
          state: state,
          initial: initial,
          fullPage: true,
          lookup: _Lookup(),
        );
      });
      await tester.tap(find.text('Find a manga'));
      await tester.pumpAndSettle();
      await select(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Catalog title');
      expect(saved?.currentChapter, 7);
      expect(saved?.totalChapters, 100);
      expect(saved?.history.single.at, 1);
      expect(saved?.history.single.to, 7);
    },
  );

  testWidgets('film metadata preserves viewing logs and notes', (tester) async {
    final initial = ShelfEntry.blank()
      ..title = 'Draft'
      ..note = 'Keep my notes'
      ..rating = 4;
    ShelfEntry? saved;
    await host(tester, (context) async {
      saved = await film_editor.showEditSheet(
        context,
        initial: initial,
        fullPage: true,
        lookup: _Lookup(),
      );
    });
    await tester.tap(find.text('Find a film'));
    await tester.pumpAndSettle();
    await select(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved?.title, 'Catalog title');
    expect(saved?.director, 'Catalog creator');
    expect(saved?.runtime, 24);
    expect(saved?.year, 2023);
    expect(saved?.rating, 4);
    expect(saved?.note, 'Keep my notes');
    expect(saved?.viewings, isEmpty);
  });

  testWidgets('lookup remains usable at narrow width and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCompanionTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: TitleLookupScreen(catalog: TitleCatalog.anime, lookup: _Lookup()),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Catalog title'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Catalog title'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Use these details'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog totals cannot reduce saved series progress', (
    tester,
  ) async {
    final initial = ShelfEntry.blank()
      ..kind = 'series'
      ..title = 'Draft'
      ..episodes = 60
      ..watched = 50
      ..seasons = [30, 30];
    ShelfEntry? saved;
    await host(tester, (context) async {
      saved = await film_editor.showEditSheet(
        context,
        initial: initial,
        fullPage: true,
        lookup: _Lookup(),
      );
    });
    await tester.tap(find.text('Find a series'));
    await tester.pumpAndSettle();
    await select(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved?.watched, 50);
    expect(saved?.episodes, 60);
    expect(saved?.seasons, [30, 30]);
  });
}
