import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;

/// Reads data only. HTML exports are never executed or loaded in a web view.
String readImportText(Uint8List bytes) {
  final text = utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
  if (!RegExp(
    r'^<(?:!doctype\s+html|html\b|head\b|body\b|pre\b|code\b|textarea\b|script\b)',
    caseSensitive: false,
  ).hasMatch(text)) {
    return text;
  }
  final document = html.parse(text);
  for (final candidate in [
    ...document
        .querySelectorAll(
          'script[type="application/json"], pre, code, textarea',
        )
        .map((e) => e.text),
    document.body?.text ?? '',
  ]) {
    try {
      final decoded = jsonDecode(candidate.trim());
      if (decoded is Map &&
          decoded['entries'] is List &&
          decoded['app'] == null) {
        return jsonEncode(decoded);
      }
    } on FormatException {
      /* Try another data container. */
    }
  }
  const columns = {
    'name': 'name',
    'title': 'name',
    'anime': 'name',
    'manga': 'name',
    'status': 'status',
    'rating': 'rating',
    'score': 'rating',
    'started': 'started',
    'start date': 'started',
    'completed': 'completed',
    'finished': 'completed',
    'finish date': 'completed',
    'episodes': 'eps',
    'eps': 'eps',
    'episodes watched': 'eps',
    'chapters': 'ch',
    'ch': 'ch',
    'chapters read': 'ch',
    'volumes': 'vol',
    'vol': 'vol',
    'volumes read': 'vol',
    'times': 'times',
    'times watched': 'times',
    'times read': 'times',
  };
  for (final table in document.querySelectorAll('table')) {
    List<String?>? headers;
    final entries = <Map<String, dynamic>>[];
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children
          .where((e) => e.localName == 'th' || e.localName == 'td')
          .toList();
      if (headers == null) {
        final names = cells
            .map(
              (e) =>
                  columns[e.text.trim().toLowerCase().replaceAll(
                    RegExp(r'\s+'),
                    ' ',
                  )],
            )
            .toList();
        if (names.contains('name') &&
            names.contains('status') &&
            (names.contains('eps') || names.contains('ch'))) {
          headers = names;
        }
        continue;
      }
      if (cells.isEmpty || cells.every((e) => e.text.trim().isEmpty)) continue;
      if (cells.length != headers.length) {
        throw const FormatException(
          'An export table has incomplete rows. Choose the JSON export instead.',
        );
      }
      entries.add({
        for (var i = 0; i < headers.length; i++)
          if (headers[i] != null) headers[i]!: cells[i].text.trim(),
      });
    }
    if (headers != null && entries.isNotEmpty) {
      return jsonEncode({'entries': entries});
    }
  }
  throw const FormatException(
    'No Anime-Planet list data found in this HTML file. Choose your exported JSON file instead.',
  );
}
