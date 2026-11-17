import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:companion/film/app_state.dart';
import 'package:companion/film/diagnostics.dart';
import 'package:companion/film/import_plan.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/models/viewing.dart';
import 'package:companion/film/shelf_filter.dart';
import 'package:companion/film/storage.dart';

ShelfEntry entry(String title, {String? id, int updated = 10}) => ShelfEntry(
  id: id ?? title,
  title: title,
  year: 1995,
  runtime: 90,
  addedAt: 1,
  lastUpdated: updated,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('diagnostics are bounded and never copy sensitive error payloads', () {
    for (var i = 0; i < 500; i++) {
      Diagnostics.record(
        StateError('SECRET title https://private.example/'),
        StackTrace.current,
        source: 'test',
      );
    }
    expect(Diagnostics.report, isNot(contains('SECRET')));
    expect(Diagnostics.report, isNot(contains('private.example')));
    expect(Diagnostics.report.length, lessThan(25000));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'atomic migration, queued writes, and an interrupted temp file',
    () async {
      final dir = await Directory.systemTemp.createTemp('screen-store-');
      addTearDown(() => dir.delete(recursive: true));
      SharedPreferences.setMockInitialValues({
        ShelfStore.legacyKey: jsonEncode([entry('Legacy').toJson()]),
      });
      final store = await ShelfStore.open(directory: dir);
      final state = AppState(store);
      expect(state.entries.single.title, 'Legacy');
      await store.save(state.entries);
      await Future.wait([
        store.save([entry('First')]),
        store.save([entry('Last')]),
      ]);
      await File('${dir.path}/shelf-v2.json.tmp').writeAsString('{truncated');
      final reopened = await ShelfStore.open(directory: dir);
      expect(reopened.load().single.title, 'Last');
      expect(
        (await SharedPreferences.getInstance()).getString(ShelfStore.legacyKey),
        isNotNull,
      );
    },
  );

  test('a corrupt primary recovers the previous committed shelf', () async {
    final dir = await Directory.systemTemp.createTemp('screen-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final store = await ShelfStore.open(directory: dir);
    await store.save([entry('Recover me')]);
    await store.save([entry('Most recent')]);
    await File('${dir.path}/shelf-v2.json').writeAsString('broken');
    final next = await ShelfStore.open(directory: dir);
    expect(next.load().single.title, 'Recover me');
    expect(next.recovered, isTrue);
    expect(next.loadFailed, isFalse);
  });

  test(
    'a failed commit rolls back the shelf and never replaces the good file',
    () async {
      final dir = await Directory.systemTemp.createTemp('screen-failed-');
      addTearDown(() => dir.delete(recursive: true));
      final store = await ShelfStore.open(directory: dir);
      final state = AppState(store);
      await state.add(entry('Safe'));
      await Directory('${dir.path}/shelf-v2.json.tmp').create();
      await expectLater(
        state.remove('Safe'),
        throwsA(isA<FileSystemException>()),
      );
      expect(state.entries.single.title, 'Safe');
      expect(state.trash, isEmpty);
      final next = await ShelfStore.open(directory: dir);
      expect(next.load().single.title, 'Safe');
    },
  );

  test('damaged storage cannot be silently replaced by an add', () async {
    SharedPreferences.setMockInitialValues({ShelfStore.legacyKey: '{broken'});
    final state = AppState(await ShelfStore.open(memoryOnly: true));
    expect(state.loadFailed, isTrue);
    await expectLater(state.add(entry('New')), throwsStateError);
    expect(state.entries, isEmpty);
  });

  test(
    'trash survives restart, expires after 30 days and restores history',
    () async {
      final store = await ShelfStore.open(memoryOnly: true);
      final state = AppState(store);
      final e = entry('History')
        ..viewings = [
          Viewing(
            at: DateTime(2024).millisecondsSinceEpoch,
            precision: 'year',
            location: 'cinema',
            company: 'Alex',
          ),
        ];
      await state.add(e);
      await state.remove(e.id);
      final restarted = AppState(await ShelfStore.open(memoryOnly: true));
      expect(restarted.entries, isEmpty);
      expect(restarted.trash.single.daysLeft, 30);
      await restarted.restoreTrash(restarted.trash.single);
      expect(restarted.entries.single.toJson(), e.toJson());
      expect(restarted.trash, isEmpty);
      final expired = TrashEntry(
        entry('Old'),
        DateTime.now()
            .subtract(const Duration(days: 31))
            .millisecondsSinceEpoch,
      );
      expect(expired.daysLeft, 0);
    },
  );

  test('merge classifications protect newer local history and equal-date conflicts', () async {
    final local = [
      entry('Newer local', updated: 20),
      entry('Newer incoming'),
      entry('Same'),
      entry('Equal'),
    ];
    final incoming = [
      entry('Newer local')..note = 'older',
      entry('Newer incoming', updated: 20)..note = 'new',
      entry('Same'),
      entry('Equal')..note = 'different',
      entry('New'),
    ];
    final plan = ImportPlan(local, incoming);
    expect(plan.count(ImportChange.added), 1);
    expect(plan.count(ImportChange.updated), 1);
    expect(plan.count(ImportChange.unchanged), 1);
    expect(plan.count(ImportChange.conflict), 2);
    final state = AppState(await ShelfStore.open(memoryOnly: true));
    for (final e in local) {
      await state.add(e);
    }
    await state.applyImport(plan, replace: false);
    expect(state.entries.firstWhere((e) => e.title == 'Newer local').note, '');
    expect(
      state.entries.firstWhere((e) => e.title == 'Newer incoming').note,
      'new',
    );
    expect(state.entries.firstWhere((e) => e.title == 'Equal').note, '');
    await state.restoreSnapshot();
    expect(
      state.entries.map((e) => e.title).toSet(),
      local.map((e) => e.title).toSet(),
    );
    await state.restoreSnapshot();
    expect(state.entries.length, 5);
  });

  test('conflicts can be explicitly resolved incoming; replace and snapshot survive restart', () async {
    final state = AppState(await ShelfStore.open(memoryOnly: true));
    await state.add(entry('Keep me', updated: 100));
    final plan = ImportPlan(state.entries, [
      entry('Keep me', updated: 1)..note = 'chosen',
    ]);
    plan.rows.single.useIncoming = true;
    await state.applyImport(plan, replace: false);
    expect(state.entries.single.note, 'chosen');
    await state.importEntries([entry('Replacement')], replace: true);
    final restarted = AppState(await ShelfStore.open(memoryOnly: true));
    expect(restarted.hasSnapshot, isTrue);
    expect(restarted.trash.single.entry.note, 'chosen');
    await restarted.restoreSnapshot();
    expect(restarted.entries.single.title, 'Keep me');
    expect(restarted.entries.single.note, 'chosen');
  });

  test('undated old backups never overwrite a timestamped local version', () {
    final old = ShelfStore.parseExport(
      '[{"id":"Heat","title":"Heat","note":"old"}]',
    )!.single;
    final plan = ImportPlan([entry('Heat', updated: 100)], [old]);
    expect(plan.rows.single.change, ImportChange.conflict);
    expect(plan.rows.single.useIncoming, isFalse);
  });

  test('envelope and CSV retain tags, seasons, viewing details and escape spreadsheet formulas', () {
    final e = entry('=FORMULA,"title"')
      ..kind = 'series'
      ..episodes = 20
      ..tags = ['family', 'cinema']
      ..seasons = [10, 10]
      ..viewings = [
        Viewing(
          at: DateTime(2024, 3).millisecondsSinceEpoch,
          precision: 'month',
          location: 'cinema',
          company: 'Sam',
        ),
      ];
    final raw = ShelfStore.toExportJson([e]);
    final envelope = jsonDecode(raw) as Map;
    expect(
      envelope.keys,
      containsAll([
        'app',
        'schemaVersion',
        'exportedAt',
        'appVersion',
        'count',
        'entries',
      ]),
    );
    expect(ShelfStore.parseExport(raw)!.single.toJson(), e.toJson());
    final csv = ShelfStore.toCsv([e]);
    expect(csv, contains("'=FORMULA,"));
    expect(csv, contains('""title""'));
    expect(csv, contains('cinema'));
    expect(csv, contains('Sam'));
  });

  test('combined filters, time budget and season progress agree', () {
    final e = entry('Series')
      ..kind = 'series'
      ..episodes = 28
      ..seasons = [10, 10, 8]
      ..watched = 14
      ..runtime = 45
      ..tags = ['family']
      ..rating = 4;
    expect(e.seasonProgress, 'S2 E4');
    expect(e.nextEpisode, 'S2 E5');
    expect(e.episodesThatFit(100), 2);
    expect(e.episodesThatFit(10000), 14);
    final filter = ShelfFilter()
      ..kind = 'series'
      ..tag = 'family'
      ..yearFrom = 1990
      ..yearTo = 2000
      ..minRating = 4
      ..minutes = 100;
    expect(filter.matches(e), isTrue);
    filter.minutes = 30;
    expect(filter.matches(e), isFalse);
    filter.minutes = 100;
    e.year = null;
    expect(filter.matches(e), isFalse);
  });

  test('bulk move, tag, and trash operate on the selected ids only', () async {
    final state = AppState(await ShelfStore.open(memoryOnly: true));
    for (final name in ['A', 'B', 'C']) {
      await state.add(entry(name));
    }
    await state.bulk({'A', 'B'}, status: 'seen', tags: ['family']);
    expect(state.countFor('seen'), 2);
    expect(
      state.entries
          .where((e) => e.isSeen)
          .every((e) => e.plays == 1 && e.tags.contains('family')),
      isTrue,
    );
    await state.bulk({'A', 'B'}, delete: true);
    expect(state.entries.single.id, 'C');
    expect(state.trash.length, 2);
  });

  test(
    'year review excludes unknown precision and partial series progress',
    () {
      final e = entry('Film')
        ..viewings = [
          Viewing(at: DateTime(2024).millisecondsSinceEpoch, precision: 'year'),
          Viewing(
            at: DateTime(2024, 3).millisecondsSinceEpoch,
            precision: 'month',
          ),
          Viewing.undated(),
          Viewing(at: DateTime(2023).millisecondsSinceEpoch, precision: 'year'),
        ];
      final review = YearReview(2024, [
        e,
        entry('Partial series')
          ..kind = 'series'
          ..watched = 5,
      ]);
      expect(review.films, 2);
      expect(review.series, 0);
      expect(review.minutes, 180);
    },
  );

  test(
    'import report includes each malformed row, preserving valid neighbors',
    () {
      final document = ShelfStore.parseDocument(
        jsonEncode([
          entry('Good').toJson(),
          null,
          4,
          {'title': ''},
          {'title': 'Bad', 'rating': []},
          {
            'title': 'Bad viewings',
            'viewings': ['no'],
          },
          {
            'title': 'Bad tags',
            'tags': [4],
          },
          {
            'title': 'Bad seasons',
            'seasons': [-4],
          },
          {'title': 'Huge count', 'plays': 999999999},
          entry('End').toJson(),
        ]),
      );
      // Numeric fields remain tolerant, but collections and strings must have
      // their declared shape. A wrong rating collection is reported, too.
      expect(document.entries.map((e) => e.title), ['Good', 'End']);
      expect(document.issues.map((e) => e.row), [2, 3, 4, 5, 6, 7, 8, 9]);
    },
  );

  test(
    'bounded importer survives garbage, truncation, huge and wrong-type inputs',
    () {
      final random = Random(7341);
      for (var i = 0; i < 1000; i++) {
        final garbage = String.fromCharCodes(
          List.generate(random.nextInt(500), (_) => random.nextInt(128)),
        );
        expect(() => ShelfStore.parseDocument(garbage), returnsNormally);
        final values = [null, true, [], {}, 'text', 1e200, -999999999999999999];
        final row = {
          'title': 'Fuzz $i',
          for (final field in [
            'id',
            'runtime',
            'episodes',
            'watched',
            'plays',
            'lastUpdated',
            'viewings',
            'tags',
            'year',
          ])
            field: values[random.nextInt(values.length)],
        };
        expect(
          () => ShelfStore.parseDocument(jsonEncode([row])),
          returnsNormally,
        );
      }
      expect(
        ShelfStore.parseDocument('x' * (ShelfStore.maxImportBytes + 1)).valid,
        isFalse,
      );
      final valid = ShelfStore.toExportJson([entry('A')]);
      for (var i = 0; i < valid.length; i += 11) {
        expect(
          () => ShelfStore.parseDocument(valid.substring(0, i)),
          returnsNormally,
        );
      }
      expect(
        ShelfStore.parseDocument(
          '{"app":"Screen Companion","schemaVersion":999,"entries":[]}',
        ).valid,
        isFalse,
      );
    },
  );

  test(
    '5,000 titles filter and sort without eagerly building row widgets',
    () async {
      final state = AppState(await ShelfStore.open(memoryOnly: true));
      state.entries = List.generate(
        5000,
        (i) => entry('Film $i', id: '$i')
          ..runtime = 30 + i % 180
          ..director = 'Maker ${i % 10}',
      );
      final watch = Stopwatch()..start();
      final visible = state.visible(
        'watchlist',
        'maker 7',
        filter: ShelfFilter()..minutes = 100,
      );
      watch.stop();
      expect(visible, isNotEmpty);
      expect(visible.every((e) => e.runtime! <= 100), isTrue);
      expect(visible.first.runtime, lessThanOrEqualTo(visible.last.runtime!));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    },
  );
}
