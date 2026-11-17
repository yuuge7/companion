import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'backup_type.dart';
import 'design.dart';
import 'widgets/star_rating.dart';

PreferredSizeWidget libraryEditorBar(
  BuildContext context,
  String title,
  VoidCallback? save,
) => AppBar(
  title: Text(title),
  actions: [TextButton(onPressed: save, child: const Text('Save'))],
);

class LibraryChoice {
  const LibraryChoice(this.id, this.label);
  final String id, label;
}

class LibraryDisplayQuery {
  String search = '', shelf = 'all', sort = 'recent';
  bool descending = false;
}

class LibraryAction {
  const LibraryAction(this.id, this.label, this.icon, this.run);
  final String id, label;
  final IconData icon;
  final Future<void> Function(BuildContext) run;
}

/// Presentation only. Each controller retains its own typed models and codecs.
class LibraryRowData {
  const LibraryRowData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.edit,
    required this.details,
    this.coverUrl,
    this.coverPath,
    this.fraction,
    this.rating,
    this.primary,
    this.decrease,
    this.increase,
    this.stepUnit = '',
    this.stepName = '',
    this.actions = const [],
  });
  final String id, title, subtitle, progress, stepUnit, stepName;
  final String? coverUrl, coverPath;
  final double? fraction, rating;
  final Future<void> Function(BuildContext) edit, details;
  final LibraryAction? primary;
  final Future<void> Function(BuildContext)? decrease, increase;
  final List<LibraryAction> actions;
}

class LibraryMetric {
  const LibraryMetric(this.label, this.value, [this.detail = '']);
  final String label, value, detail;
}

class LibraryActionError implements Exception {
  const LibraryActionError(this.message);
  final String message;
}

abstract class LibraryController extends ChangeNotifier {
  LibraryController(this.model) {
    model.addListener(notifyListeners);
  }
  final Listenable model;
  CompanionMode get mode;
  String get singular;
  IconData get icon;
  List<LibraryChoice> get shelves;
  List<LibraryChoice> get sorts;
  int get totalCount;
  String? get error => null;
  bool get locked => false;
  bool get saving => false;
  bool get hasFilters => false;
  bool get canTag => false;
  int count(String shelf);
  List<LibraryRowData> rows(LibraryDisplayQuery query);
  Future<void> add(BuildContext context);
  Future<void> importExport(BuildContext context);
  List<LibraryMetric> get metrics;
  Future<void> detailedStats(BuildContext context);
  Future<void> filters(BuildContext context, LibraryDisplayQuery query);
  void clearFilters();
  Future<void> bulk(BuildContext context, Set<String> ids, String action);
  List<LibraryAction> get tools => const [];
  @override
  void dispose() {
    model.removeListener(notifyListeners);
    super.dispose();
  }
}

Future<T?> openLibraryPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

