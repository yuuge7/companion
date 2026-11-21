import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:companion/core/library.dart';
import 'package:companion/manga/app_state.dart';
import 'package:companion/manga/importers.dart';
import 'package:companion/manga/library_controller.dart';
import 'package:companion/manga/models/manga_entry.dart';
import 'package:companion/manga/screens/import_preview.dart';
import 'package:companion/manga/storage.dart';
import 'package:companion/manga/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder row(String title) => find.text(title).first;

MangaEntry entry(
  String title, {
  int chapter = 0,
  int updated = 1000,
  ShelfStatus status = ShelfStatus.reading,
}) => MangaEntry(
  id: 'id-$title',
  title: title,
  currentChapter: chapter,
  status: status,
  addedAt: 1,
  lastUpdated: updated,
);

Future<AppState> stateWith(List<MangaEntry> items) async {
  SharedPreferences.setMockInitialValues({});
  final store = await MangaStore.open();
  await store.save(items);
  return AppState(store);
}

Future<void> pumpHome(WidgetTester tester, AppState state) async {
  final controller = MangaLibraryController(state);
  addTearDown(controller.dispose);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: LibraryScreen(controller: controller),
    ),
  );
}

void main() {
  testWidgets('manga dates can be edited, saved, reopened and cleared', (
    tester,
  ) async {
    final state = await stateWith([
      entry('Berserk', chapter: 10).copyWith(
        startedAt: DateTime(2020, 1, 2, 15).millisecondsSinceEpoch,
        finishedAt: DateTime(2021, 3, 4, 16).millisecondsSinceEpoch,
        history: const [ReadEvent(at: 1000, from: 0, to: 10)],
      ),
    ]);
    await pumpHome(tester, state);
    Future<void> open() async {
      await tester.tap(row('Berserk'));
      await tester.pumpAndSettle();
    }

    Future<void> change(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pump();
    }

    await open();
    await change('Started', '2019-02-03');
    await change('Finished', '2020-04-05');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      state.entries.single.startedAt,
      DateTime(2019, 2, 3).millisecondsSinceEpoch,
    );
    expect(
      state.entries.single.finishedAt,
      DateTime(2020, 4, 5).millisecondsSinceEpoch,
    );
    expect(state.entries.single.history, const [
      ReadEvent(at: 1000, from: 0, to: 10),
    ]);
    expect(
      (await MangaStore.open()).load().single.finishedAt,
      state.entries.single.finishedAt,
    );
    await open();
    await change('Started', '');
    await change('Finished', '');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(state.entries.single.startedAt, isNull);
    expect(state.entries.single.finishedAt, isNull);
  });

  testWidgets('invalid manga dates cannot save and calendar dates can', (
    tester,
  ) async {
    final state = await stateWith([entry('Berserk')]);
    await pumpHome(tester, state);
    await tester.tap(row('Berserk'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Started');
    await tester.ensureVisible(field);
    await tester.enterText(field, '2025-02-30');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Use a valid date: YYYY-MM-DD.'), findsOneWidget);
    await tester.ensureVisible(field);
    await tester.tap(find.byTooltip('Choose started date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(
      state.entries.single.startedAt,
      DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('import preview lists changes and returns the choice', (
    tester,
  ) async {
    final state = await stateWith([
      entry('Berserk', chapter: 300),
      entry('Monster', chapter: 162, updated: 9000),
    ]);
    final incoming = [
      entry('Berserk', chapter: 364, updated: 2000),
      entry('Monster', chapter: 100, updated: 1),
      entry('Vagabond', chapter: 5),
    ];
    final plan = state.planMerge(incoming);
    ImportMode? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportPreview(
                context,
                state: state,
                backup: ParsedBackup(BackupSource.mihon, incoming),
                plan: plan,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Import from Mihon?'), findsOneWidget);
    await tester.tap(find.text('Updated'));
    await tester.pumpAndSettle();
    expect(find.text('ch 300 → 364'), findsOneWidget);

    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    expect(result, ImportMode.merge);
  });

  testWidgets('a deleted title can be brought back', (tester) async {
    final state = await stateWith([entry('Berserk'), entry('Monster')]);
    await pumpHome(tester, state);

    await tester.tap(find.byTooltip('Actions for Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete title'));
    await tester.pumpAndSettle();

    expect(state.entries.map((e) => e.title), ['Monster']);
    expect(find.text('Berserk deleted.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(state.entries.map((e) => e.title), ['Berserk', 'Monster']);
  });

  testWidgets('long-press selects; bulk delete can be undone', (tester) async {
    final state = await stateWith([
      entry('Berserk'),
      entry('Monster'),
      entry('Vagabond'),
    ]);
    await pumpHome(tester, state);

    await tester.longPress(row('Berserk'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(row('Monster'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete selected'));
    await tester.pumpAndSettle();
    expect(state.entries.map((e) => e.title), ['Vagabond']);
    expect(find.text('2 manga updated.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(state.entries.length, 3);
  });

  testWidgets('bulk move puts titles on another shelf', (tester) async {
    final state = await stateWith([entry('Berserk'), entry('Monster')]);
    await pumpHome(tester, state);

    await tester.longPress(row('Berserk'));
    await tester.pump();
    await tester.tap(find.byTooltip('Select all visible titles'));
    await tester.pump();
    await tester.tap(find.byTooltip('Bulk actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to On hold'));
    await tester.pumpAndSettle();

    expect(state.countFor(ShelfStatus.onHold), 2);
  });

  testWidgets('chapter controls log and reverse progress', (tester) async {
    final state = await stateWith([entry('Berserk', chapter: 9)]);
    await pumpHome(tester, state);

    await tester.tap(find.byTooltip('Increase chapters for Berserk'));
    await tester.pumpAndSettle();
    expect(state.entries.single.currentChapter, 10);
    expect(state.entries.single.history.single.delta, 1);
    await tester.tap(find.byTooltip('Decrease chapters for Berserk'));
    await tester.pumpAndSettle();
    expect(state.entries.single.currentChapter, 9);
    expect(state.entries.single.history, isEmpty);
  });

  testWidgets('row actions move a title to read and back', (tester) async {
    final state = await stateWith([entry('Berserk', chapter: 9)]);
    await pumpHome(tester, state);

    await tester.tap(find.byTooltip('Actions for Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Read'));
    await tester.pumpAndSettle();
    expect(state.entries.single.status, ShelfStatus.read);

    await tester.tap(find.byTooltip('Actions for Berserk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Reading'));
    await tester.pumpAndSettle();
    expect(state.entries.single.status, ShelfStatus.reading);
  });

  testWidgets('an empty shelf shows the onboarding', (tester) async {
    final state = await stateWith([]);
    await pumpHome(tester, state);

    expect(find.text('Your manga library starts here'), findsOneWidget);
    expect(find.text('Import & export'), findsOneWidget);

    await tester.tap(find.text('Add title'));
    await tester.pumpAndSettle();
    expect(find.text('Add manga'), findsOneWidget);
  });

  testWidgets('adding a title already on the shelf warns', (tester) async {
    final state = await stateWith([entry('Kaguya-sama: Love Is War')]);
    await pumpHome(tester, state);

    await tester.tap(find.text('Add title'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'kaguya sama love is war',
    );
    await tester.pump();

    expect(
      find.textContaining('is already on your reading shelf'),
      findsOneWidget,
    );
    expect(find.text('Add anyway'), findsOneWidget);
  });

  testWidgets('every shelf has a filter', (tester) async {
    final state = await stateWith([
      entry('Berserk'),
      entry('Someday', status: ShelfStatus.planned),
    ]);
    await pumpHome(tester, state);

    for (final s in ShelfStatus.values) {
      expect(find.text('${s.label}  ${state.countFor(s)}'), findsOneWidget);
    }
    final planned = find.text('Plan to read  1');
    await tester.ensureVisible(planned);
    await tester.tap(planned);
    await tester.pump();
    expect(find.text('Someday'), findsWidgets);
    expect(find.text('Berserk'), findsNothing);
  });
}
