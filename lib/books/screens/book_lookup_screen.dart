import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/book_lookup.dart';

class BookLookupScreen extends StatefulWidget {
  const BookLookupScreen({super.key, this.lookup});
  final BookLookup? lookup;
  @override
  State<BookLookupScreen> createState() => _BookLookupScreenState();
}

class _BookLookupScreenState extends State<BookLookupScreen> {
  final _query = TextEditingController();
  late final _lookup = widget.lookup ?? BookLookup();
  List<BookMetadata>? _results;
  BookMetadata? _selected;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Could not look up this book. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() => _run(() async {
    final results = await _lookup.search(_query.text);
    if (mounted) {
      setState(() {
        _results = results;
        _selected = null;
      });
    }
  });
  Future<void> _select(BookMetadata book) => _run(() async {
    final details = book.edition.isEmpty
        ? book
        : await _lookup.edition(book.edition) ?? book;
    if (mounted) setState(() => _selected = details);
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find a book')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Search Open Library by title or ISBN. Review the edition, then use its details in your book editor.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _query,
          enabled: !_busy,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            labelText: 'Title or ISBN',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final isbn = await _lookup.scanIsbn();
                      if (isbn == null || !mounted) return;
                      _query.text = isbn;
                      final results = await _lookup.search(isbn);
                      if (mounted) {
                        setState(() {
                          _results = results;
                          _selected = null;
                        });
                      }
                    }),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan ISBN'),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_selected case final book?) ...[
          const SizedBox(height: 24),
          Text('Review edition', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (book.coverUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: CachedNetworkImage(
                imageUrl: book.coverUrl,
                height: 160,
                errorWidget: (_, _, _) => const Icon(Icons.menu_book, size: 64),
              ),
            ),
          const SizedBox(height: 16),
          Text(book.title, style: Theme.of(context).textTheme.headlineSmall),
          Text(book.author),
          const SizedBox(height: 12),
          Text('ISBN: ${book.isbn.isEmpty ? 'Not provided' : book.isbn}'),
          Text(
            'Publisher: ${book.publisher.isEmpty ? 'Not provided' : book.publisher}',
          ),
          Text(
            'Published: ${book.year ?? 'Not provided'} · Pages: ${book.pages ?? 'Not provided'}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Check that this is your edition. You can change every field before saving.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => Navigator.pop(context, book),
            child: const Text('Use these details'),
          ),
        ] else if (_results != null) ...[
          const SizedBox(height: 20),
          if (_results!.isEmpty)
            const Text(
              'No books found. Try another title or ISBN, or go back to add it manually.',
            ),
          for (final book in _results!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(book.title),
              subtitle: Text(book.author),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _select(book),
            ),
        ],
      ],
    ),
  );
}
