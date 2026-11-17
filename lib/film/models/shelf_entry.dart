import 'dart:math';

import 'viewing.dart';

/// One tracked title — a film, or a series.
///
/// The two are one type because they answer the same question in the same
/// units: what does sitting down with this cost me tonight? So [runtime] is
/// not "the length of the thing", it is **the length of one sitting** — the
/// whole film, or one episode. That keeps the app's one accent colour
/// meaning one thing on every row.
///
/// Where they differ is progress. A film is atomic: you saw it or you did
/// not. A series is serial: [watched] counts episodes, and only once it
/// reaches [episodes] has the thing been seen at all.
///
/// Either way, having seen it is not a number but a list. [viewings] holds
/// one dated event per time through, because "I saw it three times" and "I
/// saw it in 2011, 2016 and last Tuesday" are different facts, and the
/// second one is the one worth keeping.
class ShelfEntry {
  String id;
  String kind; // "film" | "series"
  String title;
  int? year;
  String director; // the creator, for a series
  int? runtime; // minutes per sitting: whole film, or one episode
  int? episodes; // series only; null while it is still running
  int watched; // series only: episodes watched in the current run
  String posterUrl;
  String watchUrl;
  String status; // "watchlist" | "seen" | "bailed"
  int rating; // 0..5
  String note; // one line of verdict, shown on seen rows
  List<String> tags;
  List<int> seasons;

  /// One entry per complete time through, newest dated first. Empty until
  /// the thing has been seen at all.
  List<Viewing> viewings;
  int addedAt; // epoch ms
  int lastUpdated; // epoch ms

  ShelfEntry({
    required this.id,
    required this.title,
    this.kind = 'film',
    this.year,
    this.director = '',
    this.runtime,
    this.episodes,
    this.watched = 0,
    this.posterUrl = '',
    this.watchUrl = '',
    this.status = 'watchlist',
    this.rating = 0,
    this.note = '',
    List<String>? tags,
    List<int>? seasons,
    List<Viewing>? viewings,
    required this.addedAt,
    required this.lastUpdated,
  }) : viewings = viewings ?? [],
       tags = tags ?? [],
       seasons = seasons ?? [];

  int episodesThatFit(int minutes) => !hasRuntime || minutes < runtime!
      ? 0
      : min(minutes ~/ runtime!, episodesLeft ?? (minutes ~/ runtime!));

  String get seasonProgress {
    if (!isSeries || seasons.isEmpty) return '';
    var left = watched;
    for (var i = 0; i < seasons.length; i++) {
      if (left < seasons[i]) return 'S${i + 1} E$left';
      left -= seasons[i];
    }
    return left > 0 ? '' : 'S${seasons.length} E${seasons.last}';
  }

  String get nextEpisode {
    if (!isSeries) return '';
    var left = watched;
    for (var i = 0; i < seasons.length; i++) {
      if (left < seasons[i]) return 'S${i + 1} E${left + 1}';
      left -= seasons[i];
    }
    return episodesLeft == 0 ? 'Complete' : 'Episode ${watched + 1}';
  }

  bool get isSeries => kind == 'series';

  bool get isSeen => status == 'seen';

  /// How many complete times through. The shelf shows this as "SEEN 3x".
  int get plays => viewings.length;

  /// The most recent viewing that can actually be placed on a timeline.
  /// A title watched three times but never dated has none, and sinks to the
  /// bottom of the log rather than claiming a place in it.
  Viewing? get lastViewing {
    Viewing? best;
    for (final v in viewings) {
      if (v.isDated && (best == null || v.at! > best.at!)) best = v;
    }
    return best;
  }

  int? get watchedAt => lastViewing?.at;
  String get watchedPrecision => lastViewing?.precision ?? 'unknown';

  /// True when a date is recorded at all, however roughly.
  bool get hasWatchedDate => lastViewing != null;

  /// Viewings in the order the log reads them: newest first, undated last.
  List<Viewing> get viewingsNewestFirst => [...viewings]..sort(Viewing.compare);

  /// Records another time through. Keeps the list in log order so the most
  /// recent viewing is always the one the shelf stamps.
  void addViewing(Viewing v) {
    viewings.add(v);
    viewings.sort(Viewing.compare);
  }

  /// Drops the most recent viewing. Stops at one, because a seen title has
  /// been seen — un-seeing it is a change of shelf, not of tally.
  void removeNewestViewing() {
    if (viewings.length <= 1) return;
    viewings.sort(Viewing.compare);
    viewings.removeAt(0);
  }

  bool get hasRuntime => runtime != null && runtime! > 0;

  /// True once every episode is accounted for. A series with no episode
  /// count is still running, so it can never be finished by counting.
  bool get isFinished =>
      isSeries && episodes != null && episodes! > 0 && watched >= episodes!;

  /// Episodes left to watch, or null when nobody knows yet.
  int? get episodesLeft {
    if (!isSeries || episodes == null) return null;
    return max(episodes! - watched, 0);
  }

  /// Minutes this title has actually cost you. For a series that is every
  /// episode watched; a full rewatch costs the whole run again.
  int get minutesSpent {
    if (!hasRuntime) return 0;
    if (!isSeries) return runtime! * plays;
    final rerunLength = episodes ?? watched;
    return runtime! * (max(watched, 0) + rerunLength * max(plays - 1, 0));
  }

