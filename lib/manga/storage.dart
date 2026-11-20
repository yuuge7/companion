import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/backup_type.dart';
import 'models/manga_entry.dart';

/// Persists the list as one JSON array string
class MangaStore {
  final String key;
  final String sortKey;

  final SharedPreferences _prefs;
  MangaStore(
    this._prefs, {
    this.key = 'manga-entries-v1',
    this.sortKey = 'manga-sort-mode',
  });

  /// True when the saved blob existed but could not be read back. The UI
  /// shows a recovery state for this instead of pretending the shelf is
  /// empty.
  bool loadFailed = false;
  Future<void> _writes = Future.value();
  Future<void> settle() => _writes;
  Future<void> _write(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.catchError((Object _) {});
    return result;
  }

  static Future<MangaStore> open() async =>
      MangaStore(await SharedPreferences.getInstance());

  List<MangaEntry> load() {
    loadFailed = false;
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      requireBackupType(decoded, CompanionMode.manga);
      if (decoded is! List) {
        loadFailed = true;
        return [];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MangaEntry.fromJson)
          .toList();
    } catch (_) {
      loadFailed = true;
      return [];
    }
  }

  /// Re-reads from disk, dropping the in-memory cache. Needed after the
  /// home screen widget writes to the same store.
  Future<List<MangaEntry>> reload() async {
    await settle();
    await _prefs.reload();
    return load();
  }

  Future<void> save(List<MangaEntry> entries) {
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    return _write(() async {
      if (loadFailed) {
        final damaged = _prefs.getString(key);
        if (damaged != null &&
            !await _prefs.setString(
              '$key-damaged-${DateTime.now().millisecondsSinceEpoch}',
              damaged,
            )) {
          throw StateError('Could not preserve damaged manga data.');
        }
      }
      if (!await _prefs.setString(key, raw)) {
        throw StateError('Manga could not be saved.');
      }
    });
  }

  /// Name of the last chosen sort, or null if none was ever picked.
  String? loadSortMode() => _prefs.getString(sortKey);

  Future<void> saveSortMode(String name) => _write(() async {
    if (!await _prefs.setString(sortKey, name)) {
      throw StateError('Manga sort could not be saved.');
    }
  });

  /// Returns null when the file is not a JSON array of entries.
  static List<MangaEntry>? parseExport(String raw) {
    try {
      final decoded = jsonDecode(raw);
      requireBackupType(decoded, CompanionMode.manga);
      if (decoded is! List) return null;
      final entries = decoded
          .whereType<Map<String, dynamic>>()
          .map(MangaEntry.fromJson)
          .where((e) => e.title.trim().isNotEmpty)
          .toList();
      return entries;
    } catch (_) {
      return null;
    }
  }

  static String toExportJson(List<MangaEntry> entries) =>
      const JsonEncoder.withIndent('  ')
          .convert(entries.map((e) => e.toJson()).toList());
}
