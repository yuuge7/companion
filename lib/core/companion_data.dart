import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../books/models/reading_session.dart';
import '../books/models/book.dart';
import '../books/services/library_model.dart';
import '../books/services/theme_notifier.dart';
import '../manga/app_state.dart' as manga;
import '../manga/models/manga_entry.dart';
import '../film/app_state.dart' as film;
import '../anime/anime_library.dart';
import '../anime/anime_entry.dart';
import 'backup_type.dart';
import 'physical_collection.dart';

DateTime calendarDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

class DiaryEvent {
  const DiaryEvent({
    required this.mode,
    required this.entryId,
    required this.title,
    required this.detail,
    required this.date,
    this.precision = 'day',
    this.amount = 0,
    this.unit = '',
    this.completed = false,
  });
  final CompanionMode mode;
  final String entryId, title, detail, precision, unit;
  final DateTime? date;
  final int amount;
  final bool completed;
  bool get hasDay => date != null && precision == 'day';
  int? get year => date == null
      ? null
      : hasDay
      ? date!.toLocal().year
      : date!.year;
  bool get isActivity => completed || amount > 0 || detail == 'Started reading';
}

class Rediscovery {
  const Rediscovery(
    this.mode,
    this.id,
    this.title,
    this.reasons,
    this.priority,
    this.lastActive,
  );
  final CompanionMode mode;
  final String id, title;
  final List<String> reasons;
  final int priority, lastActive;
}

class CollectionItem {
  const CollectionItem(this.mode, this.id, this.title, this.collection);
  final CompanionMode mode;
  final String id, title;
  final PhysicalCollection collection;
}

/// Shared projections only; the four libraries keep their own persisted schemas.
class CompanionData extends ChangeNotifier {
  CompanionData({
    required this.books,
    required this.settings,
    required this.mangaLibrary,
    required this.filmLibrary,
    required this.anime,
    required this.preferences,
  }) {
    for (final model in _models) {
      model.addListener(notifyListeners);
    }
  }
  final LibraryModel books;
  final ThemeNotifier settings;
  final manga.AppState mangaLibrary;
  final film.AppState filmLibrary;
  final AnimeLibrary anime;
  final SharedPreferences preferences;
  List<ChangeNotifier> get _models => [
    books,
    settings,
    mangaLibrary,
    filmLibrary,
    anime,
  ];
  bool get hasLoadFailure =>
      books.loadFailed ||
      mangaLibrary.loadFailed ||
      filmLibrary.loadFailed ||
      anime.loadFailed;
  @override
  void dispose() {
    for (final model in _models) {
      model.removeListener(notifyListeners);
    }
    super.dispose();
  }

