import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/backup_type.dart';
import '../core/library.dart';
import '../core/file_export.dart';
import 'app_state.dart';
import 'csv_export.dart';
import 'format.dart';
import 'import_flow.dart';
import 'models/manga_entry.dart';
import 'screens/edit_sheet.dart';
import 'screens/stats_sheet.dart';

class MangaLibraryController extends LibraryController {
  MangaLibraryController(this.state) : super(state);
  final AppState state;
  int _minimumRating = 0;
  @override
  CompanionMode get mode => CompanionMode.manga;
  @override
  String get singular => 'manga';
  @override
  IconData get icon => Icons.auto_stories_outlined;
  @override
  int get totalCount => state.entries.length;
  @override
  bool get locked => state.loadFailed;
  @override
  String? get error => state.loadFailed
      ? 'Your manga library could not be read. Import a backup to recover it.'
      : null;
  @override
  bool get hasFilters => _minimumRating > 0;
  @override
  List<LibraryChoice> get shelves => [
    for (final status in ShelfStatus.values)
      LibraryChoice(status.json, status.label),
  ];
  @override
  List<LibraryChoice> get sorts => const [
    LibraryChoice('recent', 'Recent'),
    LibraryChoice('title', 'Title'),
    LibraryChoice('progress', 'Progress'),
    LibraryChoice('rating', 'Rating'),
  ];
  @override
  int count(String shelf) =>
      shelf == 'all' ? totalCount : state.countFor(ShelfStatus.fromJson(shelf));
  Future<void> _edit(BuildContext context, [MangaEntry? entry]) async {
    final updated = await showEditSheet(
      context,
      state: state,
      initial: entry,
      fullPage: true,
    );
    if (updated != null) {
      if (entry == null) {
        await state.add(updated);
      } else {
        await state.update(updated);
      }
    }
  }

