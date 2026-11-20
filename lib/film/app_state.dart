import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_services.dart';
import 'diagnostics.dart';
import 'import_plan.dart';
import 'models/shelf_entry.dart';
import 'models/viewing.dart';
import 'shelf_filter.dart';
import 'storage.dart';

/// How the shelf is ordered. [shelf] is not one order but the right order
/// for whichever shelf you are on — shortest sitting first on the
/// watchlist, most recently watched under seen, most recently added under
/// bailed.
enum SortMode { shelf, title, runtime, rating, year }

class AppState extends ChangeNotifier {
  final ShelfStore _store;
  List<ShelfEntry> entries;
  SortMode sortMode = SortMode.shelf;
  String? saveError;
  late final bool _recoveredOnLoad;

  AppState(this._store) : entries = _store.load() {
    _recoveredOnLoad = _store.recovered;
  }
  Future<void> settle() => _store.settle();

  Map<String, dynamic> companionState() => {
    'entries': entries.map((e) => e.toJson()).toList(),
    'trash': _store.trash.map((e) => e.toJson()).toList(),
    'snapshot': _store.snapshot?.map((e) => e.toJson()).toList(),
    'snapshotAt': _store.snapshotAt,
  };

  static void validateCompanionState(Map<String, dynamic> state) {
    void validateRows(List rows) {
      final ids = <String>{};
      for (final row in rows) {
        if (row is! Map ||
            row['id'] is! String ||
            (row['id'] as String).trim().isEmpty ||
            !ids.add(row['id'] as String) ||
            row['title'] is! String ||
            (row['title'] as String).trim().isEmpty) {
          throw const FormatException('Invalid or duplicate film entry.');
        }
        ShelfEntry.fromJson(Map<String, dynamic>.from(row));
      }
    }

    validateRows(state['entries'] as List);
    for (final row in state['trash'] as List) {
      ShelfEntry.fromJson(Map<String, dynamic>.from(row['entry'] as Map));
      if (row['deletedAt'] is! int) {
        throw const FormatException('Invalid trash date.');
      }
    }
    validateRows(state['snapshot'] as List? ?? []);
    if (state['snapshotAt'] != null && state['snapshotAt'] is! int) {
      throw const FormatException('Invalid snapshot date.');
    }
  }

