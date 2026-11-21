import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'title_lookup.dart';

class TitleLookupScreen extends StatefulWidget {
  const TitleLookupScreen({
    super.key,
    required this.catalog,
    this.initialQuery = '',
    this.lookup,
  });
  final TitleCatalog catalog;
  final String initialQuery;
  final TitleLookup? lookup;
  @override
  State<TitleLookupScreen> createState() => _TitleLookupScreenState();
}

class _TitleLookupScreenState extends State<TitleLookupScreen> {
  late final _query = TextEditingController(text: widget.initialQuery);
  late final _lookup = widget.lookup ?? TitleLookup();
  List<TitleMetadata>? _results;
  TitleMetadata? _selected;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
              : 'Could not read this catalog. Try again or add manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() => _run(() async {
    setState(() {
      _selected = null;
      _results = null;
    });
    final rows = await _lookup.search(widget.catalog, _query.text);
    if (mounted) setState(() => _results = rows);
  });
  Future<void> _select(TitleMetadata row) => _run(() async {
    final details = await _lookup.details(row);
    if (mounted) setState(() => _selected = details);
  });
  Future<void> _source(TitleMetadata item) async {
    try {
      if (await launchUrl(
        Uri.parse(item.sourceUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Keep the review available when no browser is installed. */
    }
    if (mounted) setState(() => _error = 'Could not open the source link.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'Find ${widget.catalog == TitleCatalog.anime ? 'an anime' : 'a ${widget.catalog.label}'}',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Search ${widget.catalog == TitleCatalog.anime || widget.catalog == TitleCatalog.manga ? 'Jikan and Kitsu' : widget.catalog.source} by title. Review a result before filling your editor.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('title-lookup-query'),
          controller: _query,
          enabled: !_busy,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            labelText: 'Search title',
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Add manually'),
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
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (_selected case final item?) ...[
          const SizedBox(height: 24),
          Text('Review title', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 110,
              height: 160,
              child: item.coverUrl.isEmpty
                  ? const Center(
                      child: Text(
                        'No cover available',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.coverUrl,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => const Center(
                        child: Text(
                          'Cover unavailable',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          if (item.creator.isNotEmpty) Text(item.creator),
          const SizedBox(height: 12),
          Text('Year: ${item.year ?? 'Not provided'}'),
          if (item.format.isNotEmpty) Text('Format: ${item.format}'),
          if (item.season.isNotEmpty) Text('Release season: ${item.season}'),
          if (item.catalog == TitleCatalog.manga) ...[
            Text('Chapters: ${item.chapters ?? 'Unknown'}'),
            Text('Volumes: ${item.volumes ?? 'Unknown'}'),
          ] else ...[
            if (item.catalog != TitleCatalog.film)
              Text('Total episodes: ${item.episodes ?? 'Unknown'}'),
            Text(
              '${item.catalog == TitleCatalog.film || item.format.toLowerCase() == 'movie' ? 'Runtime' : 'Minutes per episode'}: ${item.minutes ?? 'Unknown'}',
            ),
          ],
          if (item.sourceUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _source(item),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  'Source: ${item.sourceName}${item.catalog == TitleCatalog.series ? ' (CC BY-SA)' : ''}',
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Available details replace matching editor fields. Your progress, ratings, notes and history stay as entered. You can edit everything before saving.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => Navigator.pop(context, item),
            child: const Text('Use these details'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _selected = null),
            child: const Text('Back to results'),
          ),
        ] else if (_results != null) ...[
          const SizedBox(height: 20),
          if (_results!.isEmpty)
            const Text(
              'No titles found. Try another title or add it manually.',
            ),
          for (final item in _results!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(
                [
                  if (item.year != null) '${item.year}',
                  if (item.format.isNotEmpty) item.format,
                  if (item.creator.isNotEmpty) item.creator,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _select(item),
            ),
        ],
      ],
    ),
  );
}