  @override
  Future<void> add(BuildContext context) => _edit(context);
  @override
  Future<void> importExport(BuildContext context) => openLibraryPage(
    context,
    LibraryDataPage(
      controller: this,
      description: 'Manga JSON, MyAnimeList manga XML, Anime-Planet manga JSON/HTML and Mihon backups. JSON is the complete manga backup.',
      actions: [
        LibraryAction('import', 'Import backup', Icons.file_upload_outlined, (
          context,
        ) async {
          final outcome = await pickAndImport(context, state);
          if (outcome != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(outcome.message),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => state.replaceAll(outcome.before),
                ),
              ),
            );
          }
        }),
        LibraryAction(
          'export',
          'Export backup',
          Icons.file_download_outlined,
          (context) => _export(context, false),
        ),
        LibraryAction(
          'csv',
          'Export CSV',
          Icons.table_view_outlined,
          (context) => _export(context, true),
        ),
      ],
    ),
  );
  Future<void> _export(BuildContext context, bool csv) async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await saveTextFile(
      fileName: 'manga-companion-$date.${csv ? "csv" : "json"}',
      content: csv ? toCsv(state.entries) : state.exportJson(),
      mimeType: csv ? 'text/csv' : 'application/json',
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $saved')));
    }
  }

  @override
  Future<void> detailedStats(BuildContext context) =>
      showStatsSheet(context, state);
  @override
  List<LibraryMetric> get metrics => [
    LibraryMetric('Titles', '$totalCount'),
    LibraryMetric('Chapters read', '${state.totalChaptersRead}'),
    LibraryMetric(
      'Average rating',
      state.averageRating == 0
          ? 'Unrated'
          : state.averageRating.toStringAsFixed(1),
    ),
    ...shelves.map((shelf) => LibraryMetric(shelf.label, '${count(shelf.id)}')),
  ];
  @override
  Future<void> filters(BuildContext context, LibraryDisplayQuery query) async {
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Minimum rating'),
        children: [
          for (var rating = 0; rating <= 5; rating++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, rating),
              child: Text(rating == 0 ? 'Any rating' : '$rating stars or more'),
            ),
        ],
      ),
    );
    if (value != null) {
      _minimumRating = value;
      notifyListeners();
    }
  }

  @override
  void clearFilters() {
    _minimumRating = 0;
    notifyListeners();
  }

  @override
  Future<void> bulk(
    BuildContext context,
    Set<String> ids,
    String action,
  ) async {
    final before = state.snapshot();
    if (action == 'delete') {
      await state.removeMany(ids);
    } else {
      await state.setStatusMany(ids, ShelfStatus.fromJson(action));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ids.length} manga updated.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => state.replaceAll(before),
          ),
        ),
      );
    }
  }

  @override
  List<LibraryRowData> rows(LibraryDisplayQuery query) {
    final entries = state.entries
        .where(
          (entry) =>
              (query.shelf == 'all' || entry.status.json == query.shelf) &&
              (query.ignoreFilters || entry.rating >= _minimumRating) &&
              entry.title.toLowerCase().contains(
                query.search.trim().toLowerCase(),
              ),
        )
        .toList();
    entries.sort(
      (a, b) => switch (query.sort) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'progress' =>
          (b.totalChapters == null ? -1.0 : b.currentChapter / b.totalChapters!)
              .compareTo(
                a.totalChapters == null
                    ? -1.0
                    : a.currentChapter / a.totalChapters!,
              ),
        'rating' => b.rating.compareTo(a.rating),
        _ => b.lastUpdated.compareTo(a.lastUpdated),
      },
    );
    return (query.descending ? entries.reversed : entries)
        .map(
          (entry) => LibraryRowData(
            id: entry.id,
            title: entry.title,
            subtitle: entry.status.label,
            updatedLabel: 'Last edited: ${editedLabel(entry.lastUpdated)}',
            coverUrl: entry.coverUrl,
            progress:
                '${entry.currentChapter} / ${entry.totalChapters ?? "?"} chapters',
            fraction: entry.totalChapters == null
                ? null
                : entry.currentChapter / entry.totalChapters!,
            rating: entry.rating.toDouble(),
            edit: (context) => _edit(context, entry),
            details: (context) => showLibraryDetails(
              context,
              title: entry.title,
              values: [
                LibraryMetric('Shelf', entry.status.label),
                LibraryMetric('Last edited', editedLabel(entry.lastUpdated)),
                LibraryMetric(
                  'Chapters',
                  '${entry.currentChapter} / ${entry.totalChapters ?? "?"}',
                ),
                LibraryMetric('Rereads', '${entry.rereads}'),
                LibraryMetric('Started', shortDate(entry.startedAt)),
                LibraryMetric('Finished', shortDate(entry.finishedAt)),
              ],
              history: entry.history.reversed
                  .map(
                    (event) => LibraryMetric(
                      '${event.from} → ${event.to} chapters',
                      shortDate(event.at),
                    ),
                  )
                  .toList(),
            ),
            stepUnit: 'ch',
            stepName: 'chapters',
            decrease: entry.currentChapter > 0
                ? (_) async {
                    await state.bumpChapter(entry.id, -1);
                  }
                : null,
            increase:
                entry.totalChapters == null ||
                    entry.currentChapter < entry.totalChapters!
                ? (_) async {
                    await state.bumpChapter(entry.id, 1);
                  }
                : null,
            actions: [
              LibraryAction(
                'rating',
                'Rate title',
                Icons.star_border,
                (context) => showLibraryRating(
                  context,
                  entry.rating,
                  (rating) => state.setRating(entry.id, rating),
                ),
              ),
              LibraryAction('reread', 'Start reread', Icons.replay, (_) async {
                await state.startReread(entry.id);
              }),
              if (entry.readUrl.isNotEmpty)
                LibraryAction('link', 'Open reading link', Icons.open_in_new, (
                  _,
                ) async {
                  final uri = Uri.tryParse(entry.readUrl);
                  if (uri == null ||
                      !['http', 'https'].contains(uri.scheme) ||
                      !await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                    throw const LibraryActionError(
                      'Could not open this reading link. Check it in Edit title.',
                    );
                  }
                }),
              ...shelves.map(
                (shelf) => LibraryAction(
                  shelf.id,
                  'Move to ${shelf.label}',
                  Icons.drive_file_move_outline,
                  (_) async {
                    await state.setStatus(
                      entry.id,
                      ShelfStatus.fromJson(shelf.id),
                    );
                  },
                ),
              ),
              LibraryAction('delete', 'Delete title', Icons.delete_outline, (
                context,
              ) async {
                final removed = await state.remove(entry.id);
                if (removed != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${entry.title} deleted.'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () => state.restoreRemoved(removed),
                      ),
                    ),
                  );
                }
              }),
            ],
          ),
        )
        .toList();
  }
}
