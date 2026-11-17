import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:companion/core/library.dart';
import 'package:companion/film/app_state.dart';
import 'package:companion/film/library_controller.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/screens/edit_sheet.dart';
import 'package:companion/film/screens/import_sheet.dart';
import 'package:companion/film/screens/settings_sheet.dart';
import 'package:companion/film/screens/stats_sheet.dart';
import 'package:companion/film/storage.dart';
import 'package:companion/film/theme.dart';

Future<AppState> sampleState({bool big = false}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(await ShelfStore.open(memoryOnly: true));
  state.entries = [
    ShelfEntry(
      id: 'robot',
      title: 'Mr. Robot',
      kind: 'series',
      year: 2015,
      director: 'Sam Esmail',
      runtime: 45,
      episodes: 45,
      watched: 14,
      seasons: [10, 12, 10, 13],
      tags: ['with family'],
      addedAt: 1,
      lastUpdated: 10,
    ),
    ShelfEntry(
      id: 'heat',
      title: 'Heat',
      year: 1995,
      director: 'Michael Mann',
      runtime: 170,
      tags: ['cinema only'],
      addedAt: 1,
      lastUpdated: 20,
    ),
    ShelfEntry(
      id: 'unknown',
      title: 'A title without a runtime',
      addedAt: 1,
      lastUpdated: 10,
    ),
    if (big)
      ...List.generate(
        4997,
        (i) => ShelfEntry(
          id: 'large-$i',
          title: 'Large shelf $i',
          runtime: 80 + i % 90,
          addedAt: 1,
          lastUpdated: 10,
        ),
      ),
  ];
  return state;
}

Future<void> loadFonts() async {
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  for (final (family, assets) in [
    (
      'PlexSans',
      [
        'IBMPlexSans-Regular.ttf',
        'IBMPlexSans-Medium.ttf',
        'IBMPlexSans-SemiBold.ttf',
      ],
    ),
    ('PlexMono', ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Medium.ttf']),
    ('Marquee', ['Oswald-Medium.ttf', 'Oswald-SemiBold.ttf']),
    ('Readout', ['DMMono-Regular.ttf', 'DMMono-Medium.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load('assets/fonts/$asset'));
    }
    await loader.load();
  }
}

Future<void> pumpShelf(
  WidgetTester tester,
  AppState state, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = FilmLibraryController(state);
  addTearDown(controller.dispose);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: LibraryScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.ionel.movie_companion/device'),
          (call) async =>
              call.method == 'backupStatus' ? {'enabled': false} : null,
        );
  });

  for (final brightness in Brightness.values) {
    final mode = brightness.name;
    // These font-loaded baselines were captured on Windows. Keep exact
    // comparisons on that host; both CI and releases run the golden job.
    testWidgets(
      'edit, settings, stats and import in $mode',
      (tester) async {
        final state = await sampleState();
        await pumpShelf(tester, state, brightness: brightness);
        // The four-section goldens cover the current library screen.
        final context = tester.element(find.byType(LibraryScreen));
        showEditSheet(context, initial: state.entries.first, state: state);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/edit_$mode.png'),
        );
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        showSettingsSheet(context, state);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_$mode.png'),
        );
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        showStatsSheet(context, state);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/stats_$mode.png'),
        );
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        showImportSheet(
          context,
          state,
          ImportDocument([
            state.entries[1].copy()
              ..lastUpdated = 1
              ..note = 'Older incoming version',
          ], const []),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Heat').last);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/import_$mode.png'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      tags: ['golden'],
      skip: !Platform.isWindows,
    );
  }

  testWidgets('time budget, pick, search and selection work together', (
    tester,
  ) async {
    final state = await sampleState();
    await pumpShelf(tester, state);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          )
          .first,
      '100',
    );
    await tester.scrollUntilVisible(
      find.text('Apply filters'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Heat'), findsNothing);
    expect(find.text('14 / 45 episodes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'robot');
    await tester.pumpAndSettle();
    expect(find.text('Mr. Robot'), findsOneWidget);
    await tester.tap(find.byTooltip('Film tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick for me'));
    await tester.pumpAndSettle();
    expect(find.text('Open title'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions for Mr. Robot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete title'));
    await tester.pumpAndSettle();
    expect(state.entries.any((e) => e.id == 'robot'), isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(state.entries.any((e) => e.id == 'robot'), isTrue);
    await tester.longPress(find.text('Mr. Robot'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete selected'));
    await tester.pumpAndSettle();
    expect(state.entries.any((e) => e.id == 'robot'), isFalse);
  });

  testWidgets('duplicate warning preserves the editor and can be cancelled', (
    tester,
  ) async {
    final state = await sampleState();
    await pumpShelf(tester, state);
    final context = tester.element(find.byType(LibraryScreen));
    final duplicate = state.entries[1].copy()..id = 'another';
    showEditSheet(context, initial: duplicate, state: state);
    await tester.pumpAndSettle();
    final save = find.text('Save changes');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Already on your shelf'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets(
    'active filters and editor validation remain visible with large text',
    (tester) async {
      final state = await sampleState();
      await pumpShelf(tester, state, width: 360, scale: 1.6);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            )
            .first,
        '100',
      );
      await tester.scrollUntilVisible(
        find.text('Apply filters'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filters on'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(LibraryScreen));
      showEditSheet(context, initial: state.entries.first, state: state);
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            )
            .at(2),
        '-2',
      );
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.text('Runtime needs a positive number of minutes.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('5,000 rows stay lazy and large text fits a narrow shelf', (
    tester,
  ) async {
    final state = await sampleState(big: true);
    await pumpShelf(tester, state, width: 360, scale: 1.5);
    expect(find.text('Large shelf 4996'), findsNothing);
    expect(find.byKey(const ValueKey('heat')), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