  /// What is still owed. A film costs its runtime; a series costs whatever
  /// is left, and an unmeasured or still-running one costs an unknown
  /// amount that the stats sheet owns up to rather than guessing.
  int get minutesRemaining {
    if (!hasRuntime || isSeen) return 0;
    if (!isSeries) return runtime!;
    return runtime! * (episodesLeft ?? 0);
  }

  /// Runtime bracket, used to band the watchlist. The question the shelf
  /// answers is "what fits tonight", so this brackets a single sitting —
  /// one episode of a series, not the whole box set.
  String get lengthBand {
    if (!hasRuntime) return 'RUNTIME UNKNOWN';
    final m = runtime!;
    if (m < 90) return 'UNDER 90 MINUTES';
    if (m < 120) return '90 TO 120 MINUTES';
    if (m < 150) return '2 TO 2½ HOURS';
    return 'OVER 2½ HOURS';
  }

  /// Same scheme the manga shelf uses: base36 timestamp + random tail.
  static String newId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final rnd = Random();
    final tail = List.generate(
      10,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
    return '$ts$tail';
  }

  factory ShelfEntry.blank() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ShelfEntry(id: newId(), title: '', addedAt: now, lastUpdated: now);
  }

  static int _asInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is double && v.isFinite) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double && v.isFinite) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Tolerant parse: hand-edited backups carry years and runtimes as
  /// strings, and older exports predate [kind], [viewings] and [note].
  factory ShelfEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final status = json['status'] as String? ?? 'watchlist';
    final safeStatus = const {'watchlist', 'seen', 'bailed'}.contains(status)
        ? status
        : 'watchlist';
    final kind = json['kind'] as String? ?? 'film';
    final safeKind = kind == 'series' ? 'series' : 'film';
    final rawViewings = json['viewings'];
    final episodes = _asIntOrNull(json['episodes']);
    var watched = _asInt(json['watched']);
    // A backup written before series existed, or one hand-edited to add a
    // finished series, still knows a seen series was watched all the way.
    if (safeKind == 'series' && safeStatus == 'seen' && watched <= 0) {
      watched = episodes ?? 0;
    }
    return ShelfEntry(
      id: (json['id'] as String?)?.isNotEmpty == true
          ? json['id'] as String
          : newId(),
      kind: safeKind,
      title: json['title'] as String? ?? '',
      year: _asIntOrNull(json['year']),
      director: json['director'] as String? ?? '',
      runtime: _asIntOrNull(json['runtime']),
      episodes: safeKind == 'series' ? episodes : null,
      watched: safeKind == 'series' ? max(watched, 0) : 0,
      posterUrl: json['posterUrl'] as String? ?? '',
      watchUrl: json['watchUrl'] as String? ?? '',
      status: safeStatus,
      rating: _asInt(json['rating']).clamp(0, 5),
      note: json['note'] as String? ?? '',
      tags: (json['tags'] is List ? json['tags'] as List : const [])
          .whereType<String>()
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .take(100)
          .toList(),
      seasons: (json['seasons'] is List ? json['seasons'] as List : const [])
          .map(_asInt)
          .where((n) => n > 0 && n <= 10000)
          .take(1000)
          .toList(),
      viewings: rawViewings is List
          ? (rawViewings
                .whereType<Map<String, dynamic>>()
                .map(Viewing.fromJson)
                .toList()
              ..sort(Viewing.compare))
          : _viewingsFromLegacy(json, safeStatus),
      addedAt: _asInt(json['addedAt'], now),
      lastUpdated: _asInt(json['lastUpdated']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'year': year,
    'director': director,
    'runtime': runtime,
    'episodes': episodes,
    'watched': watched,
    'posterUrl': posterUrl,
    'watchUrl': watchUrl,
    'status': status,
    'rating': rating,
    'note': note,
    'tags': tags,
    'seasons': seasons,
    'viewings': viewings.map((v) => v.toJson()).toList(),
    'addedAt': addedAt,
    'lastUpdated': lastUpdated,
  };

  /// Rebuilds the log from a backup that only ever counted. Such a file
  /// knows how many times and when the *last* one was; the earlier ones
  /// genuinely have no date on record, and inventing one would be worse
  /// than admitting it.
  static List<Viewing> _viewingsFromLegacy(
    Map<String, dynamic> json,
    String status,
  ) {
    final watchedAt = _asIntOrNull(json['watchedAt']);
    final rawPrecision = json['watchedPrecision'] as String?;
    final precision = watchedAt == null
        ? 'unknown'
        : (Viewing.precisions.contains(rawPrecision) &&
                  rawPrecision != 'unknown'
              ? rawPrecision!
              // Backups written before precision existed recorded only exact
              // stamps.
              : 'day');
    var count = _asIntOrNull(json['plays']) ?? (status == 'seen' ? 1 : 0);
    if (status == 'seen' && count < 1) count = 1;
    count = count.clamp(0, 10000);
    return [
      if (watchedAt != null) Viewing(at: watchedAt, precision: precision),
      for (var i = watchedAt != null ? 1 : 0; i < count; i++) Viewing.undated(),
    ];
  }

  ShelfEntry copy() => ShelfEntry.fromJson(toJson());
}
