import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/atomic_file.dart';
import 'anime_backup.dart';
import 'anime_entry.dart';

class AnimeLibrary extends ChangeNotifier {
  AnimeLibrary(this.directory);
  final Directory directory;
  List<AnimeEntry> _entries = [];
  List<Map<String, dynamic>> _trash = [];
  List<AnimeEntry>? _snapshot;
  bool loadFailed = false, recovered = false, busy = false;
  String? error;
  Future<void> _writes = Future.value();
  List<AnimeEntry> get entries => List.unmodifiable(_entries);
  List<AnimeEntry> get trash =>
      _trash.map((e) => AnimeEntry.fromJson(e['entry'])).toList();
  bool get hasSnapshot => _snapshot != null;
  File get _file => File('${directory.path}/anime-v1.json');
  File get _previous => File('${directory.path}/anime-v1.previous.json');

  Future<void> settle() => _writes;
  Map<String, dynamic> companionState() => {
    'library': jsonDecode(AnimeBackup.encode(_entries)),
    'trash': _trash,
    'snapshot': _snapshot == null
        ? null
        : jsonDecode(AnimeBackup.encode(_snapshot!)),
  };

  static void validateCompanionState(Map<String, dynamic> state) {
    final temporary = AnimeLibrary(Directory.systemTemp);
    temporary._decode(jsonEncode(state));
    temporary.dispose();
  }

  Future<void> restoreCompanion(Map<String, dynamic> state) => _change(() {
    _decode(jsonEncode(state));
  });

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      _decode(await _file.readAsString());
    } catch (_) {
      try {
        _decode(await _previous.readAsString());
        recovered = true;
        error = 'Recovered the previous anime library. Export a backup.';
      } catch (_) {
        loadFailed = true;
        error = 'The anime library could not be read. Import an anime backup to recover it. Saved files have been kept.';
      }
    }
    notifyListeners();
  }

  void _decode(String raw) {
    final state = jsonDecode(raw) as Map<String, dynamic>;
    final entries = AnimeBackup.decodeDocument(
      state['library'],
      enforceLimits: false,
    );
    final threshold = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final trash = (state['trash'] as List)
        .map((row) {
          final entry = AnimeEntry.fromJson(
            Map<String, dynamic>.from(row['entry']),
          );
          if (row['deletedAt'] is! int) {
            throw const FormatException('Invalid trash date.');
          }
          return <String, dynamic>{
            'entry': entry.toJson(),
            'deletedAt': row['deletedAt'],
          };
        })
        .where((row) => row['deletedAt'] >= threshold)
        .toList();
    final snapshot = state['snapshot'] == null
        ? null
        : AnimeBackup.decodeDocument(state['snapshot'], enforceLimits: false);
    _entries = entries;
    _trash = trash;
    _snapshot = snapshot;
  }

  Future<void> _change(void Function() change) {
    final operation = _writes.then((_) async {
      final before = _entries.toList();
      final oldTrash = _trash.toList();
      final oldSnapshot = _snapshot;
      busy = true;
      notifyListeners();
      try {
        change();
        final raw = jsonEncode({
          'library': jsonDecode(AnimeBackup.encode(_entries)),
          'trash': _trash,
          'snapshot': _snapshot == null
              ? null
              : jsonDecode(AnimeBackup.encode(_snapshot!)),
        });
        if (!loadFailed && !recovered && await _file.exists()) {
          await atomicWrite(_previous, await _file.readAsBytes());
        }
        if ((loadFailed || recovered) && await _file.exists()) {
          await atomicWrite(
            File(
              '${directory.path}/anime-v1.damaged-${DateTime.now().millisecondsSinceEpoch}.json',
            ),
            await _file.readAsBytes(),
          );
        }
        await atomicWrite(_file, utf8.encode(raw));
        error = null;
        loadFailed = false;
        recovered = false;
      } catch (_) {
        _entries = before;
        _trash = oldTrash;
        _snapshot = oldSnapshot;
        error =
            'Anime changes could not be saved. Free some space and try again.';
        rethrow;
      } finally {
        busy = false;
        notifyListeners();
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> save(AnimeEntry entry) => _change(() {
    if (loadFailed) {
      throw const FormatException('Recover the saved library first.');
    }
    final validated = AnimeEntry.fromJson(entry.toJson());
    final index = _entries.indexWhere((e) => e.id == entry.id);
    _entries = [..._entries];
    if (index < 0) {
      _entries.add(validated);
    } else {
      _entries[index] = validated;
    }
  });
  Future<void> remove(String id) => _change(() {
    final entry = _entries.firstWhere((e) => e.id == id);
    _trash = [
      ..._trash,
      {
        'entry': entry.toJson(),
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
      },
    ];
    _entries = _entries.where((e) => e.id != id).toList();
  });
  Future<void> restore(String id) => _change(() {
    final row = _trash.firstWhere((e) => e['entry']['id'] == id);
    final entry = AnimeEntry.fromJson(row['entry']);
    if (_entries.any((e) => e.id == id)) {
      throw const FormatException('This anime is already in the library.');
    }
    _entries = [..._entries, entry];
    _trash = _trash.where((e) => e != row).toList();
  });
  Future<void> importEntries(
    List<AnimeEntry> incoming, {
    required bool replace,
  }) => _change(() {
    _snapshot = _entries.toList();
    if (replace) {
      _trash = [
        ..._trash,
        ..._entries.map(
          (e) => {
            'entry': e.toJson(),
            'deletedAt': DateTime.now().millisecondsSinceEpoch,
          },
        ),
      ];
      _entries = incoming.toList();
    } else {
      final merged = _entries.toList();
      for (final entry in incoming) {
        final previous = entry.importMatch(merged);
        final index = previous == null
            ? -1
            : merged.indexWhere((e) => e.id == previous.id);
        if (index < 0) {
          merged.add(entry);
        } else if (entry.updatedAt > merged[index].updatedAt) {
          merged[index] = entry.importOver(merged[index]);
        }
      }
      _entries = merged;
    }
  });
  Future<void> restoreSnapshot() => _change(() {
    if (_snapshot == null) return;
    final old = _entries;
    _entries = _snapshot!;
    _snapshot = old;
  });
}
