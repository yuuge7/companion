// Short, mono-friendly formatting. Everything here ends up set in DM Mono
// with tabular figures, so widths stay stable while numbers change.

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "just now", "14m", "6h", "3d", "2w", "5mo". Deliberately compact: on a
/// row this sits beside the runtime and must not compete with it. Past a
/// year, "18mo" stops meaning anything, so it hands over to a real date.
String timeAgo(int ts) {
  if (ts <= 0) return '';
  final d = DateTime.now().millisecondsSinceEpoch - ts;
  if (d < 0) return 'just now';
  final minutes = d ~/ 60000;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}m';
  final hours = d ~/ 3600000;
  if (hours < 24) return '${hours}h';
  final days = d ~/ 86400000;
  if (days < 14) return '${days}d';
  if (days < 60) return '${days ~/ 7}w';
  if (days < 365) return '${days ~/ 30}mo';
  return monthYear(ts);
}

/// "Mar 2019".
String monthYear(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${_months[d.month - 1]} ${d.year}';
}

/// A backup's update timestamp is exact metadata. UTC makes comparisons
/// unambiguous even when two files were written in different time zones.
String updatedLabel(int ts) {
  if (ts <= 0) return 'Update date not recorded';
  final d = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Updated ${d.day} ${_months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)} UTC';
}

/// The date written out as far as it is known: "6 Mar 2019", "Mar 2019",
/// "2019", or nothing at all. Used where there is room for the whole thing.
String watchedLabel(int? ts, String precision) {
  if (ts == null || precision == 'unknown') return 'Not sure';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return switch (precision) {
    'year' => '${d.year}',
    'month' => monthYear(ts),
    _ => '${d.day} ${_months[d.month - 1]} ${d.year}',
  };
}

/// The same date, compact, for the right margin of a row. An exact date
/// gets to be relative because that is the useful thing about knowing it;
/// a rough one is stated plainly, because "7mo ago" would be a claim the
/// date cannot back up.
String watchedStamp(int? ts, String precision) {
  if (ts == null || precision == 'unknown') return '';
  return switch (precision) {
    'year' => '${DateTime.fromMillisecondsSinceEpoch(ts).year}',
    'month' => monthYear(ts),
    _ => timeAgo(ts),
  };
}

/// 4182 -> "4,182". Used wherever a tally is shown as prose.
String groupDigits(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "1 title" / "12 titles" — the shelf holds films and series, and
/// "titles" is the one word that covers both without picking a side. Never
/// "entries" or "items".
String titleCount(int n) => '${groupDigits(n)} ${n == 1 ? 'title' : 'titles'}';

/// The unit a runtime is measured in. A film's runtime is the whole film;
/// a series' is one episode, and saying so is what stops the accent
/// numeral from meaning two different things on two rows.
String runtimeUnit({required bool series}) => series ? 'min/ep' : 'min';

/// "45 EP" is how long the run is; "12/45 EP" is how far into it you are.
/// A series still on air keeps the slash — "12/— EP" — because dropping it
/// would make the watched count look like a total.
String episodeLine({required int watched, int? episodes}) {
  if (watched <= 0) return episodes == null ? '' : '$episodes EP';
  return '$watched/${episodes ?? '—'} EP';
}

/// 112 -> "1 h 52". A runtime read the way a programme prints it: hours
/// first, because the hour is what you budget an evening in.
String runtimeLong(int? minutes) {
  if (minutes == null || minutes <= 0) return '—';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h ${m.toString().padLeft(2, '0')}';
}

/// Total viewing time, at the scale it deserves. Minutes for an afternoon,
/// hours for a habit, days once the tally stops being an afternoon at all.
String spanOfTime(int minutes) {
  if (minutes <= 0) return 'nothing yet';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  if (hours < 48) {
    final rest = minutes % 60;
    return rest == 0
        ? '$hours h'
        : '$hours h ${rest.toString().padLeft(2, '0')}';
  }
  final days = hours ~/ 24;
  final restHours = hours % 24;
  return restHours == 0
      ? '$days days'
      : '$days days ${restHours.toString().padLeft(2, '0')} h';
}

/// "1999 · David Fincher", skipping whichever half you never filled in.
String provenance({int? year, String director = ''}) {
  final parts = <String>[
    if (year != null && year > 0) '$year',
    if (director.trim().isNotEmpty) director.trim(),
  ];
  return parts.join(' · ');
}
