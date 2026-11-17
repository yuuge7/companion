import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:companion/film/app_state.dart';
import 'package:companion/film/format.dart';
import 'package:companion/film/models/shelf_entry.dart';
import 'package:companion/film/models/viewing.dart';
import 'package:companion/film/storage.dart';

ShelfEntry film(
  String title, {
  int? runtime,
  String status = 'watchlist',
  int plays = 0,
  int rating = 0,
  int? year,
  String kind = 'film',
  int? episodes,
  int watched = 0,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return ShelfEntry(
    // Real ids, so merge tests exercise the title-and-year fallback rather
    // than colliding on a name used as a key.
    id: ShelfEntry.newId(),
    title: title,
    kind: kind,
    episodes: episodes,
    watched: watched,
    runtime: runtime,
    status: status,
    viewings: List.generate(plays, (_) => Viewing.undated()),
    rating: rating,
    year: year,
    addedAt: now,
    lastUpdated: now,
  );
}

Future<AppState> stateWith(List<ShelfEntry> entries) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(await ShelfStore.open(memoryOnly: true));
  for (final e in entries) {
    await state.add(e);
  }
  return state;
}

ShelfEntry series(
  String title, {
  int? runtime,
  int? episodes,
  int watched = 0,
  String status = 'watchlist',
  int plays = 0,
}) => film(
  title,
  kind: 'series',
  runtime: runtime,
  episodes: episodes,
  watched: watched,
  status: status,
  plays: plays,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runtime brackets', () {
    test('band the evening, not the catalogue', () {
      expect(film('a', runtime: 88).lengthBand, 'UNDER 90 MINUTES');
      expect(film('a', runtime: 90).lengthBand, '90 TO 120 MINUTES');
      expect(film('a', runtime: 119).lengthBand, '90 TO 120 MINUTES');
      expect(film('a', runtime: 120).lengthBand, '2 TO 2½ HOURS');
      expect(film('a', runtime: 170).lengthBand, 'OVER 2½ HOURS');
      expect(film('a').lengthBand, 'RUNTIME UNKNOWN');
    });
  });

  group('shelf order', () {
    test('the watchlist opens shortest first, unmeasured last', () async {
      final state = await stateWith([
        film('Long', runtime: 201),
        film('Unknown'),
        film('Short', runtime: 84),
        film('Middle', runtime: 122),
      ]);
      expect(state.visible('watchlist', '').map((e) => e.title).toList(), [
        'Short',
        'Middle',
        'Long',
        'Unknown',
      ]);
    });

    test('search matches the director as well as the title', () async {
      final state = await stateWith([
        film('Heat')..director = 'Michael Mann',
        film('Solaris')..director = 'Andrei Tarkovsky',
      ]);
      expect(state.visible('watchlist', 'tarkov').single.title, 'Solaris');
      expect(state.visible('watchlist', 'hea').single.title, 'Heat');
    });
  });

  group('viewings', () {
    test('marking a film seen dates it and counts one viewing', () async {
      final state = await stateWith([film('Heat', runtime: 170)]);
      final e = state.entries.single;
      await state.markSeen(e);
      expect(e.status, 'seen');
      expect(e.plays, 1);
      expect(e.watchedAt, isNotNull);
      expect(state.minutesWatched, 170);
    });

    test('a rewatch costs the runtime again', () async {
      final state = await stateWith([
        film('Heat', runtime: 170, status: 'seen', plays: 1),
      ]);
      await state.watchAgain(state.entries.single);
      expect(state.entries.single.plays, 2);
      expect(state.minutesWatched, 340);
      expect(state.rewatches, 1);
    });

    test('undoing a viewing stops at one, because seen is seen', () async {
      final state = await stateWith([
        film('Heat', runtime: 170, status: 'seen', plays: 2),
      ]);
      final e = state.entries.single;
      await state.undoPlay(e);
      expect(e.plays, 1);
      await state.undoPlay(e);
      expect(e.plays, 1);
    });

    test('moving to seen through the menu still stamps the log', () async {
      final state = await stateWith([film('Heat', runtime: 170)]);
      await state.setStatus(state.entries.single, 'seen');
      expect(state.entries.single.watchedAt, isNotNull);
      expect(state.entries.single.plays, 1);
    });

    test('a watchlist film costs nothing until it is watched', () async {
      final state = await stateWith([film('Heat', runtime: 170)]);
      expect(state.minutesWatched, 0);
      expect(state.minutesQueued, 170);
    });
  });

  group('tallies', () {
    test('the queue reports how much of it is unmeasured', () async {
      final state = await stateWith([
        film('Measured', runtime: 100),
        film('Unmeasured'),
      ]);
      expect(state.minutesQueued, 100);
      expect(state.unmeasuredQueued, 1);
    });

    test('average rating counts only rated films on the seen shelf', () async {
      final state = await stateWith([
        film('A', status: 'seen', plays: 1, rating: 5),
        film('B', status: 'seen', plays: 1, rating: 3),
        film('C', status: 'seen', plays: 1),
        film('D', status: 'watchlist', rating: 1),
      ]);
      expect(state.averageRating, 4);
    });

    test('earliest year looks only at what has been seen', () async {
      final state = await stateWith([
        film('Old', status: 'seen', plays: 1, year: 1927),
        film('Older but unwatched', year: 1902),
      ]);
      expect(state.earliestYearSeen, 1927);
    });
  });

  group('series', () {
    test('band by the sitting, not the whole box set', () {
      // 45 minutes of Mr. Robot is a weeknight; 45 x 45 is not, and
      // banding by the latter would answer a question nobody asked.
      expect(
        series('Mr. Robot', runtime: 45, episodes: 45).lengthBand,
        'UNDER 90 MINUTES',
      );
    });

    test('cost only the episodes actually watched', () {
      final e = series('Mr. Robot', runtime: 45, episodes: 45, watched: 12);
      expect(e.minutesSpent, 540);
      expect(e.minutesRemaining, 45 * 33);
      expect(e.episodesLeft, 33);
    });

    test('a series still running owes an unknown amount, not zero', () {
      final e = series('Severance', runtime: 50, watched: 9);
      expect(e.episodesLeft, isNull);
      expect(e.minutesRemaining, 0);
      expect(e.minutesSpent, 450);
    });

    test('advancing counts an episode and leaves it queued', () async {
      final state = await stateWith([
        series('Mr. Robot', runtime: 45, episodes: 45),
      ]);
      final e = state.entries.single;
      await state.advanceEpisode(e, 1);
      expect(e.watched, 1);
      expect(e.status, 'watchlist');
      expect(state.minutesWatched, 45);
      expect(state.episodesWatched, 1);
    });

    test('the last episode finishes the series outright', () async {
      final state = await stateWith([
        series('Mr. Robot', runtime: 45, episodes: 45, watched: 44),
      ]);
      final e = state.entries.single;
      await state.advanceEpisode(e, 1);
      expect(e.watched, 45);
      expect(e.status, 'seen');
      expect(e.plays, 1);
      expect(e.watchedAt, isNotNull);
      expect(state.minutesQueued, 0);
    });

    test('stepping back stops at zero and never overshoots the run', () async {
      final state = await stateWith([
        series('Mr. Robot', runtime: 45, episodes: 45, watched: 1),
      ]);
      final e = state.entries.single;
      await state.advanceEpisode(e, -1);
      expect(e.watched, 0);
      await state.advanceEpisode(e, -1);
      expect(e.watched, 0);
    });

    test('filing one straight under seen squares the episode tally', () async {
      final state = await stateWith([
        series('Mr. Robot', runtime: 45, episodes: 45),
      ]);
      await state.markSeen(state.entries.single);
      expect(state.entries.single.watched, 45);
      expect(state.minutesWatched, 45 * 45);
    });

    test('a rewatch costs the whole run again', () async {
      final state = await stateWith([
        series(
          'Mr. Robot',
          runtime: 45,
          episodes: 45,
          watched: 45,
          status: 'seen',
          plays: 1,
        ),
      ]);
      await state.watchAgain(state.entries.single);
      expect(state.minutesWatched, 45 * 45 * 2);
      expect(state.rewatchMinutes, 45 * 45);
    });

    test('a still-running series is counted as unmeasured queue', () async {
      final state = await stateWith([series('Severance', runtime: 50)]);
      expect(state.unmeasuredQueued, 1);
      expect(state.minutesQueued, 0);
    });

    test('kinds are counted separately', () async {
      final state = await stateWith([
        film('Heat', runtime: 170),
        series('Mr. Robot', runtime: 45, episodes: 45),
        series('Severance', runtime: 50),
      ]);
      expect(state.countOfKind('film'), 1);
      expect(state.countOfKind('series'), 2);
    });
  });

  group('how well you remember', () {
    int ms(int y, [int m = 1, int d = 1]) =>
        DateTime(y, m, d).millisecondsSinceEpoch;

    test('a stamp never claims more than the date knows', () {
      expect(watchedStamp(ms(2019, 3, 6), 'day'), 'Mar 2019');
      expect(watchedStamp(ms(2019, 3, 6), 'month'), 'Mar 2019');
      expect(watchedStamp(ms(2019, 3, 6), 'year'), '2019');
      expect(watchedStamp(ms(2019, 3, 6), 'unknown'), '');
      expect(watchedStamp(null, 'day'), '');
    });

    test('a recent exact date stays relative, an old one becomes a date', () {
      final threeDaysAgo = DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch;
      expect(watchedStamp(threeDaysAgo, 'day'), '3d');
      final longAgo = DateTime.now()
          .subtract(const Duration(days: 900))
          .millisecondsSinceEpoch;
      // "30mo" is not a fact anyone can use.
      expect(watchedStamp(longAgo, 'day'), monthYear(longAgo));
    });

    test('the written-out label spells out only what is known', () {
      expect(watchedLabel(ms(2019, 3, 6), 'day'), '6 Mar 2019');
      expect(watchedLabel(ms(2019, 3, 1), 'month'), 'Mar 2019');
      expect(watchedLabel(ms(2019), 'year'), '2019');
      expect(watchedLabel(ms(2019), 'unknown'), 'Not sure');
      expect(watchedLabel(null, 'day'), 'Not sure');
    });

    test('a date you cannot give sinks to the bottom of the log', () async {
      final dated = film('Dated', status: 'seen')
        ..viewings = [Viewing(at: ms(2019, 3, 6), precision: 'day')];
      final vague = film('Vague', status: 'seen')
        ..viewings = [Viewing.undated()];
      final recent = film('Recent', status: 'seen')..viewings = [Viewing.now()];
      final state = await stateWith([vague, dated, recent]);
      expect(state.visible('seen', '').map((e) => e.title).toList(), [
        'Recent',
        'Dated',
        'Vague',
      ]);
    });

    test('a viewing with no precision is not a date', () {
      final v = Viewing(at: ms(2019), precision: 'unknown');
      // Constructing one with no precision drops the stamp outright.
      expect(v.at, isNull);
      expect(v.isDated, isFalse);
      v.setDate(DateTime(2019), 'year');
      expect(v.isDated, isTrue);
      expect(v.at, ms(2019));
    });

    test('a viewing logged now reads as now, not as hours old', () {
      final v = Viewing.now();
      // Snapping "day" to midnight would make something logged this
      // afternoon claim to be several hours old on the shelf.
      expect(watchedStamp(v.at, v.precision), 'just now');
    });

    test('a coarse claim over a fine stamp is normalised on import', () {
      final v = Viewing.fromJson({'at': ms(2019, 7, 14), 'precision': 'year'});
      expect(v.at, ms(2019), reason: 'the month and day were never claimed');
    });

    test('a date is stored only as precisely as it is claimed', () {
      final v = Viewing()..setDate(DateTime(2019, 3, 6), 'day');
      expect(v.at, ms(2019, 3, 6));
      v.setPrecision('month');
      expect(v.at, ms(2019, 3), reason: 'the day is dropped, not kept');
      v.setPrecision('year');
      expect(v.at, ms(2019));
      v.setPrecision('unknown');
      expect(v.at, isNull);
    });

    test('logging from the shelf records an exact date', () async {
      final state = await stateWith([film('Heat', runtime: 170)]);
      final e = state.entries.single;
      await state.markSeen(e);
      expect(e.watchedPrecision, 'day');
      expect(e.viewings, hasLength(1));
      await state.watchAgain(e);
      expect(e.watchedPrecision, 'day');
      expect(e.plays, 2);
      expect(e.viewings.every((v) => v.isDated), isTrue);
    });
  });

  group('the viewing log', () {
    int ms(int y, [int m = 1, int d = 1]) =>
        DateTime(y, m, d).millisecondsSinceEpoch;

    test('the shelf stamps the most recent viewing, not the last added', () {
      final e = film('Heat', status: 'seen')
        ..viewings = [
          Viewing(at: ms(2011), precision: 'year'),
          Viewing(at: ms(2019, 3, 6), precision: 'day'),
          Viewing(at: ms(2016, 5), precision: 'month'),
        ];
      expect(e.plays, 3);
      expect(e.watchedAt, ms(2019, 3, 6));
      expect(e.watchedPrecision, 'day');
    });

    test('an undated viewing never becomes the stamp', () {
      final e = film('Heat', status: 'seen')
        ..viewings = [
          Viewing.undated(),
          Viewing(at: ms(2011), precision: 'year'),
        ];
      expect(e.watchedAt, ms(2011));
      expect(e.plays, 2);
    });

    test('a log of nothing but shrugs has no date at all', () {
      final e = film('Heat', status: 'seen')
        ..viewings = [Viewing.undated(), Viewing.undated()];
      expect(e.plays, 2);
      expect(e.hasWatchedDate, isFalse);
      expect(e.watchedAt, isNull);
    });

    test('the log reads newest first, shrugs last', () {
      final e = film('Heat', status: 'seen')
        ..viewings = [
          Viewing.undated(),
          Viewing(at: ms(2011), precision: 'year'),
          Viewing(at: ms(2019, 3, 6), precision: 'day'),
        ];
      expect(e.viewingsNewestFirst.map((v) => v.at).toList(), [
        ms(2019, 3, 6),
        ms(2011),
        null,
      ]);
    });

    test('every viewing costs the runtime again', () async {
      final state = await stateWith([
        film('Heat', runtime: 170, status: 'seen')
          ..viewings = [
            Viewing(at: ms(2011), precision: 'year'),
            Viewing(at: ms(2019, 3, 6), precision: 'day'),
            Viewing.undated(),
          ],
      ]);
      expect(state.minutesWatched, 510);
      expect(state.rewatches, 2);
      expect(state.rewatchMinutes, 340);
      expect(state.viewingsLogged, 3);
    });

    test('undoing takes the newest viewing, keeping the history', () async {
      final state = await stateWith([
        film('Heat', runtime: 170, status: 'seen')
          ..viewings = [
            Viewing(at: ms(2011), precision: 'year'),
            Viewing(at: ms(2019, 3, 6), precision: 'day'),
          ],
      ]);
      final e = state.entries.single;
      await state.undoPlay(e);
      expect(e.plays, 1);
      expect(
        e.viewings.single.at,
        ms(2011),
        reason: 'the older viewing is the one that survives',
      );
    });

    test('logging one more leaves the earlier dates alone', () async {
      final state = await stateWith([
        film('Heat', runtime: 170, status: 'seen')
          ..viewings = [Viewing(at: ms(2011), precision: 'year')],
      ]);
      final e = state.entries.single;
      await state.watchAgain(e);
      expect(e.plays, 2);
      expect(e.viewingsNewestFirst.last.at, ms(2011));
      expect(e.viewingsNewestFirst.first.precision, 'day');
    });
  });

  group('merging a backup', () {
    test(
      'matches on title and year, so a reissue is not a duplicate',
      () async {
        // Merge accepts only strictly newer incoming versions. Wall-clock
        // timestamps can be equal when these fixtures share a millisecond.
        final original = film('Solaris', year: 1972)..lastUpdated = 1;
        final state = await stateWith([original]);
        final added = await state.importEntries([
          film('Solaris', year: 1972, runtime: 167)..lastUpdated = 2,
          film('Solaris', year: 2002),
        ], replace: false);
        expect(added, 1);
        expect(state.entries.length, 2);
        final merged = state.entries.singleWhere((e) => e.year == 1972);
        expect(merged.id, original.id);
        expect(merged.runtime, 167);
        expect(
          state.entries.singleWhere((e) => e.year == 2002).title,
          'Solaris',
        );
      },
    );
  });

  group('formatting', () {
    test('runtime reads the way a programme prints it', () {
      expect(runtimeLong(null), '—');
      expect(runtimeLong(48), '48 min');
      expect(runtimeLong(120), '2 h');
      expect(runtimeLong(170), '2 h 50');
      expect(runtimeLong(125), '2 h 05');
    });

    test('a viewing tally grows into the unit it deserves', () {
      expect(spanOfTime(0), 'nothing yet');
      expect(spanOfTime(45), '45 min');
      expect(spanOfTime(120), '2 h');
      expect(spanOfTime(185), '3 h 05');
      expect(spanOfTime(2880), '2 days');
      expect(spanOfTime(2940), '2 days 01 h');
    });

    test('credits skip whichever half is missing', () {
      expect(
        provenance(year: 1995, director: 'Michael Mann'),
        '1995 · Michael Mann',
      );
      expect(provenance(year: 1995), '1995');
      expect(provenance(director: 'Michael Mann'), 'Michael Mann');
      expect(provenance(), '');
    });

    test('the shelf counts titles, since it holds both kinds', () {
      expect(titleCount(1), '1 title');
      expect(titleCount(1200), '1,200 titles');
    });

    test('the unit says what one sitting is', () {
      expect(runtimeUnit(series: false), 'min');
      expect(runtimeUnit(series: true), 'min/ep');
    });

    test('the episode line reads differently before, during and after', () {
      expect(episodeLine(watched: 0, episodes: 45), '45 EP');
      expect(episodeLine(watched: 12, episodes: 45), '12/45 EP');
      expect(episodeLine(watched: 12, episodes: null), '12/— EP');
      expect(episodeLine(watched: 0, episodes: null), '');
    });
  });
}
