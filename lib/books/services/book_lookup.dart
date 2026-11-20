import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class BookMetadata {
  const BookMetadata({
    required this.title,
    this.author = '',
    this.isbn = '',
    this.publisher = '',
    this.year,
    this.pages,
    this.coverUrl = '',
    this.edition = '',
  });
  final String title, author, isbn, publisher, coverUrl, edition;
  final int? year, pages;
}

/// Open Library is contacted only when a search or result is explicitly selected.
class BookLookup {
  BookLookup({this._fetch});
  final Future<Uint8List> Function(Uri)? _fetch;
  Future<Uint8List> _json(Uri uri) => _fetch == null ? _get(uri) : _fetch(uri);
  static String normalizeIsbn(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  static bool validIsbn(String value) {
    final isbn = normalizeIsbn(value);
    if (RegExp(r'^\d{9}[\dX]$').hasMatch(isbn)) {
      var sum = 0;
      for (var i = 0; i < 10; i++) {
        sum += (10 - i) * (isbn[i] == 'X' ? 10 : int.parse(isbn[i]));
      }
      return sum % 11 == 0;
    }
    if (!RegExp(r'^97[89]\d{10}$').hasMatch(isbn)) return false;
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(isbn[i]) * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }

  Future<Uint8List> _get(Uri uri, {int maxBytes = 2 * 1024 * 1024}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'Companion/1.2 (https://github.com/yuuge7/companion)';
    try {
      return await (() async {
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode != 200) {
          throw const FormatException(
            'Open Library could not answer. Try again in a moment.',
          );
        }
        final bytes = BytesBuilder();
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException(
              'The response was too large. Try a more specific title.',
            );
          }
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      })().timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const FormatException(
        'Could not connect. Check your internet connection or add the book manually.',
      );
    } on TimeoutException {
      throw const FormatException(
        'Search timed out. Try again or add the book manually.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<BookMetadata>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    if (normalizeIsbn(trimmed).length >= 10 &&
        RegExp(r'^[\dXx\s-]+$').hasMatch(trimmed)) {
      if (!validIsbn(trimmed)) {
        throw const FormatException(
          'Check the ISBN. Enter a valid ISBN-10 or ISBN-13.',
        );
      }
      final result = await edition('ISBN:${normalizeIsbn(trimmed)}');
      return result == null ? [] : [result];
    }
    final raw = jsonDecode(
      utf8.decode(
        await _json(
          Uri.https('openlibrary.org', '/search.json', {
            'title': trimmed,
            'limit': '12',
            'fields': 'title,author_name,cover_i,edition_key',
          }),
        ),
      ),
    ) as Map;
    return (raw['docs'] as List? ?? [])
        .map((doc) {
          final editions = doc['edition_key'] as List? ?? [];
          return BookMetadata(
            title: doc['title'] as String? ?? '',
            author: (doc['author_name'] as List? ?? []).join(', '),
            coverUrl: doc['cover_i'] is int
                ? 'https://covers.openlibrary.org/b/id/${doc['cover_i']}-M.jpg'
                : '',
            edition: editions.isEmpty ? '' : 'OLID:${editions.first}',
          );
        })
        .where((b) => b.title.isNotEmpty)
        .toList();
  }

  Future<BookMetadata?> edition(String key) async {
    final raw = jsonDecode(
      utf8.decode(
        await _json(
          Uri.https('openlibrary.org', '/api/books', {
            'bibkeys': key,
            'format': 'json',
            'jscmd': 'data',
          }),
        ),
      ),
    ) as Map;
    if (raw[key] is! Map) return null;
    final b = raw[key] as Map;
    final identifiers = b['identifiers'] as Map? ?? {};
    final isbns = identifiers['isbn_13'] ?? identifiers['isbn_10'] ?? [];
    final year = RegExp(r'\b(\d{4})\b')
        .firstMatch(b['publish_date'] as String? ?? '');
    return BookMetadata(
      title: b['title'] as String? ?? '',
      author: (b['authors'] as List? ?? []).map((a) => a['name']).join(', '),
      isbn: (isbns as List).firstOrNull as String? ?? '',
      publisher: (b['publishers'] as List? ?? [])
          .map((p) => p['name'])
          .join(', '),
      year: year == null ? null : int.tryParse(year[1]!),
      pages: b['number_of_pages'] as int?,
      coverUrl: (b['cover'] as Map?)?['large'] as String? ?? '',
      edition: key,
    );
  }

  Future<Uint8List?> cover(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host != 'covers.openlibrary.org' ||
        uri.scheme != 'https') {
      return null;
    }
    try {
      return await _get(uri, maxBytes: 5 * 1024 * 1024);
    } catch (_) {
      return null;
    }
  }

  Future<String?> scanIsbn() async {
    try {
      final raw = await const MethodChannel('io.github.yuuge7.companion/isbn')
          .invokeMethod<String>('scan');
      if (raw == null) return null;
      if (!validIsbn(raw)) {
        throw const FormatException(
          'That barcode is not a book ISBN. Scan the ISBN barcode or enter it below.',
        );
      }
      return normalizeIsbn(raw);
    } on MissingPluginException {
      throw const FormatException(
        'Scanning is available on Android. Enter the ISBN or search for a title below.',
      );
    } on PlatformException {
      throw const FormatException(
        'The scanner is unavailable. Update Google Play services, or enter the ISBN below.',
      );
    }
  }
}
