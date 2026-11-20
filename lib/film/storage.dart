import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backup_type.dart';
import '../core/atomic_file.dart' as files;
import 'diagnostics.dart';
import 'models/shelf_entry.dart';

class ImportIssue {
  final int row;
  final String reason;
  const ImportIssue(this.row, this.reason);
}

class ImportDocument {
  final List<ShelfEntry> entries;
  final List<ImportIssue> issues;
  final String? error;
  const ImportDocument(this.entries, this.issues, [this.error]);
  bool get valid => error == null;
}

class TrashEntry {
  final ShelfEntry entry;
  final int deletedAt;
  TrashEntry(this.entry, this.deletedAt);
  int get daysLeft =>
      (30 -
              DateTime.now()
                  .difference(DateTime.fromMillisecondsSinceEpoch(deletedAt))
                  .inDays)
          .clamp(0, 30);
  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'deletedAt': deletedAt,
  };
}

/// The legacy preference is read only during migration and is never renamed.
/// Every subsequent commit replaces a flushed temporary file atomically.
class ShelfStore {
  static const legacyKey = 'film-entries-v1';
  static const maxImportBytes = 10 * 1024 * 1024;
  static const maxEntries = 20000;
  static const appVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '1.0.0',
  );
  final SharedPreferences _prefs;
  final Directory? directory;
  String? _raw;
  Future<void> _writes = Future.value();
  Future<void> settle() => _writes;
  List<TrashEntry> trash = [];
  List<ShelfEntry>? snapshot;
  int? snapshotAt;
  bool loadFailed = false;
  bool recovered = false;
  bool get needsMigration => _raw == null;

  ShelfStore(this._prefs, {this.directory});

  static Future<ShelfStore> open({
    Directory? directory,
    bool memoryOnly = false,
  }) async {
    final store = ShelfStore(
      await SharedPreferences.getInstance(),
      directory: memoryOnly
          ? null
          : directory ?? await getApplicationSupportDirectory(),
    );
    final dir = store.directory;
    if (dir != null) {
      try {
        await dir.create(recursive: true);
        final file = File('${dir.path}/shelf-v2.json');
        if (await file.exists()) store._raw = await file.readAsString();
      } catch (error, stack) {
        store._raw = 'Unreadable shelf';
        Diagnostics.record(error, stack, source: 'storage open');
      }
    } else {
      store._raw = store._prefs.getString('shelf-v2-test');
    }
    return store;
  }

  List<ShelfEntry> _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['entries'] is! List ||
        decoded['schemaVersion'] != 2) {
      throw const FormatException('Invalid shelf');
    }
    final entries = _storedEntries(decoded['entries']);
    final rawTrash = decoded['trash'];
    trash = rawTrash is List
        ? rawTrash
              .map((t) {
                return TrashEntry(
                  ShelfEntry.fromJson(
                    Map<String, dynamic>.from(t['entry'] as Map),
                  ),
                  t['deletedAt'] as int,
                );
              })
              .where((t) => t.daysLeft > 0)
              .toList()
        : [];
    final snap = decoded['snapshot'];
    snapshot = null;
    snapshotAt = null;
    if (snap is Map && snap['entries'] is List) {
      snapshot = _storedEntries(snap['entries']);
      snapshotAt = snap['at'] as int?;
    }
    return entries;
  }

  // File-import limits must never make a shelf the app already saved unreadable.
  static List<ShelfEntry> _storedEntries(dynamic rows) {
    if (rows is! List) throw const FormatException('Damaged shelf');
    return rows
        .map(
          (row) => ShelfEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  List<ShelfEntry> load() {
    loadFailed = false;
    trash = [];
    snapshot = null;
    snapshotAt = null;
    try {
      if (_raw != null) return _decode(_raw!);
      final legacy = _prefs.getString(legacyKey);
      if (legacy == null) return [];
      return _storedEntries(jsonDecode(legacy));
    } catch (error, stack) {
      Diagnostics.record(error, stack, source: 'storage load');
      if (directory != null) {
        try {
          final previous = File('${directory!.path}/shelf-v2.previous.json');
          if (previous.existsSync()) {
            final entries = _decode(previous.readAsStringSync());
            recovered = true;
            return entries;
          }
        } catch (_) {
          /* Keep the damaged originals for recovery. */
        }
      }
      loadFailed = true;
      return [];
    }
  }

  Future<void> save(List<ShelfEntry> entries) {
    final raw = jsonEncode({
      'schemaVersion': 2,
      'entries': entries.map((e) => e.toJson()).toList(),
      'trash': trash
          .where((t) => t.daysLeft > 0)
          .map((t) => t.toJson())
          .toList(),
      'snapshot': snapshot == null
          ? null
          : {
              'at': snapshotAt,
              'entries': snapshot!.map((e) => e.toJson()).toList(),
            },
    });
    final write = _writes.then((_) async {
      if (directory == null) {
        await _prefs.setString('shelf-v2-test', raw);
      } else {
        if (_raw != null && !loadFailed && !recovered) {
          final previous = File(
            '${directory!.path}/shelf-v2.previous.json.tmp',
          );
          await previous.writeAsString(_raw!, flush: true);
          await previous.rename('${directory!.path}/shelf-v2.previous.json');
        }
        await files.atomicWrite(
          File('${directory!.path}/shelf-v2.json'),
          utf8.encode(raw),
        );
      }
      _raw = raw;
      loadFailed = false;
      recovered = false;
    });
    _writes = write.catchError((Object error, StackTrace stack) {
      Diagnostics.record(error, stack, source: 'storage save');
    });
    return write;
  }

  static ImportDocument parseDocument(String raw) {
    if (raw.length > maxImportBytes ||
        utf8.encode(raw).length > maxImportBytes) {
      return const ImportDocument(
        [],
        [],
        'This file is larger than the 10 MB limit.',
      );
    }
    try {
      dynamic decoded = jsonDecode(raw);
      requireBackupType(decoded, CompanionMode.film);
      if (decoded is Map) {
        if (decoded['app'] != 'Screen Companion' ||
            decoded['schemaVersion'] != 2) {
          return const ImportDocument(
            [],
            [],
            'This backup format or version is not supported.',
          );
        }
        if (decoded['count'] != null &&
            (decoded['entries'] is! List ||
                decoded['count'] != (decoded['entries'] as List).length)) {
          return const ImportDocument(
            [],
            [],
            'The backup count does not match its titles. Check the original file.',
          );
        }
        decoded = decoded['entries'];
      }
      if (decoded is! List) {
        return const ImportDocument(
          [],
          [],
          'Expected a backup envelope or an array of titles.',
        );
      }
      if (decoded.length > maxEntries) {
        return const ImportDocument(
          [],
          [],
          'A backup can contain at most 20,000 titles.',
        );
      }
      final entries = <ShelfEntry>[];
      final issues = <ImportIssue>[];
      final ids = <String>{};

      for (var i = 0; i < decoded.length; i++) {
        try {
          final row = decoded[i];
          if (row is! Map<String, dynamic>) {
            throw const FormatException('Expected an object');
          }
          if (row['title'] is! String ||
              (row['title'] as String).trim().isEmpty) {
            throw const FormatException('Missing title');
          }
          if ((row['title'] as String).length > 1000) {
            throw const FormatException('Title is too long');
          }
          for (final field in [
            'year',
            'runtime',
            'episodes',
            'watched',
            'rating',
            'plays',
            'watchedAt',
            'addedAt',
            'lastUpdated',
          ]) {
            final value = row[field];
            final number = value == null ? null : num.tryParse('$value');
            if (value != null &&
                (number == null ||
                    !number.isFinite ||
                    number.abs() > 8640000000000000)) {
              throw FormatException('Invalid $field number');
            }
          }
          for (final field in ['tags', 'seasons', 'viewings']) {
            if (row[field] != null && row[field] is! List) {
              throw FormatException('Invalid $field list');
            }
          }
          if ((row['tags'] is List && (row['tags'] as List).length > 100) ||
              (row['seasons'] is List &&
                  (row['seasons'] as List).length > 1000)) {
            throw const FormatException('Too many tags or seasons');
          }
          if (row['tags'] is List &&
              (row['tags'] as List).any((t) => t is! String)) {
            throw const FormatException('Tags must be text');
          }
          if (row['seasons'] is List &&
              (row['seasons'] as List).any(
                (n) =>
                    (int.tryParse('$n') ?? 0) < 1 ||
                    (int.tryParse('$n') ?? 0) > 10000,
              )) {
            throw const FormatException('Invalid season length');
          }
          if (row['viewings'] is List) {
            for (final viewing in row['viewings'] as List) {
              if (viewing is! Map<String, dynamic>) {
                throw const FormatException('Invalid viewing');
              }
              final at = viewing['at'];
              if (at != null &&
                  (num.tryParse('$at') == null ||
                      num.parse('$at').abs() > 8640000000000000)) {
                throw const FormatException('Invalid viewing date');
              }
            }
          }
          if (row['plays'] != null &&
              (num.tryParse('${row['plays']}') ?? 0) > 10000) {
            throw const FormatException('Too many legacy viewings');
          }
          if (row['viewings'] is List &&
              (row['viewings'] as List).length > 10000) {
            throw const FormatException('Too many viewings');
          }
          final entry = ShelfEntry.fromJson(row);
          if (entry.runtime != null &&
              (entry.runtime! <= 0 || entry.runtime! > 100000)) {
            throw const FormatException('Invalid runtime');
          }
          if (entry.episodes != null &&
              (entry.episodes! <= 0 || entry.episodes! > 100000)) {
            throw const FormatException('Invalid episode count');
          }
          if (entry.episodes != null && entry.watched > entry.episodes!) {
            throw const FormatException('Progress exceeds episode count');
          }
          if (ids.contains(entry.id)) {
            throw const FormatException('Duplicate title in this file');
          }
          ids.add(entry.id);
          entries.add(entry);
        } catch (error) {
          issues.add(
            ImportIssue(
              i + 1,
              error is FormatException
                  ? error.message.toString()
                  : 'Invalid field type or date',
            ),
          );
        }
      }
      return ImportDocument(entries, issues);
    } catch (_) {
      return const ImportDocument(
        [],
        [],
        'The JSON is damaged, truncated or unreadable.',
      );
    }
  }

  static Future<ImportDocument> parseInBackground(String raw) =>
      compute(parseDocument, raw);
  static List<ShelfEntry>? parseExport(String raw) {
    final result = parseDocument(raw);
    return result.valid ? result.entries : null;
  }

  static String toExportJson(List<ShelfEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert({
        'app': 'Screen Companion',
        'schemaVersion': 2,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': appVersion,
        'count': entries.length,
        'entries': entries.map((e) => e.toJson()).toList(),
      });

  static String toCsv(List<ShelfEntry> entries) {
    String cell(Object? v) {
      var value = v?.toString() ?? '';
      if (RegExp(r'^[=+\-@\t\r]').hasMatch(value)) value = "'$value";
      return '"${value.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[
      [
        'id',
        'title',
        'kind',
        'year',
        'director',
        'runtime',
        'episodes',
        'watched',
        'status',
        'rating',
        'tags',
        'note',
        'seasons',
        'viewings',
        'posterUrl',
        'watchUrl',
        'addedAt',
        'lastUpdated',
      ],
      for (final e in entries)
        [
          e.id,
          e.title,
          e.kind,
          e.year,
          e.director,
          e.runtime,
          e.episodes,
          e.watched,
          e.status,
          e.rating,
          e.tags.join('; '),
          e.note,
          e.seasons.join('; '),
          jsonEncode(e.viewings.map((v) => v.toJson()).toList()),
          e.posterUrl,
          e.watchUrl,
          e.addedAt,
          e.lastUpdated,
        ],
    ];
    return '\uFEFF${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }
}
