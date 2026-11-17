import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../format.dart';
import '../models/shelf_entry.dart';
import '../shelf_filter.dart';
import 'filter_sheet.dart';
import 'year_review_sheet.dart';
import '../theme.dart';
import '../widgets/shelf_row.dart';
import 'edit_sheet.dart';
import 'settings_sheet.dart';
import 'stats_sheet.dart';

/// The shelf.
///
/// Three statuses are filters over one list, not destinations, so they sit
/// in a rail at the top rather than in a bottom bar. The watchlist opens
/// shortest-first and bands by runtime, because the question this app can
/// answer and a catalogue cannot is "what fits tonight". The seen shelf
/// bands by date instead: there it is a viewing log.
class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _tab = 'watchlist';
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _query = '';
  Timer? _debounce;
  ShelfFilter _filter = ShelfFilter();
  final Set<String> _selected = {};
  bool _working = false;

  AppState get state => widget.state;

  static const _tabs = [
    (id: 'watchlist', label: 'WATCHLIST'),
    (id: 'seen', label: 'SEEN'),
    (id: 'bailed', label: 'BAILED'),
  ];

  static const _sortLabels = {
    SortMode.shelf: 'shelf',
    SortMode.title: 'title',
    SortMode.runtime: 'runtime',
    SortMode.rating: 'rating',
    SortMode.year: 'year',
  };

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 160), () {
        if (mounted) setState(() => _query = _searchCtrl.text);
      });
    });
    if (state.recovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _snack(
            'Recovered the previous saved copy. Export a backup in Settings.',
          );
        }
      });
    }
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onState() => setState(() {});

  // --------------------------------------------------------------- actions

  Future<void> _addEntry() async {
    final entry = await showEditSheet(context, state: state);
    if (entry != null) {
      await _run(() => state.add(entry));
      if (mounted && entry.status != _tab) setState(() => _tab = entry.status);
    }
  }

  Future<void> _editEntry(ShelfEntry item) async {
    final updated = await showEditSheet(context, initial: item, state: state);
    if (updated != null) await _run(() => state.update(updated));
  }

  void _snack(String text, {VoidCallback? undo}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        action: undo == null
            ? null
            : SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_working) return false;
    setState(() => _working = true);
    try {
      await action();
      return true;
    } catch (_) {
      _snack(state.saveError ?? 'Could not save that change. Try again.');
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmDelete(ShelfEntry item) async {
    if (await _run(() => state.remove(item.id))) {
      final deleted = state.trash.where((t) => t.entry.id == item.id).last;
      _snack(
        '${item.title} moved to 30-day trash.',
        undo: () => _run(() => state.restoreTrash(deleted)),
      );
    }
  }

  Future<void> _bulk({
    String? status,
    bool delete = false,
    bool tag = false,
  }) async {
    final ids = {..._selected};
    final existingTrash = state.trash.toSet();
    List<String>? tags;
    if (tag) {
      final ctrl = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tag selected titles'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'with family, cinema only',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Add tags'),
            ),
          ],
        ),
      );
      // The dialog route may still be animating out when its result arrives.
      Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
      if (value == null || value.trim().isEmpty) return;
      tags = value
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
    }
    if (await _run(
      () => state.bulk(ids, status: status, tags: tags, delete: delete),
    )) {
      final removed = state.trash
          .where((t) => ids.contains(t.entry.id) && !existingTrash.contains(t))
          .toList();
      if (mounted) setState(_selected.clear);
      _snack(
        delete
            ? '${ids.length} titles moved to trash.'
            : '${ids.length} titles updated.',
        undo: delete
            ? () => _run(() => state.restoreTrashBatch(removed))
            : null,
      );
    }
  }

  Future<void> _filters() async {
    final value = await showFilterSheet(context, _filter, state.tags);
    if (value != null && mounted) setState(() => _filter = value);
  }

  Future<void> _pick() async {
    final choices = state
        .visible('watchlist', _query, filter: _filter)
        .where((e) => e.hasRuntime && (!e.isSeries || e.episodesLeft != 0))
        .toList();
    if (choices.isEmpty) {
      _snack('No measured titles fit these filters.');
      return;
    }
    final picked = choices[Random().nextInt(choices.length)];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(picked.title),
        content: Text(
          '${runtimeLong(picked.runtime)}${picked.isSeries ? '/episode · ${picked.nextEpisode}' : ''}'
          '${_filter.minutes != null && picked.isSeries ? '\n${picked.episodesThatFit(_filter.minutes!)} episodes fit tonight.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pick();
            },
            child: const Text('Pick again'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _editEntry(picked);
            },
            child: const Text('Open title'),
          ),
        ],
      ),
    );
  }

  Widget _tools() => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _filters,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  _filter.minutes != null
                      ? '${_filter.minutes} min · filters'
                      : _filter.active
                      ? 'Filters on'
                      : 'Time & filters',
                ),
              ),
              if (_filter.active)
                IconButton(
                  tooltip: 'Clear filters',
                  onPressed: () => setState(() => _filter = ShelfFilter()),
                  icon: const Icon(Icons.close, size: 17),
                ),
            ],
          ),
          if (_tab == 'watchlist')
            TextButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.shuffle, size: 17),
              label: const Text('Pick for me'),
            ),
        ],
      ),
    ),
  );

  // ---------------------------------------------------------------- header

  Widget _iconButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    double size = 20,
  }) {
    return Tooltip(
      message: label,
      child: InkResponse(
        radius: 24,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Semantics(
            button: true,
            label: label,
            child: Icon(icon, size: size, color: context.tk.inkMuted),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final t = context.tk;
    if (_selected.isNotEmpty) {
      return Row(
        children: [
          IconButton(
            tooltip: 'Cancel selection',
            onPressed: () => setState(_selected.clear),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text('${_selected.length} selected', style: Type.label),
          ),
          TextButton(
            onPressed: () => setState(
              () => _selected.addAll(
                state.visible(_tab, _query, filter: _filter).map((e) => e.id),
              ),
            ),
            child: const Text('All'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Bulk actions',
            onSelected: (value) {
              if (value == 'tag') {
                _bulk(tag: true);
              } else if (value == 'delete') {
                _bulk(delete: true);
              } else {
                _bulk(status: value);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'watchlist',
                child: Text('Move to watchlist'),
              ),
              PopupMenuItem(value: 'seen', child: Text('Move to seen')),
              PopupMenuItem(value: 'bailed', child: Text('Move to bailed')),
              PopupMenuItem(value: 'tag', child: Text('Add tags')),
              PopupMenuItem(value: 'delete', child: Text('Move to trash')),
            ],
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: _searching
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: Type.body.copyWith(color: t.ink),
                    decoration: const InputDecoration(
                      hintText: 'Search title or maker',
                    ),
                  )
                : Text(
                    'SCREEN COMPANION',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.display.copyWith(color: t.ink),
                  ),
          ),
          const SizedBox(width: 4),
          _iconButton(
            _searching ? Icons.close_rounded : Icons.search_rounded,
            _searching ? 'Close search' : 'Search your shelf',
            () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            }),
          ),
          if (!_searching) ...[
            _iconButton(Icons.add_rounded, 'Add a title', _addEntry, size: 24),
            SizedBox(
              width: 44,
              height: 44,
              child: PopupMenuButton<String>(
                tooltip: 'More',
                position: PopupMenuPosition.under,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: t.inkMuted,
                ),
                onSelected: (v) {
                  if (v == 'stats') showStatsSheet(context, state);
                  if (v == 'year') showYearReviewSheet(context, state);
                  if (v == 'settings') showSettingsSheet(context, state);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'year', child: Text('Year in review')),
                  PopupMenuItem(
                    value: 'stats',
                    height: 44,
                    child: Text('Stats'),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    height: 44,
                    child: Text('Settings'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Status rail. Counts are the point, so they are set large in mono; the
  /// active filter is marked by an ink underline, never by the accent.
  Widget _rail() {
    final t = context.tk;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final tab in _tabs)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _tab == tab.id,
                  label:
                      '${tab.label.toLowerCase()}, ${state.countFor(tab.id)} titles',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => setState(() {
                      _tab = tab.id;
                      _selected.clear();
                    }),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _tab == tab.id ? t.ink : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.eyebrow.copyWith(
                              fontSize: 11,
                              color: _tab == tab.id ? t.inkMuted : t.inkGhost,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${state.countFor(tab.id)}',
                            style: Type.number.copyWith(
                              fontSize: 20,
                              color: _tab == tab.id ? t.ink : t.inkGhost,
                            ),
                          ),
                          const SizedBox(height: 7),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _sortControl(),
          ],
        ),
      ),
    );
  }

  Widget _sortControl() {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 6),
      child: PopupMenuButton<SortMode>(
        tooltip: 'Sort the shelf',
        position: PopupMenuPosition.under,
        onSelected: state.setSort,
        itemBuilder: (_) => [
          for (final (mode, label) in [
            (SortMode.shelf, 'Shelf order'),
            (SortMode.runtime, 'Shortest first'),
            (SortMode.title, 'Title A–Z'),
            (SortMode.rating, 'Rating'),
            (SortMode.year, 'Newest film first'),
          ])
            PopupMenuItem(
              value: mode,
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: state.sortMode == mode
                        ? Icon(Icons.check_rounded, size: 15, color: t.ink)
                        : null,
                  ),
                  Text(label),
                ],
              ),
            ),
        ],
        child: Semantics(
          button: true,
          label: 'Sort the shelf, currently ${_sortLabels[state.sortMode]}',
          excludeSemantics: true,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(R.control),
              border: Border.all(color: t.rule),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert_rounded, size: 14, color: t.inkFaint),
                const SizedBox(width: 4),
                Text(
                  _sortLabels[state.sortMode]!,
                  style: Type.meta.copyWith(color: t.inkFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- bands

  /// The watchlist bands by length whenever it is ordered by length, which
  /// is what makes "what fits tonight" answerable at a glance. The seen
  /// shelf bands by date, where it is a log. Nothing else bands.
  bool get _banded =>
      (_tab == 'watchlist' &&
          (state.sortMode == SortMode.shelf ||
              state.sortMode == SortMode.runtime)) ||
      (_tab == 'seen' && state.sortMode == SortMode.shelf);

  /// A band is a claim about when something happened, so it can never be
  /// narrower than the date it is grouping. A month you half-remember can
  /// reach "this month" and no further; a bare year cannot even do that.
  String _bandFor(ShelfEntry e) {
    if (_tab == 'watchlist') return e.lengthBand;
    if (!e.hasWatchedDate) return 'DATE NOT RECORDED';
    final ts = e.watchedAt!;
    final now = DateTime.now();
    if (e.watchedPrecision == 'year') return 'EARLIER';
    final startOfMonth = DateTime(now.year, now.month).millisecondsSinceEpoch;
    if (e.watchedPrecision == 'month') {
      return ts >= startOfMonth ? 'THIS MONTH' : 'EARLIER';
    }
    final startOfToday = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    if (ts >= startOfToday) return 'TODAY';
    final age = now.millisecondsSinceEpoch - ts;
    if (age < 7 * 86400000) return 'THIS WEEK';
    if (age < 30 * 86400000) return 'THIS MONTH';
    return 'EARLIER';
  }

  Widget _bandHeader(String label, int count) {
    final t = context.tk;
    return Container(
      color: t.groundSunken,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.eyebrow.copyWith(fontSize: 11, color: t.inkFaint),
            ),
          ),
          Text('$count', style: Type.meta.copyWith(color: t.inkGhost)),
        ],
      ),
    );
  }

  Widget _footer(List<ShelfEntry> list) {
    final t = context.tk;
    final minutes = state.minutesIn(list);
    final tally = switch (_tab) {
      'watchlist' => minutes == 0 ? '' : '${spanOfTime(minutes)} to clear',
      'seen' => minutes == 0 ? '' : '${spanOfTime(minutes)} watched',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            titleCount(list.length),
            style: Type.meta.copyWith(color: t.inkGhost),
          ),
          if (tally.isNotEmpty)
            Text(tally, style: Type.meta.copyWith(color: t.inkGhost)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- states

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final t = context.tk;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 26, color: t.inkGhost),
            const SizedBox(height: 16),
            Text(
              title.toUpperCase(),
              style: Type.display.copyWith(fontSize: 20, color: t.ink),
            ),
            const SizedBox(height: 9),
            Text(body, style: Type.bodySm.copyWith(color: t.inkMuted)),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    if (_filter.active) {
      return _message(
        icon: Icons.filter_list_off,
        title: 'Nothing fits these filters',
        body:
            'Try a longer time budget, widen the year range or clear a filter.',
        actionLabel: 'Adjust filters',
        onAction: _filters,
      );
    }
    if (_searchCtrl.text.trim().isNotEmpty) {
      return _message(
        icon: Icons.search_off_rounded,
        title: 'No matches here',
        body:
            'Nothing on the $_tab shelf matches '
            '"${_searchCtrl.text.trim()}". Try fewer words, or look in '
            'another tab.',
        actionLabel: 'Clear search',
        onAction: () => setState(() {
          _searchCtrl.clear();
          _searching = false;
        }),
      );
    }
    return switch (_tab) {
      'seen' => _message(
        icon: Icons.done_all_rounded,
        title: 'Nothing logged yet',
        body:
            'Finish a film, or the last episode of a series, and it '
            'lands here — dated, ready to rate, counted towards your '
            'hours.',
      ),
      'bailed' => _message(
        icon: Icons.exit_to_app_rounded,
        title: 'You finished everything',
        body:
            'Films you walk out on and series you stop watching land '
            'here. They keep their runtime and their place, in case you '
            'go back.',
      ),
      _ => _message(
        icon: Icons.local_movies_outlined,
        title: 'Nothing queued',
        body:
            'Add a film, or a series and how long one episode runs. '
            'The watchlist sorts itself shortest first, so you can see '
            'what fits tonight.',
        actionLabel: 'Add a title',
        onAction: _addEntry,
      ),
    };
  }

  // ------------------------------------------------------------------ list

  Widget _list(List<ShelfEntry> list) {
    // Store data slots, constructing only the rows in the viewport. Band
    // counts are calculated once, so a large shelf remains linear to build.
    final slots = <Object>[];
    final counts = <String, int>{};
    if (_banded) {
      for (final item in list) {
        final b = _bandFor(item);
        counts[b] = (counts[b] ?? 0) + 1;
      }
    }
    String? band;
    for (final item in list) {
      if (_banded) {
        final b = _bandFor(item);
        if (b != band) {
          slots.add(b);
          band = b;
        }
      }
      slots.add(item);
    }
    return ListView.builder(
      key: ValueKey('$_tab-${state.sortMode}'),
      padding: EdgeInsets.zero,
      itemCount: slots.length + 1,
      itemBuilder: (_, i) {
        if (i == slots.length) return _footer(list);
        final slot = slots[i];
        if (slot is String) return _bandHeader(slot, counts[slot]!);
        final item = slot as ShelfEntry;
        final selecting = _selected.isNotEmpty;
        final row = ShelfRow(
          item: item,
          timeBudget: _filter.minutes,
          onEdit: () => _editEntry(item),
          onDelete: () => _confirmDelete(item),
          onMarkSeen: () => _run(() => state.markSeen(item)),
          onEpisode: (dir) => _run(() => state.advanceEpisode(item, dir)),
          onWatchAgain: () => _run(() => state.watchAgain(item)),
          onUndoPlay: () => _run(() => state.undoPlay(item)),
          onMove: (status) => _run(() => state.setStatus(item, status)),
          onRate: (r) => _run(() => state.setRating(item, r)),
        );
        return Semantics(
          selected: _selected.contains(item.id),
          child: GestureDetector(
            key: ValueKey(item.id),
            behavior: HitTestBehavior.opaque,
            onLongPress: () {
              HapticFeedback.selectionClick();
              setState(() => _selected.add(item.id));
            },
            onTap: selecting
                ? () => setState(() {
                    if (!_selected.add(item.id)) _selected.remove(item.id);
                  })
                : null,
            child: Row(
              children: [
                if (selecting)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _selected.contains(item.id)
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      color: context.tk.ink,
                    ),
                  ),
                Expanded(
                  child: IgnorePointer(
                    ignoring: selecting || _working,
                    child: row,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final list = state.visible(_tab, _query, filter: _filter);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: t.ground,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: PopScope(
        canPop: _selected.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(_selected.clear);
        },
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(),
                _rail(),
                _tools(),
                Expanded(
                  child: state.loadFailed && state.entries.isEmpty
                      ? _message(
                          icon: Icons.report_gmailerrorred_rounded,
                          title: 'Your shelf could not be read',
                          body:
                              'The saved data on this device is damaged, so '
                              'nothing loaded. Import a backup to put your '
                              'shelf back.',
                          actionLabel: 'Open settings',
                          onAction: () => showSettingsSheet(context, state),
                        )
                      : list.isEmpty
                      ? _emptyState()
                      : SafeArea(top: false, child: _list(list)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
