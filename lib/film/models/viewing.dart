/// One time you sat through something.
///
/// A viewing is an event, not a tally, so it carries its own date — and its
/// own [precision], because the third time you saw a film is exactly the
/// sort of thing you remember the year of and nothing more.
class Viewing {
  /// Epoch ms, already snapped to [precision]. Null when nothing is known.
  int? at;

  /// "day", "month", "year" or "unknown". Nothing in the UI may present
  /// [at] as more exact than this says.
  String precision;
  String location;
  String company;

  Viewing({
    this.at,
    this.precision = 'unknown',
    this.location = '',
    this.company = '',
  }) {
    if (!precisions.contains(precision)) precision = 'unknown';
    if (precision == 'unknown') at = null;
  }

  static const precisions = {'day', 'month', 'year', 'unknown'};

  /// True when this viewing can be placed on a timeline at all.
  bool get isDated => at != null && precision != 'unknown';

  /// Logged from the shelf: it happened just now, exactly.
  factory Viewing.now() =>
      Viewing(at: DateTime.now().millisecondsSinceEpoch, precision: 'day');

  /// It happened — that is the whole of what is known.
  factory Viewing.undated() => Viewing();

  /// Drops whatever the precision does not vouch for, so a bare year never
  /// carries a month and a day nobody claimed.
  ///
  /// "Day" keeps the time of day it came with. That is not a finer claim
  /// than the day — the UI never shows an hour — and throwing it away would
  /// make something you logged this afternoon read as hours old.
  static int? _snap(DateTime? d, String precision) {
    if (d == null || precision == 'unknown') return null;
    return switch (precision) {
      'year' => DateTime(d.year).millisecondsSinceEpoch,
      'month' => DateTime(d.year, d.month).millisecondsSinceEpoch,
      _ => d.millisecondsSinceEpoch,
    };
  }

  static int? _snapMs(int? ms, String precision) => ms == null
      ? null
      : _snap(DateTime.fromMillisecondsSinceEpoch(ms), precision);

  /// The date as you last left it, for re-opening a picker on. Falls back to
  /// today so a viewing you never dated still opens somewhere sensible.
  DateTime get pickerDate =>
      at == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(at!);

  void setDate(DateTime? date, String newPrecision) {
    precision = precisions.contains(newPrecision) ? newPrecision : 'unknown';
    at = _snap(date, precision);
  }

  /// Re-snaps the stored moment against a new precision, so switching from
  /// "day" to "year" drops the day rather than keeping a claim behind it.
  void setPrecision(String newPrecision) => setDate(pickerDate, newPrecision);

  /// Newest first; anything undated sinks to the bottom rather than
  /// claiming a place in the order.
  static int compare(Viewing a, Viewing b) => _key(b).compareTo(_key(a));
  static int _key(Viewing v) => v.isDated ? v.at! : -1;

  factory Viewing.fromJson(Map<String, dynamic> json) {
    final raw = json['at'];
    final at = switch (raw) {
      int v => v,
      double v => v.round(),
      String v => int.tryParse(v),
      _ => null,
    };
    final precision = json['precision'] as String?;
    // A stamp with no stated precision came from somewhere exact; a
    // precision with no stamp is not a date at all.
    final safe = at == null
        ? 'unknown'
        : (precisions.contains(precision) ? precision! : 'day');
    // A hand-edited backup can claim "year" over a mid-year stamp. Normalise
    // on the way in, so the invariant holds for every viewing in memory.
    return Viewing(
      at: _snapMs(at, safe),
      precision: safe,
      location: json['location'] as String? ?? '',
      company: json['company'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at,
    'precision': precision,
    'location': location,
    'company': company,
  };

  Viewing copy() => Viewing(
    at: at,
    precision: precision,
    location: location,
    company: company,
  );
}
