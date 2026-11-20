import 'package:flutter/material.dart';

import '../core/backup_type.dart';
import '../core/library.dart';
import 'models/book.dart';
import 'screens/add_edit_book_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/library_model.dart';
import 'services/export_service.dart';
import 'services/library_query.dart';
import 'services/theme_notifier.dart';
import 'widgets/library_filters.dart';
import 'widgets/set_page_dialog.dart';

class BookLibraryController extends LibraryController {
  BookLibraryController(this.library, this.settings) : super(library);
  final LibraryModel library;
  final ThemeNotifier settings;
  LibraryQuery _filters = LibraryQuery();
  @override
  CompanionMode get mode => CompanionMode.books;
  @override
  String get singular => 'book';
  @override
  IconData get icon => Icons.menu_book_outlined;
  @override
  String? get error => library.loadFailed
      ? 'Your book library could not be read. Import a backup to recover it.'
      : library.saveError;
  @override
  bool get locked => library.loadFailed;
  @override
  bool get saving => library.saving;
  @override
  int get totalCount => library.books.length;
  @override
  bool get hasFilters => _filters.hasFilters;
  @override
  bool get canTag => true;
  @override
  List<LibraryChoice> get shelves => [
    for (final status in [
      BookStatus.reading,
      BookStatus.toRead,
      BookStatus.read,
      BookStatus.onHold,
      BookStatus.dropped,
    ])
      LibraryChoice(status.name, status.label),
  ];
  @override
  List<LibraryChoice> get sorts => const [
    LibraryChoice('recent', 'Recent'),
    LibraryChoice('title', 'Title'),
    LibraryChoice('author', 'Author'),
    LibraryChoice('progress', 'Progress'),
    LibraryChoice('rating', 'Rating'),
    LibraryChoice('added', 'Date added'),
    LibraryChoice('read', 'Last read'),
  ];
  @override
  int count(String shelf) => shelf == 'all'
      ? totalCount
      : library.books.where((book) => book.status.name == shelf).length;

  Future<void> _check(Future<bool> action) async {
    if (!await action) {
      throw LibraryActionError(
        library.saveError ?? 'Your books could not be saved.',
      );
    }
  }

