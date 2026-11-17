import 'dart:convert';

import 'models/shelf_entry.dart';

enum ImportChange { added, updated, unchanged, conflict }

class ImportRow {
  final ShelfEntry incoming;
  final ShelfEntry? local;
  final ImportChange change;
  bool useIncoming;
  ImportRow(this.incoming, this.local, this.change)
    : useIncoming =
          change == ImportChange.added || change == ImportChange.updated;
}

class ImportPlan {
  final List<ImportRow> rows;
  ImportPlan(List<ShelfEntry> local, List<ShelfEntry> incoming) : rows = [] {
    final byId = {for (final e in local) e.id: e};
    final byTitle = {for (final e in local) identity(e): e};
    for (final entry in incoming) {
      final existing = byId[entry.id] ?? byTitle[identity(entry)];
      var change = ImportChange.added;
      if (existing != null) {
        final a = existing.toJson()..remove('id');
        final b = entry.toJson()..remove('id');
        if (jsonEncode(a) == jsonEncode(b)) {
          change = ImportChange.unchanged;
        } else if (entry.lastUpdated > existing.lastUpdated) {
          change = ImportChange.updated;
        } else {
          change = ImportChange.conflict;
        }
      }
      rows.add(ImportRow(entry.copy(), existing?.copy(), change));
    }
  }
  static String identity(ShelfEntry e) =>
      '${e.kind}|${e.title.trim().toLowerCase()}|${e.year}';
  int count(ImportChange change) =>
      rows.where((r) => r.change == change).length;
}
