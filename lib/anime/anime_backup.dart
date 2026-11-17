import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final text = utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
    if (text.startsWith('<')) return _mal(text);
    final decoded = jsonDecode(text);
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
        'Choose an Anime Companion JSON or MyAnimeList anime XML backup.',
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
          rating: ((integer('my_score') ?? 0) / 2).round().clamp(0, 5),
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
