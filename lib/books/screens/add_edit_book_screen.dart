import '../../core/physical_collection.dart';
import '../../core/widgets/collection_fields.dart';
import '../services/book_lookup.dart';
import 'book_lookup_screen.dart';

import 'dart:io';

import '../../core/library.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/reading_session.dart';
import '../services/library_model.dart';
import '../services/theme_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/ledger.dart';
import '../widgets/read_dates.dart';
import '../widgets/read_format_fields.dart';
import 'cover_crop_screen.dart';

class AddEditBookScreen extends StatefulWidget {
  const AddEditBookScreen({super.key, this.book, this.lookup});
  final BookLookup? lookup;
  final Book? book;
  @override
  State<AddEditBookScreen> createState() => _AddEditBookScreenState();
}

class _AddEditBookScreenState extends State<AddEditBookScreen> {
  final _form = GlobalKey<FormState>();
  late final _lookup = widget.lookup ?? BookLookup();
  final _fields = <String, TextEditingController>{};
  late BookStatus _status;
  late BookFormat _format;
  late DatePrecision _precision;
  late DateTime _start, _end;
  int? _rating;
  String? _cover, _error;
  bool _saving = false;
  late PhysicalCollection _collection;
  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _collection = b?.collection ?? const PhysicalCollection();
    final values = <String, String>{
      'Title': b?.title ?? '',
      'Author': b?.author ?? '',
      'Total pages': b?.totalPages?.toString() ?? '',
      'Subtitle': b?.subtitle ?? '',
      'ISBN': b?.isbn ?? '',
      'Publisher': b?.publisher ?? '',
      'Publication year': b?.year?.toString() ?? '',
      'Language': b?.language ?? '',
      'Series': b?.series ?? '',
      'Series number': b?.seriesNumber ?? '',
      'Tags / genres': b?.tags.join(', ') ?? '',
      'Personal notes': b?.notes ?? '',
      'Why I dropped it': b?.dropReason ?? '',
      'Audio duration (h:mm)': b?.totalMinutes == null
          ? ''
          : formatReadLength(BookFormat.audiobook, b!.totalMinutes),
    };
    for (final e in values.entries) {
      _fields[e.key] = TextEditingController(text: e.value);
    }
    _status = b?.status ?? BookStatus.toRead;
    _format = b?.format ?? BookFormat.paperback;
    final session = b?.openSession ?? b?.sessions.lastOrNull;
    _precision =
        session?.precision ?? context.read<ThemeNotifier>().defaultPrecision;
    _start = session?.startDate ?? DateUtils.dateOnly(DateTime.now());
    _end = session?.endDate ?? DateUtils.dateOnly(DateTime.now());
    _rating = session?.rating;
    _cover = b?.coverImagePath;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String value(String name) => _fields[name]!.text.trim();
  int? minutes(String text) {
    final match = RegExp(r'^(\d+):([0-5]\d)$').firstMatch(text);
    return match == null
        ? null
        : int.parse(match[1]!) * 60 + int.parse(match[2]!);
  }

