import 'package:flutter_test/flutter_test.dart';

import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/models/viewing.dart';
import 'package:companion/film/storage.dart';

void main() {
  test('parses a full backup export', () {
    const raw = '''
[
  {
    "id": "m1abc2def3",
    "title": "Heat",
    "year": 1995,
    "director": "Michael Mann",
    "runtime": 170,
    "posterUrl": "https://example.com/heat.jpg",
    "watchUrl": "https://example.com/watch/heat",
    "status": "seen",
    "rating": 5,
    "note": "The diner scene earns the other 168 minutes.",
    "plays": 3,
    "watchedAt": 1710000000000,
    "addedAt": 1700000000000,
    "lastUpdated": 1710000000000
  },
  {
    "id": "m4ghi5jkl6",
    "title": "Sátántangó",
    "year": 1994,
    "runtime": 439,
    "status": "watchlist",
    "addedAt": 1690000000000,
    "lastUpdated": 1695000000000
  }
]
''';
    final entries = ShelfStore.parseExport(raw);
    expect(entries, isNotNull);
    expect(entries!.length, 2);
    expect(entries[0].title, 'Heat');
    expect(entries[0].director, 'Michael Mann');
    expect(entries[0].runtime, 170);
    expect(entries[0].plays, 3);
    expect(entries[0].minutesSpent, 510);
    expect(entries[1].status, 'watchlist');
    expect(entries[1].plays, 0);
    expect(entries[1].director, '');
    expect(entries[1].watchedAt, isNull);
  });

  test('tolerates string numbers and missing fields', () {
    const raw = '''
[{"id":"x","title":"Stalker","year":"1979","runtime":"162","status":"seen"}]
''';
    final e = ShelfStore.parseExport(raw)!.single;
    expect(e.year, 1979);
    expect(e.runtime, 162);
    expect(e.rating, 0);
    expect(e.note, '');
    // A backup written before the rewatch counter existed still knows a
    // seen film was watched once.
    expect(e.plays, 1);
  });

  test('falls back to the watchlist for an unknown status', () {
    const raw = '[{"id":"x","title":"Solaris","status":"reading"}]';
    expect(ShelfStore.parseExport(raw)!.single.status, 'watchlist');
  });

  test('drops untitled rows and rejects non-array payloads', () {
    expect(ShelfStore.parseExport('[{"id":"x","title":"   "}]'), isEmpty);
    expect(ShelfStore.parseExport('{"not":"a list"}'), isNull);
    expect(ShelfStore.parseExport('garbage'), isNull);
  });

  test('parses a series, and defaults an unmarked entry to a film', () {
    const raw = '''
[
  {"id":"s1","kind":"series","title":"Mr. Robot","year":2015,
   "director":"Sam Esmail","runtime":45,"episodes":45,"watched":12,
   "status":"watchlist"},
  {"id":"s2","title":"Heat","runtime":170}
]
''';
    final entries = ShelfStore.parseExport(raw)!;
    expect(entries[0].isSeries, isTrue);
    expect(entries[0].episodes, 45);
    expect(entries[0].watched, 12);
    expect(entries[0].minutesSpent, 540);
    expect(entries[1].isSeries, isFalse);
    expect(entries[1].episodes, isNull);
  });

  test('a seen series with no episode tally is filled in from its run', () {
    const raw = '''
[{"id":"s1","kind":"series","title":"Mr. Robot","runtime":45,
  "episodes":45,"status":"seen"}]
''';
    final e = ShelfStore.parseExport(raw)!.single;
    expect(e.watched, 45);
    expect(e.plays, 1);
  });

  test('episode counts never survive on a film', () {
    const raw = '[{"id":"f1","title":"Heat","episodes":45,"watched":12}]';
    final e = ShelfStore.parseExport(raw)!.single;
    expect(e.episodes, isNull);
    expect(e.watched, 0);
  });

  test('an old backup dates what it has and shrugs at what it does not', () {
    const raw =
        '['
        '{"id":"a","title":"Heat","status":"seen","watchedAt":1710000000000},'
        '{"id":"b","title":"Solaris","status":"seen"}]';
    final entries = ShelfStore.parseExport(raw)!;
    // Backups predating precision only ever stored exact stamps.
    expect(entries[0].watchedPrecision, 'day');
    expect(entries[0].hasWatchedDate, isTrue);
    expect(entries[1].watchedPrecision, 'unknown');
    expect(entries[1].hasWatchedDate, isFalse);
  });

  test('a precision without a date is still unknown', () {
    const raw =
        '[{"id":"a","title":"Heat","status":"seen","watchedPrecision":"year"}]';
    expect(ShelfStore.parseExport(raw)!.single.watchedPrecision, 'unknown');
  });

  test('a counted backup becomes a log, dating only what it knew', () {
    // The old format recorded how many times and when the *last* one was.
    // The earlier viewings have no date on record, and inventing one would
    // be worse than admitting it.
    const raw =
        '['
        '{"id":"a","title":"Heat","status":"seen","plays":3,'
        '"watchedAt":1710000000000,"watchedPrecision":"day"}]';
    final e = ShelfStore.parseExport(raw)!.single;
    expect(e.plays, 3);
    expect(e.viewings.where((v) => v.isDated), hasLength(1));
    expect(e.watchedAt, 1710000000000);
    expect(e.watchedPrecision, 'day');
    expect(e.viewingsNewestFirst.last.isDated, isFalse);
  });

  test('a counted backup with no date at all still logs the viewings', () {
    const raw = '[{"id":"a","title":"Heat","status":"seen","plays":2}]';
    final e = ShelfStore.parseExport(raw)!.single;
    expect(e.plays, 2);
    expect(e.hasWatchedDate, isFalse);
  });

  test('a seen title from any backup has at least one viewing', () {
    const raw = '[{"id":"a","title":"Heat","status":"seen"}]';
    expect(ShelfStore.parseExport(raw)!.single.plays, 1);
  });

  test('a watchlist title from any backup has none', () {
    const raw = '[{"id":"a","title":"Heat"}]';
    expect(ShelfStore.parseExport(raw)!.single.plays, 0);
  });

  test('every viewing keeps its own date through a round trip', () {
    final e = ShelfEntry(
      id: 'a',
      title: 'Solaris',
      status: 'seen',
      viewings: [
        Viewing(at: DateTime(2019).millisecondsSinceEpoch, precision: 'year'),
        Viewing.undated(),
      ],
      addedAt: 1,
      lastUpdated: 2,
    );
    final back = ShelfStore.parseExport(ShelfStore.toExportJson([e]))!.single;
    expect(back.watchedPrecision, 'year');
    expect(back.toJson(), e.toJson());
  });

  test('round-trips a series through export JSON unchanged', () {
    final e = ShelfEntry(
      id: 'mr',
      kind: 'series',
      title: 'Mr. Robot',
      year: 2015,
      director: 'Sam Esmail',
      runtime: 45,
      episodes: 45,
      watched: 12,
      status: 'watchlist',
      addedAt: 1,
      lastUpdated: 2,
    );
    final back = ShelfStore.parseExport(ShelfStore.toExportJson([e]))!.single;
    expect(back.toJson(), e.toJson());
  });

  test('round-trips through export JSON unchanged', () {
    final e = ShelfEntry(
      id: 'abc',
      title: 'Chungking Express',
      year: 1994,
      director: 'Wong Kar-wai',
      runtime: 102,
      posterUrl: 'https://x/y.png',
      watchUrl: 'https://x/watch',
      status: 'seen',
      rating: 4,
      note: 'California Dreamin, on repeat.',
      viewings: [
        Viewing(
          at: DateTime(2024, 3, 6).millisecondsSinceEpoch,
          precision: 'day',
        ),
        Viewing(at: DateTime(2011).millisecondsSinceEpoch, precision: 'year'),
      ],
      addedAt: 1,
      lastUpdated: 2,
    );
    final json = ShelfStore.toExportJson([e]);
    final back = ShelfStore.parseExport(json)!.single;
    expect(back.toJson(), e.toJson());
  });
}