  Future<void> restoreCompanion(Map<String, dynamic> state) async {
    validateCompanionState(state);
    if (loadFailed && _store.directory != null) {
      final damaged = File('${_store.directory!.path}/shelf-v2.json');
      if (await damaged.exists()) {
        await damaged.copy(
          '${damaged.path}.damaged-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    }
    entries = (state['entries'] as List)
        .map((e) => ShelfEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _store.trash = (state['trash'] as List)
        .map(
          (e) => TrashEntry(
            ShelfEntry.fromJson(Map<String, dynamic>.from(e['entry'])),
            e['deletedAt'] as int,
          ),
        )
        .toList();
    _store.snapshot = (state['snapshot'] as List?)
        ?.map((e) => ShelfEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _store.snapshotAt = state['snapshotAt'] as int?;
    await _persist(recovery: true);
    _store.loadFailed = false;
  }

  bool get recovered => _recoveredOnLoad;
  List<TrashEntry> get trash =>
      _store.trash.where((t) => t.daysLeft > 0).toList();
  bool get hasSnapshot => _store.snapshot != null;
  int? get snapshotAt => _store.snapshotAt;
  List<String> get tags =>
      entries.expand((e) => e.tags).toSet().toList()..sort();
  ShelfEntry? duplicateOf(ShelfEntry entry) {
    for (final e in entries) {
      if (e.id != entry.id &&
          ImportPlan.identity(e) == ImportPlan.identity(entry)) {
        return e;
      }
    }
    return null;
  }

  /// The saved shelf was there but unreadable. Drives the recovery state.
  bool get loadFailed => _store.loadFailed;

  int countFor(String status) =>
      entries.where((e) => e.status == status).length;

  int countOfKind(String kind) => entries.where((e) => e.kind == kind).length;

  /// Runtime totalled across a slice of the shelf. Under seen that is time
  /// already spent; anywhere else it is what the slice still owes you.
  int minutesIn(List<ShelfEntry> list) => list.fold(
    0,
    (sum, e) => sum + (e.isSeen ? e.minutesSpent : e.minutesRemaining),
  );

  /// Unknown runtimes sort last rather than as zero, so a blank field never
  /// jumps to the top of "shortest first".
  static int _runtimeKey(ShelfEntry e) => e.hasRuntime ? e.runtime! : 1 << 20;

  /// A title you cannot date sinks to the bottom of the log rather than
  /// claiming a place in it.
  static int _watchedKey(ShelfEntry e) => e.hasWatchedDate ? e.watchedAt! : -1;

  List<ShelfEntry> visible(
    String status,
    String search, {
    ShelfFilter? filter,
  }) {
    final q = search.trim().toLowerCase();
    final list = entries
        .where(
          (e) =>
              e.status == status &&
              (filter == null || filter.matches(e)) &&
              (q.isEmpty ||
                  e.title.toLowerCase().contains(q) ||
                  e.director.toLowerCase().contains(q) ||
                  e.tags.any((t) => t.toLowerCase().contains(q))),
        )
        .toList();
    switch (sortMode) {
      case SortMode.shelf:
        switch (status) {
          case 'watchlist':
            // The watchlist exists to answer "what fits tonight", so it
            // opens shortest-first rather than newest-first.
            list.sort((a, b) => _runtimeKey(a).compareTo(_runtimeKey(b)));
          case 'seen':
            list.sort((a, b) => _watchedKey(b).compareTo(_watchedKey(a)));
          default:
            list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        }
      case SortMode.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case SortMode.runtime:
        list.sort((a, b) => _runtimeKey(a).compareTo(_runtimeKey(b)));
      case SortMode.rating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case SortMode.year:
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    }
    return list;
  }

  void setSort(SortMode mode) {
    sortMode = mode;
    notifyListeners();
  }

  Future<void> _persist({bool recovery = false}) async {
    try {
      if (loadFailed && !recovery) {
        throw StateError('Import a backup before making changes.');
      }
      await _store.save(entries);
      saveError = null;
      notifyListeners();
      await AndroidServices.refreshWidget();
    } catch (error, stack) {
      entries = _store.load();
      saveError =
          'Your change could not be saved. Free some space and try again.';
      Diagnostics.record(error, stack, source: 'shelf commit');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> add(ShelfEntry entry) async {
    entries.insert(0, entry);
    await _persist();
  }

  Future<void> update(ShelfEntry entry) async {
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) entries[i] = entry;
    await _persist();
  }

  Future<void> remove(String id) async {
    final removed = entries.where((e) => e.id == id).toList();
    _store.trash.addAll(
      removed.map(
        (e) => TrashEntry(e.copy(), DateTime.now().millisecondsSinceEpoch),
      ),
    );
    entries.removeWhere((e) => e.id == id);
    await _persist();
  }

  /// You watched it. Moving into seen is the one action that stamps a date,
  /// because the seen shelf is a viewing log and an undated entry would
  /// have nowhere to sit in it.
  Future<void> markSeen(ShelfEntry entry) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    entry.status = 'seen';
    if (entry.viewings.isEmpty) entry.addViewing(Viewing.now());
    // A series filed as seen has been sat through, so the episode tally has
    // to agree with that or the hours would be wrong.
    if (entry.isSeries && entry.episodes != null) {
      entry.watched = entry.episodes!;
    }
    entry.lastUpdated = now;
    await _persist();
  }

  /// One more episode down. Reaching the last one finishes the series
  /// outright — there is nothing left to advance to, and leaving it on the
  /// watchlist would be a lie.
  Future<void> advanceEpisode(ShelfEntry entry, int dir) async {
    if (!entry.isSeries) return;
    if (dir < 0 && entry.watched <= 0) return;
    final total = entry.episodes;
    if (dir > 0 && total != null && entry.watched >= total) return;

    entry.episodeHistory.add({
      'at': DateTime.now().millisecondsSinceEpoch,
      'from': entry.watched,
      'to': entry.watched + dir,
    });
    entry.watched += dir;
    HapticFeedback.selectionClick();
    entry.lastUpdated = DateTime.now().millisecondsSinceEpoch;
    if (entry.isFinished) {
      await markSeen(entry);
      return;
    }
    await _persist();
  }

  /// A rewatch is the only counter a finished title has, and it only goes
  /// up by sitting through the thing again — so it restamps the log too.
  Future<void> watchAgain(ShelfEntry entry) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Logging it from the shelf means it happened just now, exactly.
    entry.addViewing(Viewing.now());
    entry.lastUpdated = now;
    await _persist();
  }

  /// Takes back the most recent viewing. Stops at one: a seen title has
  /// been seen, and un-seeing it is a change of shelf, not of tally.
  Future<void> undoPlay(ShelfEntry entry) async {
    if (entry.plays <= 1) return;
    entry.removeNewestViewing();
    entry.lastUpdated = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  Future<void> setStatus(ShelfEntry entry, String status) async {
    if (status == 'seen') return markSeen(entry);
    entry.status = status;
    entry.lastUpdated = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  Future<void> setRating(ShelfEntry entry, int rating) async {
    entry.rating = rating;
    entry.lastUpdated = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  /// Replace wipes the list first; merge updates entries with a matching id
  /// (or the same title and year, so two copies of one export do not
  /// duplicate) and appends the rest.
  Future<int> importEntries(
    List<ShelfEntry> imported, {
    required bool replace,
  }) async {
    final plan = ImportPlan(entries, imported);
    await applyImport(plan, replace: replace);
    return replace ? imported.length : plan.count(ImportChange.added);
  }

  Future<void> applyImport(ImportPlan plan, {required bool replace}) async {
    // Commit the snapshot BEFORE changing the shelf, including merge imports.
    _store.snapshot = entries.map((e) => e.copy()).toList();
    _store.snapshotAt = DateTime.now().millisecondsSinceEpoch;
    await _store.save(entries);
    if (replace) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _store.trash.addAll(entries.map((e) => TrashEntry(e.copy(), now)));
      entries = plan.rows.map((r) => r.incoming.copy()).toList();
    } else {
      final byId = {for (final e in entries) e.id: e};
      for (final row in plan.rows.where((r) => r.useIncoming)) {
        final next = row.incoming.copy();
        if (row.local != null) next.id = row.local!.id;
        byId[next.id] = next;
      }
      entries = byId.values.toList();
    }
    await _persist(recovery: true);
  }

  Future<void> restoreSnapshot() async {
    final snapshot = _store.snapshot;
    if (snapshot == null) return;
    final current = entries.map((e) => e.copy()).toList();
    entries = snapshot.map((e) => e.copy()).toList();
    _store.snapshot = current;
    _store.snapshotAt = DateTime.now().millisecondsSinceEpoch;
    await _persist(recovery: true);
  }

  Future<void> restoreTrash(TrashEntry item) => restoreTrashBatch([item]);

  Future<void> restoreTrashBatch(Iterable<TrashEntry> items) async {
    final live = items
        .where((t) => t.daysLeft > 0 && _store.trash.contains(t))
        .toList();
    final ids = entries.map((e) => e.id).toSet();
    for (final t in live) {
      if (!ids.add(t.entry.id)) {
        throw StateError('This title is already on your shelf.');
      }
    }
    entries.addAll(live.map((t) => t.entry.copy()));
    final restored = live.toSet();
    _store.trash.removeWhere(restored.contains);
    await _persist();
  }

  Future<void> bulk(
    Set<String> ids, {
    String? status,
    List<String>? tags,
    bool delete = false,
  }) async {
    final targets = entries.where((e) => ids.contains(e.id)).toList();
    if (tags != null && targets.any((e) => {...e.tags, ...tags}.length > 100)) {
      throw StateError('Use at most 100 tags per title.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (delete) {
      _store.trash.addAll(targets.map((e) => TrashEntry(e.copy(), now)));
      entries.removeWhere((e) => ids.contains(e.id));
    } else {
      for (final e in targets) {
        if (status != null) {
          e.status = status;
          if (status == 'seen') {
            if (e.viewings.isEmpty) e.addViewing(Viewing.now());
            if (e.isSeries && e.episodes != null) e.watched = e.episodes!;
          }
        }
        if (tags != null) e.tags = {...e.tags, ...tags}.toList();
        e.lastUpdated = now;
      }
    }
    await _persist();
  }

  YearReview review(int year) => YearReview(year, entries);

  String exportJson() => ShelfStore.toExportJson(entries);

  // ------------------------------------------------------------------ tally

  /// Every minute you have actually sat through, episodes and rewatches
  /// included.
  int get minutesWatched => entries.fold(0, (sum, e) => sum + e.minutesSpent);

  /// What the watchlist would cost you to clear.
  int get minutesQueued => entries
      .where((e) => e.status == 'watchlist')
      .fold(0, (sum, e) => sum + e.minutesRemaining);

  /// Watchlist titles the queue figure cannot account for: no runtime yet,
  /// or a series still running with no episode count. The stats sheet says
  /// so rather than quietly under-reporting.
  int get unmeasuredQueued => entries
      .where(
        (e) =>
            e.status == 'watchlist' &&
            (!e.hasRuntime || (e.isSeries && e.episodes == null)),
      )
      .length;

  /// Every dated or undated time through, across the whole shelf.
  int get viewingsLogged => entries.fold(0, (sum, e) => sum + e.plays);

  /// Episodes watched across every series, this run only.
  int get episodesWatched =>
      entries.where((e) => e.isSeries).fold(0, (sum, e) => sum + e.watched);

  int get rewatches =>
      entries.fold(0, (sum, e) => sum + (e.plays > 1 ? e.plays - 1 : 0));

  /// Time spent on second and later times through — the part of the tally
  /// you chose to spend again.
  int get rewatchMinutes => entries.fold(0, (sum, e) {
    if (e.plays <= 1 || !e.hasRuntime) return sum;
    final runLength = e.isSeries ? (e.episodes ?? e.watched) : 1;
    return sum + e.runtime! * runLength * (e.plays - 1);
  });

  double get averageRating {
    final rated = entries.where((e) => e.status == 'seen' && e.rating > 0);
    if (rated.isEmpty) return 0;
    return rated.fold<int>(0, (s, e) => s + e.rating) / rated.length;
  }

  /// The oldest thing on the seen shelf. A quiet way of showing how far
  /// back someone actually watches.
  int? get earliestYearSeen {
    final years = entries
        .where((e) => e.status == 'seen' && (e.year ?? 0) > 0)
        .map((e) => e.year!);
    return years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b);
  }
}

class YearReview {
  final int year;
  final List<(ShelfEntry, Viewing)> viewings;
  YearReview(this.year, List<ShelfEntry> entries)
    : viewings = [
        for (final e in entries)
          for (final v in e.viewings)
            if (v.isDated &&
                DateTime.fromMillisecondsSinceEpoch(v.at!).year == year)
              (e, v),
      ];
  int get films => viewings.where((v) => !v.$1.isSeries).length;
  int get series => viewings.where((v) => v.$1.isSeries).length;
  int get minutes => viewings.fold(
    0,
    (sum, v) =>
        sum +
        (v.$1.hasRuntime
            ? v.$1.runtime! * (v.$1.isSeries ? (v.$1.episodes ?? 0) : 1)
            : 0),
  );
  int get unmeasured => viewings
      .where(
        (v) => !v.$1.hasRuntime || (v.$1.isSeries && v.$1.episodes == null),
      )
      .length;
}