  Future<void> _edit(BuildContext context, Book book) =>
      openLibraryPage(context, AddEditBookScreen(book: book));
  @override
  Future<void> add(BuildContext context) =>
      openLibraryPage(context, const AddEditBookScreen());
  @override
  Future<void> importExport(BuildContext context) => openLibraryPage(
    context,
    LibraryDataPage(
      controller: this,
      description: 'Book backups stay in Books. Use .bcbackup to include covers. Import .bcbackup, book JSON or Goodreads CSV.',
      actions: [
        LibraryAction(
          'import',
          'Import backup',
          Icons.file_upload_outlined,
          (context) => openLibraryPage(
            context,
            const BackupScreen(startWithImport: true),
          ),
        ),
        LibraryAction(
          'export',
          'Export backup',
          Icons.file_download_outlined,
          (context) => _export(context, 'bcbackup'),
        ),
        LibraryAction(
          'csv',
          'Export CSV',
          Icons.table_view_outlined,
          (context) => _export(context, 'csv'),
        ),
        LibraryAction(
          'json',
          'Export JSON',
          Icons.data_object,
          (context) => _export(context, 'json'),
        ),
        LibraryAction(
          'html',
          'Export HTML',
          Icons.print_outlined,
          (context) => _export(context, 'html'),
        ),
        LibraryAction(
          'pdf',
          'Export PDF',
          Icons.picture_as_pdf_outlined,
          (context) => _export(context, 'pdf'),
        ),
        LibraryAction(
          'recovery',
          'Snapshots & recovery',
          Icons.restore,
          (context) => openLibraryPage(context, const BackupScreen()),
        ),
      ],
    ),
  );
  Future<void> _export(BuildContext context, String format) async {
    final saved = await ExportService(library.storage)
        .export(library.allBooks, format);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $saved')));
    }
  }

  @override
  Future<void> detailedStats(BuildContext context) =>
      openLibraryPage(context, const StatsScreen());
  @override
  List<LibraryMetric> get metrics => [
    LibraryMetric('Titles', '$totalCount'),
    LibraryMetric('Completed reads', '${library.totalSessionsCompleted}'),
    LibraryMetric(
      'Pages read',
      '${library.totalPagesRead}',
      'Audiobook time stays separate from pages.',
    ),
    LibraryMetric('Rereads', '${library.totalRereads}'),
    LibraryMetric(
      'Average rating',
      library.averageRating?.toStringAsFixed(1) ?? 'Unrated',
    ),
    ...shelves.map((shelf) => LibraryMetric(shelf.label, '${count(shelf.id)}')),
  ];
  @override
  List<LibraryAction> get tools => [
    LibraryAction(
      'preferences',
      'Book preferences & recovery',
      Icons.settings_outlined,
      (context) => openLibraryPage(context, const SettingsScreen()),
    ),
  ];
  @override
  Future<void> filters(BuildContext context, LibraryDisplayQuery query) async {
    final next = await showModalBottomSheet<LibraryQuery>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LibraryFilters(
        query: _filters,
        books: library.books,
        shelf: query.shelf == 'all'
            ? BookStatus.reading
            : BookStatus.values.byName(query.shelf),
      ),
    );
    if (next != null) {
      _filters = next;
      notifyListeners();
    }
  }

  @override
  void clearFilters() {
    _filters.clearFilters();
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
      if (tag != null) await _check(library.bulk(ids, tag: tag));
      return;
    }
    await _check(
      library.bulk(
        ids,
        deleted: action == 'delete',
        status: action == 'delete' ? null : BookStatus.values.byName(action),
      ),
    );
  }

  @override
  List<LibraryRowData> rows(LibraryDisplayQuery query) {
    final filter = (query.ignoreFilters ? LibraryQuery() : _filters.copy())
      ..search = query.search
      ..sort = switch (query.sort) {
        'title' => LibrarySort.title,
        'author' => LibrarySort.author,
        'progress' => LibrarySort.progress,
        'rating' => LibrarySort.rating,
        'added' => LibrarySort.dateAdded,
        'read' => LibrarySort.lastRead,
        _ => LibrarySort.lastEdited,
      };
    filter.descending = filter.sort.defaultDescending != query.descending;
    final entries = filter.apply(
      library.books
          .where(
            (book) => query.shelf == 'all' || book.status.name == query.shelf,
          )
          .toList(),
    );
    return entries.map((book) {
      final open = book.openSession;
      final total = book.progressTotal;
      final position =
          open?.currentPage ??
          (book.status == BookStatus.read ? total ?? 0 : 0);
      final unit = book.isAudio ? 'hours' : 'pages';
      return LibraryRowData(
        id: book.id,
        title: book.title,
        subtitle: [
          book.author,
          book.format.label,
          book.status.label,
        ].where((v) => v.isNotEmpty).join(' · '),
        coverPath: book.coverImagePath,
        fraction: total == null ? null : book.progress,
        rating: book.averageRating,
        progress:
            '${book.progressLabel(position)} / ${total == null ? "?" : book.progressLabel(total)} $unit',
        edit: (context) => _edit(context, book),
        details: (context) => showLibraryDetails(
          context,
          title: book.title,
          values: [
            LibraryMetric(
              'Author',
              book.author.isEmpty ? 'Not set' : book.author,
            ),
            LibraryMetric('Format', book.format.label),
            LibraryMetric('Reading shelf', book.status.label),
            LibraryMetric(
              'Notes',
              book.notes.isEmpty ? 'No notes' : book.notes,
            ),
            LibraryMetric('Completed reads', '${book.timesRead}'),
          ],
          history: book.sessions.reversed
              .map(
                (session) => LibraryMetric(
                  session.isOpen ? 'Current read' : 'Completed read',
                  '${session.currentPage} ${session.format == BookFormat.audiobook ? "minutes" : "pages"}',
                  session.rating == null ? 'Unrated' : '${session.rating}/5',
                ),
              )
              .toList(),
          extra: LibraryAction(
            'reading',
            'Reading sessions & quotes',
            Icons.auto_stories_outlined,
            (context) =>
                openLibraryPage(context, BookDetailScreen(bookId: book.id)),
          ),
        ),
        primary: LibraryAction(
          'progress',
          open == null
              ? (book.status == BookStatus.read
                    ? 'Read again'
                    : 'Start reading')
              : 'Set progress',
          Icons.edit_outlined,
          (context) => open == null
              ? _check(
                  library.startReading(
                    book,
                    precision: settings.defaultPrecision,
                  ),
                )
              : showSetPageDialog(context, book),
        ),
        actions: [
          LibraryAction(
            'reading',
            'Reading sessions & quotes',
            Icons.auto_stories_outlined,
            (context) =>
                openLibraryPage(context, BookDetailScreen(bookId: book.id)),
          ),
          ...shelves.map(
            (shelf) => LibraryAction(
              shelf.id,
              'Move to ${shelf.label}',
              Icons.drive_file_move_outline,
              (_) => _check(
                library.setStatus(book, BookStatus.values.byName(shelf.id)),
              ),
            ),
          ),
          LibraryAction('delete', 'Delete title', Icons.delete_outline, (
            context,
          ) async {
            await _check(library.deleteBook(book.id));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${book.title} moved to trash.'),
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () => library.restoreBook(book.id),
                  ),
                ),
              );
            }
          }),
        ],
      );
    }).toList();
  }
}
