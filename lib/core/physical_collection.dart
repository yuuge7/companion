enum Ownership {
  untracked('Not tracked'),
  owned('Owned'),
  borrowed('Borrowed'),
  wishlist('Not owned');

  const Ownership(this.label);
  final String label;
}

class PhysicalCollection {
  const PhysicalCollection({
    this.ownership = Ownership.untracked,
    this.shelf = '',
    this.borrowedFrom = '',
    this.lentTo = '',
    this.totalVolumes,
    this.volumes = const [],
  });

  final Ownership ownership;
  final String shelf, borrowedFrom, lentTo;
  final int? totalVolumes;
  final List<int> volumes;
  List<int> get missingVolumes {
    if (totalVolumes == null) return const [];
    final present = volumes.toSet();
    return [
      for (var i = 1; i <= totalVolumes!; i++)
        if (!present.contains(i)) i,
    ];
  }

  bool get isTracked =>
      ownership != Ownership.untracked ||
      shelf.isNotEmpty ||
      borrowedFrom.isNotEmpty ||
      lentTo.isNotEmpty ||
      totalVolumes != null ||
      volumes.isNotEmpty;
  String get summary => [
    ownership.label,
    if (shelf.isNotEmpty) shelf,
    if (borrowedFrom.isNotEmpty) 'Borrowed from $borrowedFrom',
    if (lentTo.isNotEmpty) 'Lent to $lentTo',
    if (totalVolumes != null) '${volumes.length} of $totalVolumes volumes',
  ].join(' · ');

  PhysicalCollection copyWith({
    Ownership? ownership,
    String? shelf,
    String? borrowedFrom,
    String? lentTo,
    int? totalVolumes,
    bool clearTotal = false,
    List<int>? volumes,
  }) => PhysicalCollection(
    ownership: ownership ?? this.ownership,
    shelf: shelf ?? this.shelf,
    borrowedFrom: borrowedFrom ?? this.borrowedFrom,
    lentTo: lentTo ?? this.lentTo,
    totalVolumes: clearTotal ? null : totalVolumes ?? this.totalVolumes,
    volumes: List.unmodifiable(volumes ?? this.volumes),
  );

  Map<String, dynamic> toJson() => {
    'ownership': ownership.name,
    'shelf': shelf,
    'borrowedFrom': borrowedFrom,
    'lentTo': lentTo,
    'totalVolumes': totalVolumes,
    'volumes': volumes,
  };
  factory PhysicalCollection.fromJson(Object? value) {
    if (value == null) return const PhysicalCollection();
    if (value is! Map) {
      throw const FormatException('Invalid collection details.');
    }
    final total = value['totalVolumes'];
    final volumes = value['volumes'] ?? [];
    if ((total != null && (total is! int || total < 1 || total > 10000)) ||
        volumes is! List ||
        volumes.any((v) => v is! int || v < 1 || v > 10000)) {
      throw const FormatException('Invalid volume numbers.');
    }
    return PhysicalCollection(
      ownership:
          Ownership.values.asNameMap()[value['ownership']] ??
          Ownership.untracked,
      shelf: value['shelf'] as String? ?? '',
      borrowedFrom: value['borrowedFrom'] as String? ?? '',
      lentTo: value['lentTo'] as String? ?? '',
      totalVolumes: total as int?,
      volumes: List.unmodifiable(volumes.cast<int>().toSet().toList()..sort()),
    );
  }

  static List<int> parseVolumes(String text) {
    final result = <int>{};
    for (final part
        in text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      final match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(part);
      if (match == null) {
        throw const FormatException('Use volumes like 1-4, 7, 9.');
      }
      final first = int.parse(match[1]!);
      final last = int.parse(match[2] ?? match[1]!);
      if (first < 1 || last < first || last > 10000) {
        throw const FormatException(
          'Volumes must be between 1 and 10,000, in ascending ranges.',
        );
      }
      result.addAll([for (var i = first; i <= last; i++) i]);
    }
    return result.toList()..sort();
  }
}
