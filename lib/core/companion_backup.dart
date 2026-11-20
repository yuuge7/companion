import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../anime/anime_library.dart';
import '../books/services/storage_service.dart';
import '../film/app_state.dart' as film;
import '../manga/app_state.dart' as manga;
import '../manga/models/manga_entry.dart';
import 'atomic_file.dart';
import 'companion_data.dart';

class CompanionBackupPreview {
  const CompanionBackupPreview({
    required this.books,
    required this.mangaEntries,
    required this.filmState,
    required this.animeState,
    required this.settings,
    required this.preferences,
    required this.createdAt,
    required this.bookSnapshots,
  });
  final ImportData books;
  final List<MangaEntry> mangaEntries;
  final Map<String, dynamic> filmState, animeState, settings, preferences;
  final DateTime createdAt;
  final Map<String, Uint8List> bookSnapshots;
  Map<String, int> get counts => {
    'Books': books.books.length,
    'Manga': mangaEntries.length,
    'Film': (filmState['entries'] as List).length,
    'Anime': ((animeState['library'] as Map)['entries'] as List).length,
  };
}

class CompanionBackup {
  CompanionBackup(this.data);
  final CompanionData data;
  static const maxBytes = 150 * 1024 * 1024;
  static const _names = {
    'books.bcbackup',
    'manga.json',
    'film.json',
    'anime.json',
    'settings.json',
    'preferences.json',
  };
  static final _snapshotName = RegExp(r'^book-snapshots/[0-9-]+\.bcbackup$');
  Future<File> get _recovery =>
      data.books.storage.file('companion-before-restore.companion');
  Future<File> get _journal =>
      data.books.storage.file('companion-restore-pending.json');
  Future<bool> hasRecovery() async => (await _recovery).exists();
  Future<Uint8List> recoveryBytes() async => (await _recovery).readAsBytes();

