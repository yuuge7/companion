import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/backup_type.dart';
import '../core/file_export.dart';
import '../core/library.dart';
import 'anime_backup.dart';
import 'anime_entry.dart';
import 'anime_library.dart';
import 'anime_screen.dart';

class AnimeLibraryController extends LibraryController {
  AnimeLibraryController(this.library) : super(library);
  final AnimeLibrary library;
  AnimeFormat? _format;
  @override
  CompanionMode get mode => CompanionMode.anime;
  @override
  String get singular => 'anime';
  @override
  IconData get icon => Icons.live_tv_outlined;
  @override
  int get totalCount => library.entries.length;
  @override
  bool get saving => library.busy;
  @override
  bool get locked => library.loadFailed;
  @override
  String? get error => library.error;
  @override
  bool get hasFilters => _format != null;
  @override
  bool get canTag => true;
  @override
  List<LibraryChoice> get shelves => [
    for (final status in AnimeStatus.values)
      LibraryChoice(status.name, status.label),
  ];
  @override
  List<LibraryChoice> get sorts => const [
    LibraryChoice('recent', 'Recent'),
    LibraryChoice('title', 'Title'),
    LibraryChoice('progress', 'Progress'),
    LibraryChoice('rating', 'Rating'),
  ];
  @override
  int count(String shelf) => shelf == 'all'
      ? totalCount
      : library.entries.where((entry) => entry.status.name == shelf).length;
  Future<void> _edit(BuildContext context, [AnimeEntry? initial]) async {
    final entry = await openLibraryPage<AnimeEntry>(
      context,
      AnimeEditor(initial: initial),
    );
    if (entry == null || !context.mounted) return;
    if (library.entries.any(
      (old) => old.id != entry.id && old.identity == entry.identity,
    )) {
      final allow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This title is already in your library'),
          content: Text('Add another entry for ${entry.title}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add anyway'),
            ),
          ],
        ),
      );
      if (allow != true) return;
    }
    await library.save(entry);
  }

  @override
  Future<void> add(BuildContext context) => _edit(context);
  @override
  Future<void> filters(BuildContext context, LibraryDisplayQuery query) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Anime format'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('All formats'),
          ),
          ...AnimeFormat.values.map(
            (format) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, format.name),
              child: Text(format.label),
            ),
          ),
        ],
      ),
    );
    if (choice != null) {
      _format = choice == 'all' ? null : AnimeFormat.values.byName(choice);
      notifyListeners();
    }
  }

  @override
  void clearFilters() {
    _format = null;
    notifyListeners();
  }

  @override
  List<LibraryMetric> get metrics {
    final measured = library.entries
        .where((entry) => entry.minutesSpent != null)
        .toList();
    final minutes = measured.fold(0, (sum, entry) => sum + entry.minutesSpent!);
    return [
      LibraryMetric('Titles', '$totalCount'),
      LibraryMetric(
        'Episodes watched',
        '${library.entries.fold(0, (sum, entry) => sum + (entry.isMovie ? 0 : entry.currentEpisode))}',
      ),
      LibraryMetric(
        'Measured time watched',
        '${minutes ~/ 60} h ${minutes % 60} min',
        '${totalCount - measured.length} titles have an unknown runtime. Current viewing progress only.',
      ),
      LibraryMetric(
        'Rewatches',
        '${library.entries.fold(0, (sum, entry) => sum + entry.rewatches)}',
      ),
      ...shelves.map(
        (shelf) => LibraryMetric(shelf.label, '${count(shelf.id)}'),
      ),
    ];
  }

  @override
  Future<void> detailedStats(BuildContext context) => showLibraryDetails(
    context,
    title: 'Anime by format',
    values: [
      for (final format in AnimeFormat.values)
        LibraryMetric(
          format.label,
          '${library.entries.where((entry) => entry.animeFormat == format).length} titles',
        ),
    ],
  );
  @override
  Future<void> bulk(
    BuildContext context,
    Set<String> ids,
    String action,
  ) async {
    final tag = action == 'tag' ? await requestLibraryTag(context) : null;
    if (action == 'tag' && tag == null) return;
    for (final entry
        in library.entries.where((entry) => ids.contains(entry.id)).toList()) {
      if (action == 'delete') {
        await library.remove(entry.id);
      } else {
        final json = entry.toJson()
          ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        if (action == 'tag') {
          json['tags'] = {...entry.tags, tag!}.toList();
        } else {
          json['status'] = action;
        }
        await library.save(AnimeEntry.fromJson(json));
      }
    }
  }

  Future<void> _export(BuildContext context, bool csv) async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await saveTextFile(
      fileName: 'anime-companion-$date.${csv ? "csv" : "json"}',
      content: csv
          ? AnimeBackup.csv(library.entries)
          : AnimeBackup.encode(library.entries),
      mimeType: csv ? 'text/csv' : 'application/json',
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $saved')));
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Anime backup',
            extensions: ['json', 'xml', 'gz'],
            mimeTypes: [
              'application/json',
              'text/xml',
              'application/xml',
              'application/gzip',
            ],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > AnimeBackup.maxBytes) {
        throw const FormatException('Anime imports are limited to 10 MB.');
      }
      final entries = await compute(
        AnimeBackup.parse,
        await file.readAsBytes(),
      );
      if (!context.mounted) return;
      final replace = await openLibraryPage<bool>(
        context,
        AnimeImportPreview(incoming: entries, existing: library.entries),
      );
      if (replace != null) {
        await library.importEntries(entries, replace: replace);
      }
    } on FormatException catch (error) {
      throw LibraryActionError(error.message);
    }
  }

  @override
  Future<void> importExport(BuildContext context) => openLibraryPage(
    context,
    LibraryDataPage(
      controller: this,
      actions: [
        LibraryAction(
          'import',
          'Import backup',
          Icons.file_upload_outlined,
          _import,
        ),
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
      description: 'Anime Companion JSON, Anime-Planet anime JSON or MyAnimeList anime XML, including gzip. JSON is the complete anime backup.',
    ),
  );
  @override
  List<LibraryAction> get tools => [
    LibraryAction(
      'trash',
      'Trash & recovery',
      Icons.restore_from_trash_outlined,
      (context) => openLibraryPage(
        context,
        ListenableBuilder(
          listenable: library,
          builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('Anime trash & recovery')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (library.hasSnapshot)
                  OutlinedButton.icon(
                    onPressed: library.busy ? null : library.restoreSnapshot,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore pre-import library'),
                  ),
                if (library.trash.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No deleted titles.'),
                  ),
                ...library.trash.map(
                  (entry) => ListTile(
                    title: Text(entry.title),
                    subtitle: Text(entry.progressLabel),
                    trailing: TextButton(
                      onPressed: library.busy
                          ? null
                          : () => library.restore(entry.id),
                      child: const Text('Restore'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ];
  @override
  List<LibraryRowData> rows(LibraryDisplayQuery query) {
    final search = query.search.trim().toLowerCase();
    final entries = library.entries
        .where(
          (entry) =>
              (query.shelf == 'all' || entry.status.name == query.shelf) &&
              (_format == null || entry.animeFormat == _format) &&
              [
                entry.title,
                entry.studio,
                ...entry.tags,
              ].any((value) => value.toLowerCase().contains(search)),
        )
        .toList();
    entries.sort(
      (a, b) => switch (query.sort) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'rating' => b.rating.compareTo(a.rating),
        'progress' => (b.progress ?? -1).compareTo(a.progress ?? -1),
        _ => b.updatedAt.compareTo(a.updatedAt),
      },
    );
    return (query.descending ? entries.reversed : entries)
        .map(
          (entry) => LibraryRowData(
            id: entry.id,
            title: entry.title,
            coverUrl: entry.posterUrl,
            subtitle: [
              entry.studio,
              if (entry.year != null) '${entry.year}',
              entry.animeFormat.label,
              entry.season,
            ].where((value) => value.isNotEmpty).join(' · '),
            progress: entry.isMovie
                ? '${entry.watchedMinutes} / ${entry.episodeMinutes ?? "?"} min'
                : '${entry.currentEpisode} / ${entry.totalEpisodes ?? "?"} episodes',
            fraction: entry.progress,
            rating: entry.rating.toDouble(),
            edit: (context) => _edit(context, entry),
            details: (context) => showLibraryDetails(
              context,
              title: entry.title,
              values: [
                LibraryMetric('Format', entry.animeFormat.label),
                LibraryMetric('Shelf', entry.status.label),
                LibraryMetric(
                  'Studio',
                  entry.studio.isEmpty ? 'Not set' : entry.studio,
                ),
                LibraryMetric(
                  'Notes',
                  entry.note.isEmpty ? 'No notes' : entry.note,
                ),
                LibraryMetric(
                  'Started',
                  entry.startedDate.isEmpty ? 'Unknown' : entry.startedDate,
                ),
                LibraryMetric(
                  'Finished',
                  entry.finishedDate.isEmpty ? 'Unknown' : entry.finishedDate,
                ),
                LibraryMetric('Rewatches', '${entry.rewatches}'),
              ],
              history: entry.history.reversed
                  .map(
                    (event) => LibraryMetric(
                      '${event["from"]} → ${event["to"]} ${event["unit"]}',
                      DateTime.fromMillisecondsSinceEpoch(event['at'])
                          .toLocal()
                          .toString()
                          .substring(0, 16),
                    ),
                  )
                  .toList(),
            ),
            stepUnit: entry.isMovie ? 'min' : 'ep',
            stepName: entry.isMovie ? 'minutes' : 'episodes',
            decrease: entry.position > 0
                ? (_) => library.save(entry.withProgress(entry.position - 1))
                : null,
            increase: entry.total == null || entry.position < entry.total!
                ? (_) => library.save(entry.withProgress(entry.position + 1))
                : null,
            actions: [
              LibraryAction(
                'rating',
                'Rate title',
                Icons.star_border,
                (context) => showLibraryRating(
                  context,
                  entry.rating,
                  (rating) => library.save(
                    AnimeEntry.fromJson(
                      entry.toJson()
                        ..['rating'] = rating
                        ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch,
                    ),
                  ),
                ),
              ),
              LibraryAction(
                'rewatch',
                'Start rewatch',
                Icons.replay,
                (_) => library.save(entry.rewatch()),
              ),
              if (entry.watchUrl.isNotEmpty)
                LibraryAction('link', 'Open watch link', Icons.open_in_new, (
                  _,
                ) async {
                  final uri = Uri.tryParse(entry.watchUrl);
                  if (uri == null ||
                      !['http', 'https'].contains(uri.scheme) ||
                      !await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                    throw const LibraryActionError(
                      'Could not open this watch link. Check it in Edit title.',
                    );
                  }
                }),
              ...shelves.map(
                (shelf) => LibraryAction(
                  shelf.id,
                  'Move to ${shelf.label}',
                  Icons.drive_file_move_outline,
                  (_) => library.save(
                    AnimeEntry.fromJson(
                      entry.toJson()
                        ..['status'] = shelf.id
                        ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch,
                    ),
                  ),
                ),
              ),
              LibraryAction('delete', 'Delete title', Icons.delete_outline, (
                context,
              ) async {
                await library.remove(entry.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${entry.title} moved to trash.'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () => library.restore(entry.id),
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
