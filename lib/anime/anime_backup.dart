import '../core/import_text.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../core/backup_type.dart';
import 'anime_entry.dart';

class AnimeBackup {
  static const maxBytes = 10 * 1024 * 1024;
  static const maxEntries = 20000;

  static String encode(List<AnimeEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert({
        'app': 'Anime Companion',
        'schemaVersion': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'count': entries.length,
        'entries': entries.map((e) => e.toJson()).toList(),
      });

  static List<AnimeEntry> parse(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Anime imports are limited to 10 MB.');
    }
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      // Check decompressed size while streaming to avoid allocating a gzip bomb.
      final chunks = <int>[];
      final limited = _LimitedSink(chunks, maxBytes);
      final decoder = gzip.decoder.startChunkedConversion(limited);
      decoder.add(bytes);
      decoder.close();
      bytes = Uint8List.fromList(chunks);
    }
    final text = readImportText(bytes);
    if (text.startsWith('<')) return _mal(text);
    final decoded = jsonDecode(text);
    // Storage decoding remains strict: only the file-import path accepts AP.
    if (decoded is Map && decoded['app'] == null) {
      requireBackupType(decoded, CompanionMode.anime);
      return _animePlanet(decoded);
    }
    return decodeDocument(decoded);
  }

  /// File-import limits do not make a larger, already-saved library unreadable.
  static List<AnimeEntry> decodeDocument(
    Object? decoded, {
    bool enforceLimits = true,
  }) {
    requireBackupType(decoded, CompanionMode.anime);
    if (decoded is! Map ||
        decoded['app'] != 'Anime Companion' ||
        decoded['schemaVersion'] != 1 ||
        decoded['entries'] is! List) {
      throw const FormatException(
        'Choose Anime Companion JSON, Anime-Planet anime JSON or MyAnimeList anime XML.',
      );
    }
    final rows = decoded['entries'] as List;
    if (decoded['count'] != rows.length ||
        (enforceLimits && rows.length > maxEntries)) {
      throw const FormatException('Invalid anime backup count.');
    }
    final entries = <AnimeEntry>[];
    final ids = <String>{};
    for (var i = 0; i < rows.length; i++) {
      try {
        final entry = AnimeEntry.fromJson(
          Map<String, dynamic>.from(rows[i] as Map),
        );
        if (!ids.add(entry.id)) {
          throw const FormatException('Duplicate anime id.');
        }
        entries.add(entry);
      } catch (e) {
        throw FormatException(
          'Anime row ${i + 1}: ${e is FormatException ? e.message : "Invalid field."}',
        );
      }
    }
    return entries;
  }

  /// AP exports progress, status, rating, watch count and dates, but no series
  /// format, length or runtime. Keep those unknown instead of guessing TV/minutes.
  static List<AnimeEntry> _animePlanet(Map document) {
    final rows = document['entries'];
    if (rows is! List || rows.isEmpty) {
      // An empty, untyped external list cannot prove that it is anime.
      throw const FormatException(
        'Choose a non-empty Anime-Planet anime JSON export.',
      );
    }
    if (rows.length > maxEntries) {
      throw const FormatException('Too many anime titles.');
    }
    final result = <AnimeEntry>[];
    final ids = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < rows.length; i++) {
      try {
        final row = rows[i];
        if (row is! Map ||
            !row.containsKey('eps') ||
            row.containsKey('ch') ||
            row.containsKey('vol')) {
          throw const FormatException(
            'Choose the anime export, not manga or a mixed list.',
          );
        }
        final rawTitle = row['name'];
        if (rawTitle is! String || rawTitle.trim().isEmpty) {
          throw const FormatException('Anime title is required.');
        }
        final title = rawTitle.trim();
        final id = 'ap-${sha256.convert(utf8.encode(title.toLowerCase()))}';
        if (!ids.add(id)) throw const FormatException('Duplicate anime title.');
        final status = switch (row['status']
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('’', "'")) {
          'watched' => AnimeStatus.completed,
          'watching' => AnimeStatus.watching,
          'want to watch' => AnimeStatus.planned,
          'stalled' => AnimeStatus.onHold,
          'dropped' => AnimeStatus.dropped,
          "won't watch" => AnimeStatus.wontWatch,
          _ => throw const FormatException('Unrecognized Anime-Planet status.'),
        };
        int count(String key) {
          final raw = row[key];
          if (raw == null || raw == '') return 0;
          final value = raw is num ? raw : num.tryParse('$raw');
          if (value == null ||
              !value.isFinite ||
              value < 0 ||
              value > 100000 ||
              value != value.roundToDouble()) {
            throw FormatException('Invalid $key.');
          }
          return value.toInt();
        }

        String date(String key) {
          final raw = row[key];
          if (raw == null || raw == '') return '';
          if (raw is! String) throw FormatException('Invalid $key.');
          final match = RegExp(
            r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?(?:[ T].*)?$',
          ).firstMatch(raw.trim());
          if (match == null) throw FormatException('Invalid $key.');
          final year = match[1]!;
          final month = match[2];
          final day = match[3];
          if (year == '0000') return '';
          if (month == null || month == '00') return year;
          if (day == null || day == '00') return '$year-$month';
          return '$year-$month-$day';
        }

        final rawRating = row['rating'];
        final rating = rawRating == null || rawRating == ''
            ? 0.0
            : double.tryParse('$rawRating');
        if (rating == null ||
            !rating.isFinite ||
            rating < 0 ||
            rating > 5 ||
            rating * 2 != (rating * 2).roundToDouble()) {
          throw const FormatException('Invalid Anime-Planet rating.');
        }
        final times = count('times');
        final entry = AnimeEntry(
          id: id,
          title: title,
          animeFormat: AnimeFormat.unknown,
          status: status,
          currentEpisode: count('eps'),
          rating: rating,
          rewatches: times > 1 ? times - 1 : 0,
          startedDate: date('started'),
          finishedDate: date('completed'),
          addedAt: now,
          updatedAt: now,
        );
        result.add(
          AnimeEntry.fromJson(entry.toJson(), fromAnimePlanetExport: true),
        );
      } catch (error) {
        throw FormatException(
          'Anime-Planet row ${i + 1}: ${error is FormatException ? error.message : "Invalid field."}',
        );
      }
    }
    return result;
  }

  static List<AnimeEntry> _mal(String text) {
    final document = XmlDocument.parse(text);
    if (document.rootElement.name.local != 'myanimelist' ||
        document.findAllElements('manga').isNotEmpty) {
      throw const FormatException(
        'Choose a MyAnimeList anime export, not a manga list.',
      );
    }
    final rows = document.findAllElements('anime').toList();
    if (rows.length > maxEntries) {
      throw const FormatException('Too many anime titles.');
    }
    return rows.map((row) {
      String field(String name) => row.getElement(name)?.innerText.trim() ?? '';
      int? integer(String name) {
        final raw = field(name);
        if (raw.isEmpty || raw == '0') return null;
        final value = int.tryParse(raw);
        if (value == null || value < 0) throw FormatException('Invalid $name.');
        return value;
      }

      String date(String name) {
        final raw = field(name);
        if (raw.isEmpty || raw.startsWith('0000')) return '';
        return raw.endsWith('-00-00')
            ? raw.substring(0, 4)
            : raw.endsWith('-00')
            ? raw.substring(0, 7)
            : raw;
      }

      final format = switch (field('series_type').toLowerCase()) {
        'movie' || '3' => AnimeFormat.movie,
        'ova' || '2' => AnimeFormat.ova,
        'ona' || '5' => AnimeFormat.ona,
        'special' || '4' => AnimeFormat.special,
        _ => AnimeFormat.tv,
      };
      final status = switch (field('my_status').toLowerCase()) {
        'watching' || '1' => AnimeStatus.watching,
        'completed' || '2' => AnimeStatus.completed,
        'on-hold' || '3' => AnimeStatus.onHold,
        'dropped' || '4' => AnimeStatus.dropped,
        _ => AnimeStatus.planned,
      };
      final malId = integer('series_animedb_id');
      return AnimeEntry.fromJson(
        AnimeEntry(
          id: malId == null ? null : 'mal-$malId',
          malId: malId,
          title: field('series_title'),
          animeFormat: format,
          status: status,
          currentEpisode: format == AnimeFormat.movie
              ? 0
              : integer('my_watched_episodes') ?? 0,
          totalEpisodes: integer('series_episodes'),
          rating: ((integer('my_score') ?? 0) / 2).clamp(0, 5).toDouble(),
          note: field('my_comments'),
          tags: field('my_tags')
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          startedDate: date('my_start_date'),
          finishedDate: date('my_finish_date'),
          rewatches: integer('my_times_watched') ?? 0,
        ).toJson(),
      );
    }).toList();
  }

  static String csv(List<AnimeEntry> entries) {
    String cell(Object? raw) {
      var value = raw?.toString() ?? '';
      if (RegExp(r'^[=+\-@\t\r]').hasMatch(value)) value = "'$value";
      return '"${value.replaceAll('"', '""')}"';
    }

    return [
      [
        'title',
        'animeFormat',
        'status',
        'currentEpisode',
        'totalEpisodes',
        'watchedMinutes',
        'episodeMinutes',
        'studio',
        'year',
        'season',
        'rating',
        'rewatches',
        'tags',
        'note',
      ],
      ...entries.map(
        (e) => [
          e.title,
          e.animeFormat.name,
          e.status.name,
          e.currentEpisode,
          e.totalEpisodes,
          e.watchedMinutes,
          e.episodeMinutes,
          e.studio,
          e.year,
          e.season,
          e.rating,
          e.rewatches,
          e.tags.join(', '),
          e.note,
        ],
      ),
    ].map((row) => row.map(cell).join(',')).join('\r\n');
  }
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.output, this.limit);
  final List<int> output;
  final int limit;
  @override
  void add(List<int> data) {
    if (output.length + data.length > limit) {
      throw const FormatException('Decompressed anime backup exceeds 10 MB.');
    }
    output.addAll(data);
  }

  @override
  void close() {}
}
