import 'package:flutter/material.dart';

import '../core/widgets/star_rating.dart';
import '../core/library.dart';
import '../core/title_lookup.dart';
import '../core/title_lookup_screen.dart';
import 'anime_entry.dart';

class AnimeEditor extends StatefulWidget {
  const AnimeEditor({super.key, this.initial, this.lookup});
  final AnimeEntry? initial;
  final TitleLookup? lookup;
  @override
  State<AnimeEditor> createState() => _AnimeEditorState();
}

class _AnimeEditorState extends State<AnimeEditor> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = {};
  late AnimeFormat _format;
  late AnimeStatus _status;
  late double _rating;

  Future<void> _lookup() async {
    final item = await openLibraryPage<TitleMetadata>(
      context,
      TitleLookupScreen(
        catalog: TitleCatalog.anime,
        initialQuery: _fields['title']!.text,
        lookup: widget.lookup,
      ),
    );
    if (item == null || !mounted) return;
    setState(() {
      _fields['title']!.text = item.title;
      for (final (key, value) in [
        ('studio', item.creator),
        ('posterUrl', item.coverUrl),
        ('season', item.season),
      ]) {
        if (value.isNotEmpty) _fields[key]!.text = value;
      }
      for (final (key, value) in [
        ('year', item.year),
        ('totalEpisodes', item.episodes),
        ('episodeMinutes', item.minutes),
      ]) {
        if (value != null) _fields[key]!.text = '$value';
      }
      _format = switch (item.format.toLowerCase()) {
        'tv' => AnimeFormat.tv,
        'movie' => AnimeFormat.movie,
        'ova' => AnimeFormat.ova,
        'ona' => AnimeFormat.ona,
        'special' || 'tv special' => AnimeFormat.special,
        _ => AnimeFormat.unknown,
      };
    });
  }

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _format = e?.animeFormat ?? AnimeFormat.tv;
    _status = e?.status ?? AnimeStatus.planned;
    _rating = e?.rating ?? 0;
    final values = e?.toJson() ?? <String, dynamic>{};
    for (final key in [
      'title',
      'studio',
      'year',
      'season',
      'currentEpisode',
      'totalEpisodes',
      'episodeMinutes',
      'watchedMinutes',
      'note',
      'posterUrl',
      'watchUrl',
      'startedDate',
      'finishedDate',
      'rewatches',
    ]) {
      _fields[key] = TextEditingController(text: '${values[key] ?? ""}');
    }
    _fields['tags'] = TextEditingController(text: e?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      final json =
          widget.initial?.toJson() ??
          AnimeEntry(title: _fields['title']!.text).toJson();
      for (final field in _fields.entries) {
        json[field.key] = field.value.text.trim();
      }
      for (final key in [
        'year',
        'currentEpisode',
        'totalEpisodes',
        'episodeMinutes',
        'watchedMinutes',
        'rewatches',
      ]) {
        final text = _fields[key]!.text.trim();
        json[key] = text.isEmpty
            ? (['year', 'totalEpisodes', 'episodeMinutes'].contains(key)
                  ? null
                  : 0)
            : int.parse(text);
      }
      json['animeFormat'] = _format.name;
      json['status'] = _status.name;
      json['rating'] = _rating;
      json['tags'] = _fields['tags']!.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      json['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      Navigator.pop(context, AnimeEntry.fromJson(json));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FormatException
                ? e.message
                : 'Check the anime fields and try again.',
          ),
        ),
      );
    }
  }

  Widget _field(
    String key,
    String label, {
    bool numeric = false,
    bool required = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _fields[key],
      decoration: InputDecoration(labelText: label),
      maxLines: lines,
      keyboardType: numeric ? TextInputType.number : null,
      validator: (raw) {
        final value = raw?.trim() ?? '';
        if (required && value.isEmpty) return '$label is required.';
        if (numeric &&
            value.isNotEmpty &&
            (int.tryParse(value) == null || int.parse(value) < 0)) {
          return 'Enter a whole number of zero or more.';
        }
        if (['watchUrl', 'posterUrl'].contains(key) && value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty) {
            return 'Enter an HTTP or HTTPS URL.';
          }
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: libraryEditorBar(
      context,
      widget.initial == null ? 'Add anime' : 'Edit anime',
      _save,
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _lookup,
              icon: const Icon(Icons.search),
              label: const Text('Find an anime'),
            ),
          ),
          const SizedBox(height: 16),
          _field('title', 'Anime title', required: true),
          DropdownButtonFormField<AnimeFormat>(
            key: ValueKey(_format),
            initialValue: _format,
            decoration: const InputDecoration(labelText: 'Anime format'),
            items: AnimeFormat.values
                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (value) => setState(() => _format = value!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AnimeStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Anime shelf'),
            items: AnimeStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (value) => setState(() => _status = value!),
          ),
          const SizedBox(height: 20),
          if (_format == AnimeFormat.movie) ...[
            _field('episodeMinutes', 'Movie runtime (minutes)', numeric: true),
            _field('watchedMinutes', 'Minutes watched', numeric: true),
          ] else ...[
            _field('currentEpisode', 'Episodes watched', numeric: true),
            _field(
              'totalEpisodes',
              'Total episodes (blank if unknown)',
              numeric: true,
            ),
            _field(
              'episodeMinutes',
              'Minutes per episode (optional)',
              numeric: true,
            ),
          ],
          _field('studio', 'Studio'),
          _field('year', 'Release year', numeric: true),
          _field('season', 'Release season (for example, Winter)'),
          const Text('Rating'),
          SharedStarRating(
            value: _rating,
            onChanged: (value) => setState(() => _rating = value.toDouble()),
          ),
          const SizedBox(height: 16),
          _field('tags', 'Tags, separated by commas'),
          _field('startedDate', 'Started (YYYY, YYYY-MM or YYYY-MM-DD)'),
          _field('finishedDate', 'Finished (YYYY, YYYY-MM or YYYY-MM-DD)'),
          _field('rewatches', 'Rewatches', numeric: true),
          _field('watchUrl', 'Watch link'),
          _field('posterUrl', 'Poster URL'),
          _field('note', 'Notes', lines: 4),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save anime'),
          ),
        ],
      ),
    ),
  );
}

class AnimeImportPreview extends StatelessWidget {
  const AnimeImportPreview({
    super.key,
    required this.incoming,
    required this.existing,
  });
  final List<AnimeEntry> incoming, existing;
  @override
  Widget build(BuildContext context) {
    var added = 0, updated = 0, kept = 0;
    for (final e in incoming) {
      final old = e.importMatch(existing);
      if (old == null) {
        added++;
      } else if (e.updatedAt > old.updatedAt) {
        updated++;
      } else {
        kept++;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Preview anime import')),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${incoming.length} anime titles',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '$added new · $updated newer · $kept kept locally',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Merge adds new anime and updates newer copies. Older copies stay local. Replace moves the current anime library to trash. A pre-import anime snapshot is saved for either choice.',
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: incoming.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(incoming[i].title),
                    subtitle: Text(
                      '${incoming[i].animeFormat.label} · ${incoming[i].progressLabel}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Replace anime library'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Merge anime library'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