  Widget field(
    String name, {
    bool required = false,
    bool number = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey('field-$name'),
      controller: _fields[name],
      maxLines: lines,
      textCapitalization: number
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      keyboardType: number
          ? TextInputType.number
          : (lines > 1 ? TextInputType.multiline : TextInputType.text),
      decoration: InputDecoration(labelText: name),
      validator: (text) {
        final v = text?.trim() ?? '';
        if (required && v.isEmpty) return 'A title is required.';
        if (v.isEmpty) return null;
        if (number && (int.tryParse(v) == null || int.parse(v) <= 0)) {
          return 'Enter a positive whole number.';
        }
        if (name == 'Publication year' && int.parse(v) > 9999) {
          return 'Enter a valid year.';
        }
        if (name == 'Audio duration (h:mm)' &&
            (minutes(v) == null || minutes(v) == 0)) {
          return 'Use hours:minutes, for example 12:30.';
        }
        return null;
      },
    ),
  );
  Future<void> _findBook() async {
    final result = await Navigator.of(context).push<BookMetadata>(
      MaterialPageRoute(builder: (_) => BookLookupScreen(lookup: _lookup)),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    String? cover;
    String? warning;
    try {
      final bytes = await _lookup.cover(result.coverUrl);
      if (!mounted) return;
      if (bytes != null) {
        cover = await context.read<LibraryModel>().storage.storeCover(bytes);
      } else if (result.coverUrl.isNotEmpty) {
        warning = 'Details filled. Cover could not be downloaded; add one from Gallery.';
      }
    } catch (_) {
      warning =
          'Details filled. Cover could not be saved; add one from Gallery.';
    }
    if (!mounted) return;
    final duplicate = context.read<LibraryModel>().books.any(
      (b) =>
          b.id != widget.book?.id &&
          ((result.isbn.isNotEmpty &&
                  BookLookup.normalizeIsbn(b.isbn) == result.isbn) ||
              (b.title.toLowerCase() == result.title.toLowerCase() &&
                  b.author.toLowerCase() == result.author.toLowerCase())),
    );
    setState(() {
      _fields['Title']!.text = result.title;
      _fields['Author']!.text = result.author;
      _fields['ISBN']!.text = result.isbn;
      _fields['Publisher']!.text = result.publisher;
      _fields['Publication year']!.text = result.year?.toString() ?? '';
      _fields['Total pages']!.text = result.pages?.toString() ?? '';
      if (cover != null) _cover = cover;
      _saving = false;
      _error = duplicate
          ? 'This book may already be in your library. Review before saving.'
          : warning;
    });
  }

  Future<void> _pickCover(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 2400,
      );
      if (picked == null || !mounted) return;
      final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => CoverCropScreen(path: picked.path)),
      );
      if (path != null && mounted) setState(() => _cover = path);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not open the camera or photos. Please try again.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final library = context.read<LibraryModel>();
    var b = (widget.book ?? Book(id: const Uuid().v4(), title: value('Title')))
        .copyWith(
          title: value('Title'),
          author: value('Author'),
          collection: _collection,
          coverImagePath: _cover,
          totalPages: int.tryParse(value('Total pages')),
          totalMinutes: minutes(value('Audio duration (h:mm)')),
          subtitle: value('Subtitle'),
          isbn: value('ISBN'),
          publisher: value('Publisher'),
          year: int.tryParse(value('Publication year')),
          language: value('Language'),
          series: value('Series'),
          seriesNumber: value('Series number'),
          format: _format,
          tags: value('Tags / genres')
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList(),
          notes: value('Personal notes'),
          dropReason: value('Why I dropped it'),
          status: _status,
        );
    var sessions = List<ReadingSession>.of(b.sessions);
    if (_status == BookStatus.toRead) sessions.removeWhere((s) => s.isOpen);
    if (_status == BookStatus.reading && b.openSession == null) {
      sessions.add(
        ReadingSession(
          id: const Uuid().v4(),
          startDate: _start,
          precision: _precision,
          format: _format,
          totalLength: _format == BookFormat.audiobook
              ? b.totalMinutes
              : b.totalPages,
        ),
      );
    } else if (_status == BookStatus.reading) {
      sessions = sessions
          .map(
            (s) => !s.isOpen
                ? s
                : s.copyWith(startDate: _start, precision: _precision),
          )
          .toList();
    }
    if (_status == BookStatus.read) {
      final target = b.openSession ?? sessions.lastOrNull;
      final closed =
          (target ??
                  ReadingSession(
                    id: const Uuid().v4(),
                    startDate: _start,
                    format: _format,
                    totalLength: _format == BookFormat.audiobook
                        ? b.totalMinutes
                        : b.totalPages,
                  ))
              .copyWith(
                startDate: _start,
                endDate: _end,
                rating: _rating,
                precision: _precision,
                currentPage: target != null
                    ? target.totalLength ?? target.currentPage
                    : (_format == BookFormat.audiobook
                              ? b.totalMinutes
                              : b.totalPages) ??
                          0,
              );
      if (target == null) {
        sessions.add(closed);
      } else {
        sessions = sessions.map((s) => s.id == target.id ? closed : s).toList();
      }
    }
    b = b.copyWith(sessions: sessions);
    final ok = widget.book == null
        ? await library.addBook(b)
        : await library.updateBook(b);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = library.saveError ?? 'Your changes could not be saved.';
      });
    }
  }

  Future<void> _pickDate(bool end) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial = DateUtils.dateOnly(end ? _end : _start);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: end ? DateUtils.dateOnly(_start) : DateTime(1900),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (end) {
        _end = _precision == DatePrecision.approximate
            ? snapToMonthEnd(picked)
            : picked;
      } else {
        _start = _precision == DatePrecision.approximate
            ? snapToMonthStart(picked)
            : picked;
        if (_end.isBefore(_start)) _end = _start;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: libraryEditorBar(
      context,
      widget.book == null ? 'Add book' : 'Edit book',
      _saving ? null : _save,
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          OutlinedButton.icon(
            onPressed: _saving ? null : _findBook,
            icon: const Icon(Icons.manage_search),
            label: const Text('Find by title or scan ISBN'),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 116,
                color: context.c.plate,
                child: _cover != null && File(_cover!).existsSync()
                    ? Image.file(File(_cover!), fit: BoxFit.cover)
                    : const Icon(Icons.book_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cover stays in app storage. Location metadata is removed.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _pickCover(ImageSource.gallery),
                          child: const Text('Gallery'),
                        ),
                        TextButton(
                          onPressed: () => _pickCover(ImageSource.camera),
                          child: const Text('Camera'),
                        ),
                        if (_cover != null)
                          TextButton(
                            onPressed: () => setState(() => _cover = null),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          field('Title', required: true),
          field('Author'),
          CollectionFields(
            value: _collection,
            onChanged: (v) => setState(() => _collection = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<BookFormat>(
            isExpanded: true,
            initialValue: _format,
            decoration: InputDecoration(
              labelText: widget.book == null
                  ? 'Format for first read'
                  : 'Default format for new reads',
              helperText: widget.book == null
                  ? null
                  : 'Change each read’s format in reading history.',
            ),
            items: BookFormat.values
                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (f) => setState(() => _format = f!),
          ),
          const SizedBox(height: 14),
          if (_format == BookFormat.audiobook)
            field('Audio duration (h:mm)')
          else
            field('Total pages', number: true),
          DropdownButtonFormField<BookStatus>(
            isExpanded: true,
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Shelf'),
            items: BookStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (s) => setState(() => _status = s!),
          ),
          const SizedBox(height: 14),
          if (_status == BookStatus.dropped)
            field('Why I dropped it', lines: 3),
          if (_status == BookStatus.reading || _status == BookStatus.read) ...[
            const SectionHeading('dates'),
            const SizedBox(height: 12),
            SegmentedChoice<DatePrecision>(
              values: DatePrecision.values,
              value: _precision,
              labelOf: (p) => p.label,
              onChanged: (p) => setState(() {
                _precision = p;
                if (p == DatePrecision.approximate) {
                  _start = snapToMonthStart(_start);
                  _end = snapToMonthEnd(_end);
                }
              }),
            ),
            if (_precision != DatePrecision.unknown) ...[
              ListTile(
                title: const Text('Started'),
                subtitle: Text(dateAtPrecision(_start, _precision)),
                onTap: () => _pickDate(false),
              ),
              if (_status == BookStatus.read)
                ListTile(
                  title: const Text('Finished'),
                  subtitle: Text(dateAtPrecision(_end, _precision)),
                  onTap: () => _pickDate(true),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'This read counts in all-time totals, without invented dates.',
                ),
              ),
          ],
          if (_status == BookStatus.read)
            StarRating(
              value: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),
          const SizedBox(height: 20),
          ExpansionTile(
            title: const Text('Book details (optional)'),
            tilePadding: EdgeInsets.zero,
            children: [
              field('Subtitle'),
              field('ISBN'),
              field('Publisher'),
              field('Publication year', number: true),
              field('Language'),
              field('Series'),
              field('Series number'),
            ],
          ),
          const SizedBox(height: 14),
          field('Tags / genres'),
          field('Personal notes', lines: 4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(_error!, style: TextStyle(color: context.c.danger)),
            ),
          FilledButton(
            key: const ValueKey('save-book'),
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? 'Saving…'
                  : widget.book == null
                  ? 'Add to library'
                  : 'Save changes',
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}