Future<void> showLibraryDetails(
  BuildContext context, {
  required String title,
  required List<LibraryMetric> values,
  List<LibraryMetric> history = const [],
  LibraryAction? extra,
}) => openLibraryPage<void>(
  context,
  Scaffold(
    appBar: AppBar(title: const Text('Details & history')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        ...values.map((value) => _MetricTile(value)),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('History', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...history.map((value) => _MetricTile(value)),
        ],
        if (extra != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => extra.run(context),
            icon: Icon(extra.icon),
            label: Text(extra.label),
          ),
        ],
      ],
    ),
  ),
);

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});
  final LibraryController controller;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _query = LibraryDisplayQuery();
  final _search = TextEditingController();
  final _selected = <String>{};
  bool _working = false;
  LibraryController get library => widget.controller;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is LibraryActionError
                  ? error.message
                  : library.error ?? 'Could not save that change. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });
  Future<void> _stats() => openLibraryPage<void>(
    context,
    Scaffold(
      appBar: AppBar(title: Text('${library.mode.label} statistics')),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Your ${library.mode.label.toLowerCase()} library',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            ...library.metrics.map((metric) => _MetricTile(metric)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => library.detailedStats(context),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Detailed statistics'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final rows = library.rows(_query);
      final working = _working || library.saving;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _selected.isEmpty
                ? library.mode.label
                : '${_selected.length} selected',
          ),
          leading: _selected.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                ),
          actions: _selected.isEmpty
              ? [
                  IconButton(
                    tooltip: '${library.mode.label} statistics',
                    onPressed: _stats,
                    icon: const Icon(Icons.bar_chart_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '${library.mode.label} tools',
                    onSelected: (value) {
                      if (value == 'data') {
                        library.importExport(context);
                      } else if (value == 'stats') {
                        _stats();
                      } else {
                        _run(
                          () => library.tools
                              .firstWhere((action) => action.id == value)
                              .run(context),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'data',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.import_export),
                          title: Text('Import & export'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'stats',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.bar_chart_outlined),
                          title: Text('Statistics'),
                        ),
                      ),
                      ...library.tools.map(
                        (action) => PopupMenuItem(
                          value: action.id,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(action.icon),
                            title: Text(action.label),
                          ),
                        ),
                      ),
                    ],
                  ),
                ]
              : [
                  IconButton(
                    tooltip: 'Select all visible titles',
                    onPressed: () => setState(
                      () => _selected.addAll(rows.map((row) => row.id)),
                    ),
                    icon: const Icon(Icons.select_all),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Bulk actions',
                    enabled: !working,
                    onSelected: (value) => _run(() async {
                      await library.bulk(context, {..._selected}, value);
                      if (mounted) setState(_selected.clear);
                    }),
                    itemBuilder: (_) => [
                      ...library.shelves.map(
                        (shelf) => PopupMenuItem(
                          value: shelf.id,
                          child: Text('Move to ${shelf.label}'),
                        ),
                      ),
                      if (library.canTag)
                        const PopupMenuItem(
                          value: 'tag',
                          child: Text('Add tag'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete selected'),
                      ),
                    ],
                  ),
                ],
        ),
        floatingActionButton: _selected.isNotEmpty
            ? null
            : FloatingActionButton.extended(
                heroTag: 'add-${library.mode.name}',
                onPressed: working || library.locked
                    ? null
                    : () => _run(() => library.add(context)),
                icon: const Icon(Icons.add),
                label: const Text('Add title'),
              ),
        body: Column(
          children: [
            if (library.saving) const LinearProgressIndicator(minHeight: 2),
            if (library.error != null)
              MaterialBanner(
                content: Text(library.error!),
                actions: [
                  TextButton(
                    onPressed: () => library.importExport(context),
                    child: const Text('Recovery options'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                key: const ValueKey('library-search'),
                controller: _search,
                onChanged: (value) => setState(() => _query.search = value),
                decoration: InputDecoration(
                  hintText: 'Search ${library.mode.label.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(() {
                            _search.clear();
                            _query.search = '';
                          }),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final shelf in [
                    const LibraryChoice('all', 'All'),
                    ...library.shelves,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          '${shelf.label}  ${library.count(shelf.id)}',
                        ),
                        labelStyle: CompanionType.small.copyWith(
                          color: _query.shelf == shelf.id
                              ? colors.onPrimary
                              : colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        selected: _query.shelf == shelf.id,
                        onSelected: (_) => setState(() {
                          _query.shelf = shelf.id;
                          _selected.clear();
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${rows.length} ${rows.length == 1 ? "title" : "titles"}',
                    style: CompanionType.small.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await library.filters(context, _query);
                      if (mounted) setState(() {});
                    },
                    icon: Icon(
                      library.hasFilters ? Icons.filter_alt : Icons.tune,
                      size: 18,
                    ),
                    label: Text(library.hasFilters ? 'Filters on' : 'Filters'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Sort ${library.mode.label.toLowerCase()}',
                    onSelected: (value) => setState(() => _query.sort = value),
                    itemBuilder: (_) => library.sorts
                        .map(
                          (sort) => CheckedPopupMenuItem(
                            value: sort.id,
                            checked: _query.sort == sort.id,
                            child: Text(sort.label),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            library.sorts
                                .firstWhere(
                                  (sort) => sort.id == _query.sort,
                                  orElse: () => library.sorts.first,
                                )
                                .label,
                            style: CompanionType.small,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reverse sort order',
                    iconSize: 18,
                    onPressed: () =>
                        setState(() => _query.descending = !_query.descending),
                    icon: Icon(
                      _query.descending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                    ),
                  ),
                ],
              ),
            ),
            if (library.hasFilters)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.close, size: 16),
                    label: const Text('Clear filters'),
                    onPressed: () => setState(library.clearFilters),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                library.icon,
                                size: 40,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                library.totalCount == 0
                                    ? 'Your ${library.mode.label.toLowerCase()} library starts here'
                                    : 'No matching titles',
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                library.totalCount == 0
                                    ? 'Add your first ${library.singular} or import a backup.'
                                    : 'Try another shelf, search or filter.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                onPressed: () => library.importExport(context),
                                icon: const Icon(Icons.import_export),
                                label: const Text('Import & export'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: PageStorageKey('library-${library.mode.name}'),
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => LibraryItemRow(
                        data: rows[index],
                        icon: library.icon,
                        selected: _selected.contains(rows[index].id),
                        selecting: _selected.isNotEmpty,
                        busy: working,
                        onSelect: () => _toggle(rows[index].id),
                        run: (action) => _run(() => action(context)),
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showLibraryRating(
  BuildContext context,
  num value,
  Future<void> Function(int) save,
) async {
  final next = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rating'),
      content: SharedStarRating(
        value: value,
        onChanged: (rating) => Navigator.pop(ctx, rating),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (next != null) await save(next);
}

Future<String?> requestLibraryTag(BuildContext context) async {
  final field = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add tag'),
      content: TextField(
        controller: field,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Tag'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, field.text.trim()),
          child: const Text('Add tag'),
        ),
      ],
    ),
  );
  // The closing route may retain the field during its transition.
  Future<void>.delayed(const Duration(seconds: 1), field.dispose);
  return result == null || result.isEmpty ? null : result;
}

class LibraryItemRow extends StatelessWidget {
  const LibraryItemRow({
    super.key,
    required this.data,
    required this.icon,
    required this.selected,
    required this.selecting,
    required this.busy,
    required this.onSelect,
    required this.run,
  });
  final LibraryRowData data;
  final IconData icon;
  final bool selected, selecting, busy;
  final VoidCallback onSelect;
  final void Function(Future<void> Function(BuildContext)) run;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 28, color: colors.onSurfaceVariant),
      ),
    );

    Widget art = fallback;
    if (data.coverPath != null && data.coverPath!.isNotEmpty) {
      art = Image.file(
        File(data.coverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (data.coverUrl != null && data.coverUrl!.isNotEmpty) {
      art = CachedNetworkImage(
        imageUrl: data.coverUrl!,
        fit: BoxFit.cover,
        memCacheWidth: 240,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      );
    }
    return Material(
      color: selected ? colors.surfaceContainerHighest : Colors.transparent,
      child: InkWell(
        onLongPress: onSelect,
        onTap: selecting ? onSelect : () => run(data.edit),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 54,
                    height: 76,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: art,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: CompanionType.title.copyWith(
                            color: colors.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (data.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            data.subtitle,
                            style: CompanionType.small.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 9),
                        Text(
                          data.progress,
                          style: CompanionType.number.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selecting)
                    Checkbox(value: selected, onChanged: (_) => onSelect())
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Actions for ${data.title}',
                      enabled: !busy,
                      onSelected: (value) {
                        if (value == 'edit') {
                          run(data.edit);
                        } else if (value == 'details') {
                          run(data.details);
                        } else {
                          run(
                            data.actions
                                .firstWhere((action) => action.id == value)
                                .run,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit title'),
                        ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Text('Details & history'),
                        ),
                        ...data.actions.map(
                          (action) => PopupMenuItem(
                            value: action.id,
                            child: Text(action.label),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (data.fraction != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 12),
                  child: LinearProgressIndicator(
                    value: data.fraction!.clamp(0, 1),
                    minHeight: 3,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    data.rating == null || data.rating == 0
                        ? Icons.star_border
                        : Icons.star,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    data.rating == null || data.rating == 0
                        ? 'Unrated'
                        : '${data.rating!.toStringAsFixed(data.rating! % 1 == 0 ? 0 : 1)}/5',
                    style: CompanionType.small.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (!selecting && data.stepUnit.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'Decrease ${data.stepName} for ${data.title}',
                      onPressed: busy || data.decrease == null
                          ? null
                          : () => run(data.decrease!),
                      icon: const Icon(Icons.remove, size: 20),
                    ),
                    Text(data.stepUnit, style: CompanionType.small),
                    IconButton(
                      tooltip: 'Increase ${data.stepName} for ${data.title}',
                      onPressed: busy || data.increase == null
                          ? null
                          : () => run(data.increase!),
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ] else if (!selecting && data.primary != null)
                    TextButton(
                      onPressed: busy ? null : () => run(data.primary!.run),
                      child: Text(data.primary!.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.metric);
  final LibraryMetric metric;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metric.label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        SelectableText(
          metric.value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (metric.detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(metric.detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

class LibraryDataPage extends StatefulWidget {
  const LibraryDataPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.description,
  });
  final LibraryController controller;
  final List<LibraryAction> actions;
  final String description;
  @override
  State<LibraryDataPage> createState() => _LibraryDataPageState();
}

class _LibraryDataPageState extends State<LibraryDataPage> {
  String? _busy;
  Future<void> _run(LibraryAction action) async {
    setState(() => _busy = action.id);
    try {
      await action.run(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is LibraryActionError ? error.message : 'Could not complete this file operation. Your library has been kept.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.controller.mode.label} import & export'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Backups', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(widget.description),
        const SizedBox(height: 24),
        ...widget.actions.map(
          (action) => Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                leading: Icon(action.icon),
                title: Text(action.label),
                subtitle: _busy == action.id ? const Text('Working…') : null,
                trailing: const Icon(Icons.chevron_right),
                enabled: _busy == null,
                onTap: () => _run(action),
              ),
              const Divider(height: 1),
            ],
          ),
        ),
      ],
    ),
  );
}
