enum CompanionMode {
  books('Books', 'Pages, audio and reading sessions'),
  manga('Manga', 'Chapters and reading history'),
  film('Film', 'Movies, series and viewing history'),
  anime('Anime', 'Episodes, seasons and anime films');

  const CompanionMode(this.label, this.description);
  final String label;
  final String description;
}

/// Legacy arrays remain supported, but recognizable foreign rows are refused
/// before a permissive legacy model can fill in its missing fields.
void requireBackupType(Object? decoded, CompanionMode expected) {
  if (decoded is Map) {
    final app = decoded['app'];
    final actual = switch (app) {
      'book_companion' => CompanionMode.books,
      'Manga Companion' => CompanionMode.manga,
      'Screen Companion' => CompanionMode.film,
      'Anime Companion' => CompanionMode.anime,
      _ => null,
    };
    if (actual != null && actual != expected) {
      throw FormatException(
        'This is a ${actual.label} backup. Open ${actual.label} to import it.',
      );
    }
  }
  final rows = decoded is List
      ? decoded
      : decoded is Map
      ? decoded['entries'] ?? decoded['books']
      : null;
  if (rows is! List) return;
  for (final row in rows.whereType<Map>()) {
    final actual =
        row.containsKey('currentChapter') || row.containsKey('totalChapters')
        ? CompanionMode.manga
        : row.containsKey('totalPages') ||
              row.containsKey('sessions') ||
              row.containsKey('author')
        ? CompanionMode.books
        : row.containsKey('animeFormat') || row.containsKey('currentEpisode')
        ? CompanionMode.anime
        : row.containsKey('kind') ||
              row.containsKey('runtime') ||
              row.containsKey('viewings')
        ? CompanionMode.film
        : null;
    if (actual != null && actual != expected) {
      throw FormatException(
        'This file contains ${actual.label} entries. Import each type in its own section.',
      );
    }
  }
}
