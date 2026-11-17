import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/backup_type.dart';
import '../core/library.dart';
import '../core/file_export.dart';
import 'app_state.dart';
import 'format.dart';
import 'models/shelf_entry.dart';
import 'screens/edit_sheet.dart';
import 'screens/filter_sheet.dart';
import 'screens/settings_sheet.dart';
import 'screens/stats_sheet.dart';
import 'screens/year_review_sheet.dart';
import 'screens/import_sheet.dart';
import 'shelf_filter.dart';
import 'storage.dart';

class FilmLibraryController extends LibraryController {
  FilmLibraryController(this.state) : super(state);
  final AppState state;
  ShelfFilter _filter = ShelfFilter();
  String _search = '';
  @override
  CompanionMode get mode => CompanionMode.film;
  @override
  String get singular => 'film or series';
  @override
  IconData get icon => Icons.movie_outlined;
  @override
  int get totalCount => state.entries.length;
  @override
  bool get canTag => true;
  @override
  bool get locked => state.loadFailed;
  @override
  String? get error => state.loadFailed
      ? 'Your film library could not be read. Import a backup to recover it.'
      : state.saveError;
  @override
  bool get hasFilters => _filter.active;
  @override
  List<LibraryChoice> get shelves => const [
    LibraryChoice('watchlist', 'Watchlist'),
    LibraryChoice('seen', 'Seen'),
    LibraryChoice('bailed', 'Bailed'),
  ];
  @override
  List<LibraryChoice> get sorts => const [
    LibraryChoice('recent', 'Recent'),
    LibraryChoice('title', 'Title'),
    LibraryChoice('progress', 'Progress'),
    LibraryChoice('rating', 'Rating'),
    LibraryChoice('runtime', 'Runtime'),
    LibraryChoice('year', 'Year'),
  ];
  @override
  int count(String shelf) =>
      shelf == 'all' ? totalCount : state.countFor(shelf);
  Future<void> _edit(BuildContext context, [ShelfEntry? initial]) async {
    final entry = await showEditSheet(
      context,
      state: state,
      initial: initial,
      fullPage: true,
    );
    if (entry != null) {
      if (initial == null) {
        await state.add(entry);
      } else {
        await state.update(entry);
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
      description: 'Screen Companion JSON backups and legacy film arrays. JSON is the complete film and series backup; CSV is a report.',
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
        LibraryAction(
          'recovery',
          'Trash, recovery & automatic backups',
          Icons.restore,
          (context) => showSettingsSheet(context, state),
        ),
      ],
    ),
  );
  Future<void> _export(BuildContext context, bool csv) async {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await saveTextFile(
      fileName: 'screen-companion-$date.${csv ? "csv" : "json"}',
      content: csv ? ShelfStore.toCsv(state.entries) : state.exportJson(),
      mimeType: csv ? 'text/csv' : 'application/json',
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $saved')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Film backup',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        ),
      ],
    );
    if (file == null) return;
    if (await file.length() > ShelfStore.maxImportBytes) {
      throw const LibraryActionError(
        'That file exceeds the 10 MB backup limit.',
      );
    }
    final document = await ShelfStore.parseInBackground(
      utf8.decode(await file.readAsBytes()),
    );
    if (!document.valid) throw LibraryActionError(document.error!);
    if (context.mounted) await showImportSheet(context, state, document);
  }

  @override
  Future<void> detailedStats(BuildContext context) =>
      showStatsSheet(context, state);
  @override
  List<LibraryMetric> get metrics => [
    LibraryMetric('Titles', '$totalCount'),
    LibraryMetric(
      'Time watched',
      '${state.minutesWatched ~/ 60} h ${state.minutesWatched % 60} min',
    ),
    LibraryMetric('Episodes watched', '${state.episodesWatched}'),
    LibraryMetric('Viewings logged', '${state.viewingsLogged}'),
    LibraryMetric(
      'Time queued',
      '${state.minutesQueued ~/ 60} h ${state.minutesQueued % 60} min',
      '${state.unmeasuredQueued} queued titles have an unknown runtime or length.',
    ),
    ...shelves.map((shelf) => LibraryMetric(shelf.label, '${count(shelf.id)}')),
  ];
  @override
  List<LibraryAction> get tools => [
    LibraryAction('pick', 'Pick for me', Icons.shuffle, _pick),
    LibraryAction(
      'year-review',
      'Year in review',
      Icons.calendar_month_outlined,
      (context) => showYearReviewSheet(context, state),
    ),
  ];
  Future<void> _pick(BuildContext context) async {
    final choices = state
        .visible('watchlist', _search, filter: _filter)
        .where(
          (entry) =>
              entry.hasRuntime && (!entry.isSeries || entry.episodesLeft != 0),
        )
        .toList();
    if (choices.isEmpty) {
      throw const LibraryActionError('No measured titles fit these filters.');
    }
    final entry = choices[Random().nextInt(choices.length)];
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entry.title),
        content: Text(
          '${runtimeLong(entry.runtime)}${entry.isSeries ? "/episode · ${entry.nextEpisode}" : ""}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open title'),
          ),
        ],
      ),
    );
    if (open == true && context.mounted) await _edit(context, entry);
  }

  @override
  Future<void> filters(BuildContext context, LibraryDisplayQuery query) async {
    final next = await showFilterSheet(context, _filter, state.tags);
    if (next != null) {
      _filter = next;
      notifyListeners();
    }
  }

  @override
  void clearFilters() {
    _filter = ShelfFilter();
    notifyListeners();
  }

  @override
  Future<void> bulk(
    BuildContext context,
    Set<String> ids,
    String action,
  ) async {
    if (action == 'tag') {
      final tag = await requestLibraryTag(context);
      if (tag != null) await state.bulk(ids, tags: [tag]);
    } else {
      await state.bulk(
        ids,
        status: action == 'delete' ? null : action,
        delete: action == 'delete',
      );
    }
  }

  @override
  List<LibraryRowData> rows(LibraryDisplayQuery query) {
    _search = query.search;
    final search = query.search.trim().toLowerCase();
    final entries = state.entries
        .where(
          (entry) =>
              (query.shelf == 'all' || entry.status == query.shelf) &&
              _filter.matches(entry) &&
              [
                entry.title,
                entry.director,
                ...entry.tags,
              ].any((value) => value.toLowerCase().contains(search)),
        )
        .toList();
    double progress(ShelfEntry entry) => !entry.isSeries
        ? (entry.isSeen ? 1 : 0)
        : entry.episodes == null
        ? -1
        : entry.watched / entry.episodes!;
    entries.sort(
      (a, b) => switch (query.sort) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'rating' => b.rating.compareTo(a.rating),
        'year' => (b.year ?? 0).compareTo(a.year ?? 0),
        'runtime' => (a.runtime ?? 1000000).compareTo(b.runtime ?? 1000000),
        'progress' => progress(b).compareTo(progress(a)),
        _ => b.lastUpdated.compareTo(a.lastUpdated),
      },
    );
    return (query.descending ? entries.reversed : entries)
        .map(
          (entry) => LibraryRowData(
            id: entry.id,
            title: entry.title,
            coverUrl: entry.posterUrl,
            subtitle: [
              entry.director,
              if (entry.year != null) '${entry.year}',
              entry.isSeries ? 'Series' : 'Film',
            ].where((v) => v.isNotEmpty).join(' · '),
            progress: entry.isSeries
                ? '${entry.watched} / ${entry.episodes ?? "?"} episodes'
                : '${entry.runtime ?? "?"} min · ${entry.plays} ${entry.plays == 1 ? "viewing" : "viewings"}',
            fraction: entry.isSeries && entry.episodes == null
                ? null
                : progress(entry),
            rating: entry.rating.toDouble(),
            edit: (context) => _edit(context, entry),
            details: (context) => showLibraryDetails(
              context,
              title: entry.title,
              values: [
                LibraryMetric(
                  entry.isSeries ? 'Creator' : 'Director',
                  entry.director.isEmpty ? 'Not set' : entry.director,
                ),
                LibraryMetric(
                  'Runtime',
                  '${entry.runtime ?? "?"} ${entry.isSeries ? "min/episode" : "min"}',
                ),
                if (entry.isSeries)
                  LibraryMetric('Next episode', entry.nextEpisode),
                LibraryMetric(
                  'Notes',
                  entry.note.isEmpty ? 'No notes' : entry.note,
                ),
                LibraryMetric(
                  'Tags',
                  entry.tags.isEmpty ? 'No tags' : entry.tags.join(', '),
                ),
              ],
              history: entry.viewingsNewestFirst
                  .map(
                    (viewing) => LibraryMetric(
                      'Viewing',
                      watchedLabel(viewing.at, viewing.precision),
                      [
                        viewing.location,
                        viewing.company,
                      ].where((v) => v.isNotEmpty).join(' · '),
                    ),
                  )
                  .toList(),
            ),
            stepUnit: entry.isSeries ? 'ep' : '',
            stepName: 'episodes',
            decrease: entry.isSeries && entry.watched > 0
                ? (_) => state.advanceEpisode(entry, -1)
                : null,
            increase:
                entry.isSeries &&
                    (entry.episodes == null || entry.watched < entry.episodes!)
                ? (_) => state.advanceEpisode(entry, 1)
                : null,
            primary: entry.isSeries
                ? null
                : LibraryAction(
                    'watch',
                    entry.isSeen ? 'Watch again' : 'Mark seen',
                    Icons.check,
                    (_) => entry.isSeen
                        ? state.watchAgain(entry)
                        : state.markSeen(entry),
                  ),
            actions: [
              LibraryAction(
                'rating',
                'Rate title',
                Icons.star_border,
                (context) => showLibraryRating(
                  context,
                  entry.rating,
                  (rating) => state.setRating(entry, rating),
                ),
              ),
              LibraryAction(
                'again',
                'Watch again',
                Icons.replay,
                (_) => state.watchAgain(entry),
              ),
              if (entry.plays > 1)
                LibraryAction(
                  'undo-viewing',
                  'Undo last viewing',
                  Icons.undo,
                  (_) => state.undoPlay(entry),
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
                  (_) => state.setStatus(entry, shelf.id),
                ),
              ),
              LibraryAction('delete', 'Delete title', Icons.delete_outline, (
                context,
              ) async {
                await state.remove(entry.id);
                final removed = state.trash
                    .where((row) => row.entry.id == entry.id)
                    .last;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${entry.title} moved to trash.'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () => state.restoreTrash(removed),
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