  Future<Uint8List> create({bool recoveryCopy = false}) async {
    await Future.wait([
      data.books.settle(),
      data.anime.settle(),
      data.mangaLibrary.settle(),
      data.filmLibrary.settle(),
      data.settings.settle(),
    ]);
    if (!recoveryCopy &&
        (data.hasLoadFailure ||
            data.books.saveError != null ||
            data.filmLibrary.saveError != null)) {
      throw const FormatException(
        'Recover the unreadable library or resolve its save error before creating a complete backup.',
      );
    }
    final books = data.books.allBooks;
    final files = <String, List<int>>{
      'manga.json': utf8.encode(
        jsonEncode(data.mangaLibrary.entries.map((e) => e.toJson()).toList()),
      ),
      'film.json': utf8.encode(jsonEncode(data.filmLibrary.companionState())),
      'anime.json': utf8.encode(jsonEncode(data.anime.companionState())),
      'settings.json': utf8.encode(jsonEncode(data.settings.toJson())),
      'preferences.json': utf8.encode(
        jsonEncode({
          'mode': data.preferences.getString('companion-mode-v1') ?? 'books',
          'mangaSort': data.mangaLibrary.sortMode.name,
          'filmSort': data.filmLibrary.sortMode.name,
        }),
      ),
    };
    files['books.bcbackup'] = await data.books.storage.backupBytes(books);
    var totalSize = files.values.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    );
    for (final snapshot in (await data.books.storage.snapshots()).take(10)) {
      final name = 'book-snapshots/${p.basename(snapshot.path)}';
      if (!_snapshotName.hasMatch(name)) {
        throw const FormatException(
          'An unreadable snapshot name prevents a complete backup.',
        );
      }
      totalSize += await snapshot.length();
      if (totalSize > maxBytes) {
        throw const FormatException(
          'Complete backup exceeds 150 MB. Export individual libraries instead.',
        );
      }
      files[name] = await snapshot.readAsBytes();
    }
    final archive = Archive();
    if (files.values.fold<int>(0, (sum, b) => sum + b.length) > maxBytes) {
      throw const FormatException(
        'Complete backup exceeds 150 MB. Export individual libraries instead.',
      );
    }
    for (final file in files.entries) {
      archive.addFile(ArchiveFile(file.key, file.value.length, file.value));
    }
    final manifest = utf8.encode(
      jsonEncode({
        'app': 'Companion',
        'schemaVersion': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'files': {
          for (final file in files.entries)
            file.key: sha256.convert(file.value).toString(),
        },
      }),
    );
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  CompanionBackupPreview decode(Uint8List bytes) {
    try {
      if (bytes.length > maxBytes) {
        throw const FormatException('Backup exceeds 150 MB.');
      }
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(bytes);
      final headers = decoder.directory.fileHeaders;
      if (headers.length < _names.length + 1 ||
          headers.length > _names.length + 11 ||
          headers.map((e) => e.filename).toSet().length != headers.length) {
        throw const FormatException('Incomplete backup or duplicate files.');
      }
      final files = <String, Uint8List>{};
      var size = 0;
      for (final file in archive.files) {
        size += file.size;
        if (!file.isFile ||
            file.isSymbolicLink ||
            size > maxBytes ||
            (!_names.contains(file.name) &&
                file.name != 'manifest.json' &&
                !_snapshotName.hasMatch(file.name))) {
          throw const FormatException('Unsafe or oversized backup.');
        }
        files[file.name] = file.content;
      }
      final manifest = jsonDecode(utf8.decode(files['manifest.json']!)) as Map;
      if (manifest['app'] != 'Companion' || manifest['schemaVersion'] != 1) {
        throw const FormatException(
          'Choose a complete Companion backup (.companion).',
        );
      }
      final hashes = manifest['files'] as Map;
      if (hashes.length != files.length - 1 ||
          !hashes.keys.toSet().containsAll(_names)) {
        throw const FormatException('Incomplete backup manifest.');
      }
      for (final name in hashes.keys) {
        if (files[name] == null ||
            sha256.convert(files[name]!).toString() != hashes[name]) {
          throw const FormatException(
            'A backup checksum failed. Choose an undamaged copy.',
          );
        }
      }
      dynamic json(String name) => jsonDecode(utf8.decode(files[name]!));
      final books = data.books.storage.decodeBackup(files['books.bcbackup']!);
      final snapshots = <String, Uint8List>{};
      for (final file in files.entries.where(
        (e) => _snapshotName.hasMatch(e.key),
      )) {
        data.books.storage.decodeBackup(file.value);
        snapshots[p.basename(file.key)] = file.value;
      }
      final rows = json('manga.json') as List;
      final entries = rows
          .map((e) => MangaEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (entries.map((e) => e.id).toSet().length != entries.length ||
          entries.any((e) => e.title.trim().isEmpty)) {
        throw const FormatException('Invalid manga entries.');
      }
      final filmState = json('film.json') as Map<String, dynamic>;
      final animeState = json('anime.json') as Map<String, dynamic>;
      film.AppState.validateCompanionState(filmState);
      AnimeLibrary.validateCompanionState(animeState);
      final settings = json('settings.json') as Map<String, dynamic>;
      _validateSettings(settings);
      final preferences = json('preferences.json') as Map<String, dynamic>;
      if (!{'books', 'manga', 'film', 'anime'}.contains(preferences['mode']) ||
          !manga.SortMode.values.asNameMap().containsKey(
            preferences['mangaSort'],
          ) ||
          !film.SortMode.values.asNameMap().containsKey(
            preferences['filmSort'],
          )) {
        throw const FormatException('Invalid backup preferences.');
      }
      return CompanionBackupPreview(
        books: books,
        mangaEntries: entries,
        filmState: filmState,
        animeState: animeState,
        settings: settings,
        preferences: preferences,
        bookSnapshots: snapshots,
        createdAt: DateTime.parse(manifest['createdAt'] as String),
      );
    } on FormatException {
      rethrow;
    } on LibraryFormatException catch (e) {
      throw FormatException(e.message);
    } catch (_) {
      throw const FormatException(
        'Damaged or incomplete Companion backup. Nothing was restored.',
      );
    }
  }

  static void _validateSettings(Map<String, dynamic> settings) {
    if (!{'system', 'light', 'dark'}.contains(settings['theme']) ||
        !{
          'exact',
          'approximate',
          'unknown',
        }.contains(settings['defaultPrecision']) ||
        !{0, 1}.contains(settings['firstDayOfWeek']) ||
        settings['goalYear'] is! int ||
        settings['goalTarget'] is! int ||
        settings['goalUnit'] is! String ||
        [
          'securePreview',
          'appLock',
          'dynamicColor',
          'autoSnapshots',
        ].any((k) => settings[k] is! bool)) {
      throw const FormatException('Invalid shared settings.');
    }
  }

  List<Future<void> Function()> _steps(CompanionBackupPreview preview) => [
    () => data.books.restoreCompanion(preview.books),
    () async {
      final folder = Directory(
        p.join((await data.books.storage.directory).path, 'snapshots'),
      );
      for (final file in preview.bookSnapshots.entries) {
        await atomicWrite(File(p.join(folder.path, file.key)), file.value);
      }
      for (final obsolete in await data.books.storage.snapshots()) {
        if (!preview.bookSnapshots.containsKey(p.basename(obsolete.path))) {
          await obsolete.delete();
        }
      }
    },
    () => data.mangaLibrary.restoreCompanion(preview.mangaEntries),
    () => data.filmLibrary.restoreCompanion(preview.filmState),
    () => data.anime.restoreCompanion(preview.animeState),
    () async {
      if (!await data.preferences.setString(
        'companion-mode-v1',
        preview.preferences['mode'] as String,
      )) {
        throw const FileSystemException('Could not save library preference.');
      }
      await data.mangaLibrary.restoreSort(
        manga.SortMode.values.byName(preview.preferences['mangaSort']),
      );
      data.filmLibrary.setSort(
        film.SortMode.values.byName(preview.preferences['filmSort']),
      );
      if (!await data.settings.update(preview.settings)) {
        throw const FileSystemException('Could not restore shared settings.');
      }
    },
  ];

  Future<void> restore(CompanionBackupPreview preview) async {
    // A durable rollback copy and journal also cover process termination mid-restore.
    final beforeBytes = await create(recoveryCopy: true);
    final before = decode(beforeBytes);
    await atomicWrite(await _recovery, beforeBytes);
    await atomicWrite(await _journal, utf8.encode('{"pending":true}'));
    try {
      for (final step in _steps(preview)) {
        await step();
      }
      await (await _journal).delete();
    } catch (_) {
      var rollbackFailed = false;
      for (final step in _steps(before)) {
        try {
          await step();
        } catch (_) {
          rollbackFailed = true;
        }
      }
      if (!rollbackFailed) await (await _journal).delete();
      throw FormatException(
        rollbackFailed
            ? 'Restore stopped. Restart Companion to recover your previous libraries. The recovery backup has been kept.'
            : 'Restore could not finish. Your previous libraries have been restored.',
      );
    }
  }

  Future<void> recoverInterruptedRestore() async {
    final journal = await _journal;
    if (!await journal.exists()) return;
    final previous = decode(await recoveryBytes());
    for (final step in _steps(previous)) {
      await step();
    }
    await journal.delete();
  }
}