  List<DiaryEvent> diary() {
    final events = <DiaryEvent>[];
    void add(
      CompanionMode mode,
      String id,
      String title,
      DateTime? date,
      String detail, {
      String precision = 'day',
      int amount = 0,
      String unit = '',
      bool completed = false,
    }) => events.add(
      DiaryEvent(
        mode: mode,
        entryId: id,
        title: title,
        date: date,
        detail: detail,
        precision: precision,
        amount: amount,
        unit: unit,
        completed: completed,
      ),
    );
    DateTime stamp(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
    for (final b in books.books) {
      for (final s in b.sessions) {
        final precision = switch (s.precision) {
          DatePrecision.exact => 'day',
          DatePrecision.approximate => 'month',
          DatePrecision.unknown => 'unknown',
        };
        if (s.precision != DatePrecision.unknown) {
          add(
            CompanionMode.books,
            b.id,
            b.title,
            s.startDate,
            'Started reading',
            precision: precision,
          );
          if (s.endDate != null) {
            add(
              CompanionMode.books,
              b.id,
              b.title,
              s.endDate,
              'Finished reading',
              precision: precision,
              completed: true,
            );
          }
        }
        var previous = 0;
        for (final p in s.progress) {
          final delta = p.page - (p.fromPage ?? previous);
          previous = p.page;
          if (delta == 0) continue;
          final unit = s.isAudio ? 'listening minutes' : 'pages';
          add(
            CompanionMode.books,
            b.id,
            b.title,
            p.date,
            '${delta > 0 ? '+' : ''}$delta $unit · at ${p.page}',
            amount: delta,
            unit: unit,
          );
        }
      }
    }
    for (final m in mangaLibrary.entries) {
      for (final h in m.history) {
        if (h.delta == 0) continue;
        add(
          CompanionMode.manga,
          m.id,
          m.title,
          stamp(h.at),
          '${h.delta > 0 ? '+' : ''}${h.delta} chapters · chapter ${h.to}',
          amount: h.delta,
          unit: 'chapters',
        );
      }
      if (m.finishedAt != null) {
        add(
          CompanionMode.manga,
          m.id,
          m.title,
          stamp(m.finishedAt!),
          'Finished reading',
          completed: true,
        );
      }
    }
    for (final f in filmLibrary.entries) {
      for (final v in f.viewings) {
        add(
          CompanionMode.film,
          f.id,
          f.title,
          v.at == null ? null : stamp(v.at!),
          f.isSeries ? 'Finished series' : 'Watched film',
          precision: v.precision,
          completed: true,
          amount: !f.isSeries ? f.runtime ?? 0 : 0,
          unit: !f.isSeries ? 'watching minutes' : '',
        );
      }
      for (final h in f.episodeHistory) {
        final delta = (h['to'] as int) - (h['from'] as int);
        if (delta == 0) continue;
        add(
          CompanionMode.film,
          f.id,
          f.title,
          stamp(h['at'] as int),
          '${delta > 0 ? '+' : ''}$delta episodes · episode ${h['to']}',
          amount: delta,
          unit: 'episodes',
        );
      }
    }
    for (final a in anime.entries) {
      for (final h in a.history) {
        final delta = (h['to'] as int) - (h['from'] as int);
        if (delta == 0) continue;
        final finished = a.total != null && h['to'] == a.total && delta > 0;
        add(
          CompanionMode.anime,
          a.id,
          a.title,
          stamp(h['at'] as int),
          '${delta > 0 ? '+' : ''}$delta ${h['unit']}${finished ? ' · finished' : ''}',
          amount: delta,
          unit: a.isMovie ? 'watching minutes' : 'episodes',
          completed: finished,
        );
      }
      final parts = a.finishedDate.split('-');
      final finishedDate = a.finishedDate.isEmpty
          ? null
          : DateTime.tryParse(
              parts.length == 1
                  ? '${a.finishedDate}-01-01'
                  : parts.length == 2
                  ? '${a.finishedDate}-01'
                  : a.finishedDate,
            );
      final datePrecision = parts.length == 1
          ? 'year'
          : parts.length == 2
          ? 'month'
          : 'day';
      if (finishedDate != null &&
          !a.history.any(
            (h) =>
                a.total != null &&
                h['to'] == a.total &&
                calendarDay(stamp(h['at'] as int)) == calendarDay(finishedDate),
          )) {
        add(
          CompanionMode.anime,
          a.id,
          a.title,
          finishedDate,
          'Finished watching',
          precision: datePrecision,
          completed: true,
        );
      }
    }
    events.sort(
      (a, b) => (b.date?.millisecondsSinceEpoch ?? -1).compareTo(
        a.date?.millisecondsSinceEpoch ?? -1,
      ),
    );
    return events;
  }

  List<Rediscovery> rediscover({DateTime? now}) {
    final today = now ?? DateTime.now();
    final result = <Rediscovery>[];
    void consider(
      CompanionMode mode,
      String id,
      String title,
      int added,
      int active, {
      double progress = 0,
      bool paused = false,
      int? episodesLeft,
    }) {
      if (today
              .difference(
                DateTime.fromMillisecondsSinceEpoch(max(added, active)),
              )
              .inDays <
          14) {
        return;
      }
      final age = today
          .difference(DateTime.fromMillisecondsSinceEpoch(added))
          .inDays;
      final reasons = <String>[];
      var priority = 0;
      if (episodesLeft != null && episodesLeft > 0 && episodesLeft <= 2) {
        reasons.add(
          'Only $episodesLeft ${episodesLeft == 1 ? 'episode' : 'episodes'} left',
        );
        priority += 4;
      }
      if (paused && progress > 0) {
        reasons.add('You paused this at ${(progress * 100).round()}%');
        priority += 3;
      }
      final hasAddedDate = added >= DateTime(1971).millisecondsSinceEpoch;
      if (hasAddedDate && age >= 365) {
        reasons.add(
          age < 730 ? 'Added a year ago' : 'Added ${age ~/ 365} years ago',
        );
        priority += 2;
      } else if ((active >= DateTime(1971).millisecondsSinceEpoch ||
              hasAddedDate) &&
          today
                  .difference(
                    DateTime.fromMillisecondsSinceEpoch(
                      active > 0 ? active : added,
                    ),
                  )
                  .inDays >=
              90) {
        reasons.add('Waiting for you for 3+ months');
        priority++;
      }
      if (reasons.isNotEmpty) {
        result.add(Rediscovery(mode, id, title, reasons, priority, active));
      }
    }

    for (final b in books.books.where(
      (b) => b.status != BookStatus.read && b.status != BookStatus.dropped,
    )) {
      consider(
        CompanionMode.books,
        b.id,
        b.title,
        b.createdAt.millisecondsSinceEpoch,
        (b.lastRead ?? b.updatedAt).millisecondsSinceEpoch,
        progress: b.progress,
        paused: b.status == BookStatus.onHold,
      );
    }
    for (final m in mangaLibrary.entries.where(
      (m) => m.status != ShelfStatus.read && m.status != ShelfStatus.dropped,
    )) {
      consider(
        CompanionMode.manga,
        m.id,
        m.title,
        m.addedAt,
        m.lastUpdated,
        progress: m.progress,
        paused: m.status == ShelfStatus.onHold,
      );
    }
    for (final f in filmLibrary.entries.where((f) => f.status == 'watchlist')) {
      consider(
        CompanionMode.film,
        f.id,
        f.title,
        f.addedAt,
        f.lastUpdated,
        episodesLeft: f.episodesLeft,
      );
    }
    for (final a in anime.entries.where(
      (a) => [
        AnimeStatus.watching,
        AnimeStatus.planned,
        AnimeStatus.onHold,
      ].contains(a.status),
    )) {
      consider(
        CompanionMode.anime,
        a.id,
        a.title,
        a.addedAt,
        a.updatedAt,
        progress: a.progress ?? 0,
        paused: a.status == AnimeStatus.onHold,
        episodesLeft: !a.isMovie && a.total != null
            ? a.total! - a.position
            : null,
      );
    }
    result.sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      if (priority != 0) return priority;
      final active = a.lastActive.compareTo(b.lastActive);
      return active != 0 ? active : a.id.compareTo(b.id);
    });
    return result;
  }

  List<CollectionItem> collection() => [
    for (final b in books.books.where((b) => b.collection.isTracked))
      CollectionItem(CompanionMode.books, b.id, b.title, b.collection),
    for (final m in mangaLibrary.entries.where((m) => m.collection.isTracked))
      CollectionItem(CompanionMode.manga, m.id, m.title, m.collection),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}
