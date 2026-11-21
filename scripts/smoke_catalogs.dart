import 'package:companion/core/title_lookup.dart';

/// Optional live checks: dart run scripts/smoke_catalogs.dart
Future<void> main() async {
  for (final (catalog, query) in [
    (TitleCatalog.film, 'Arrival'),
    (TitleCatalog.series, 'Dark'),
    (TitleCatalog.manga, 'One Piece'),
    (TitleCatalog.anime, 'Frieren'),
  ]) {
    final service = TitleLookup();
    final results = await service.search(catalog, query);
    if (results.isEmpty) {
      throw StateError('No ${catalog.name} results for $query');
    }
    final selected = await service.details(results.first);
    if (selected.title.isEmpty || selected.sourceUrl.isEmpty) {
      throw StateError('Incomplete ${catalog.name} details');
    }
    // Public catalog data only, never personal library data or credentials.
    // ignore: avoid_print
    print(
      'PASS ${catalog.name}: ${selected.title} (${selected.year ?? 'unknown year'}), ${selected.sourceName}',
    );
  }
}
