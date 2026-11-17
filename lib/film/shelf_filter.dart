import 'models/shelf_entry.dart';

class ShelfFilter {
  String? kind;
  int? yearFrom;
  int? yearTo;
  int minRating = 0;
  String? tag;
  int? minutes;
  bool get active =>
      kind != null ||
      yearFrom != null ||
      yearTo != null ||
      minRating > 0 ||
      tag != null ||
      minutes != null;
  bool matches(ShelfEntry e) =>
      (kind == null || e.kind == kind) &&
      (yearFrom == null || (e.year != null && e.year! >= yearFrom!)) &&
      (yearTo == null || (e.year != null && e.year! <= yearTo!)) &&
      e.rating >= minRating &&
      (tag == null || e.tags.contains(tag)) &&
      (minutes == null ||
          (e.hasRuntime &&
              e.runtime! <= minutes! &&
              (!e.isSeries || e.episodesLeft != 0)));
}
