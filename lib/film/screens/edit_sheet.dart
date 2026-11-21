import 'package:flutter/material.dart';

import '../../core/library.dart';
import '../../core/title_lookup.dart';
import '../../core/title_lookup_screen.dart';

import '../app_state.dart';
import '../import_plan.dart';
import '../format.dart';
import '../models/shelf_entry.dart';
import '../models/viewing.dart';
import '../theme.dart';
import '../widgets/sheet.dart';

/// Bottom sheet for adding or editing a title. Returns the entry on save,
/// null on dismiss.
Future<ShelfEntry?> showEditSheet(
  BuildContext context, {
  ShelfEntry? initial,
  AppState? state,
  bool fullPage = false,
  TitleLookup? lookup,
}) {
  if (fullPage) {
    final editor = GlobalKey<_EditSheetState>();
    return Navigator.of(context).push<ShelfEntry>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: libraryEditorBar(
            context,
            initial == null ? 'Add film or series' : 'Edit film or series',
            () => editor.currentState?._save(),
          ),
          body: SafeArea(
            top: false,
            child: _EditSheet(
              key: editor,
              state: state,
              initial: initial,
              fullPage: true,
              lookup: lookup,
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<ShelfEntry>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditSheet(initial: initial, state: state, lookup: lookup),
  );
}

class _EditSheet extends StatefulWidget {
  final ShelfEntry? initial;
  final AppState? state;
  final bool fullPage;
  final TitleLookup? lookup;
  const _EditSheet({
    super.key,
    this.initial,
    this.state,
    this.fullPage = false,
    this.lookup,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _year;
  late final TextEditingController _runtime;
  late final TextEditingController _episodes;
  late final TextEditingController _watched;
  late final TextEditingController _director;
  late final TextEditingController _posterUrl;
  late final TextEditingController _watchUrl;
  late final TextEditingController _note;
  late final TextEditingController _tags;
  late final TextEditingController _seasons;
  late String _kind;
  late String _status;

  /// Working copies, so dismissing the sheet leaves the log untouched.
  /// Sorted when the sheet opens and again on save, but never while you are
  /// editing — rows jumping out from under a finger is worse than a list
  /// briefly out of order.
  late List<Viewing> _viewings;

  String? _titleError;
  String? _yearError;
  String? _formError;
  bool _saving = false;

  bool get isEdit => widget.initial != null;
  bool get isSeries => _kind == 'series';
  bool get isSeen => _status == 'seen';

  Future<void> _lookup() async {
    final item = await openLibraryPage<TitleMetadata>(
      context,
      TitleLookupScreen(
        catalog: isSeries ? TitleCatalog.series : TitleCatalog.film,
        initialQuery: _title.text,
        lookup: widget.lookup,
      ),
    );
    if (item == null || !mounted) return;
    setState(() {
      _title.text = item.title;
      if (item.year != null) _year.text = '${item.year}';
      if (item.minutes != null) _runtime.text = '${item.minutes}';
      if (item.creator.isNotEmpty) _director.text = item.creator;
      if (item.coverUrl.isNotEmpty) _posterUrl.text = item.coverUrl;
      if (item.episodes != null) {
        final watched = int.tryParse(_watched.text) ?? 0;
        final seasons = _seasons.text.trim().isEmpty
            ? <int>[]
            : _seasons.text
                  .split(',')
                  .map((s) => int.tryParse(s.trim()) ?? 0)
                  .toList();
        if (item.episodes! >= watched &&
            (seasons.isEmpty ||
                seasons.fold<int>(0, (sum, n) => sum + n) == item.episodes)) {
          _episodes.text = '${item.episodes}';
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Kept your episode total to preserve your progress and season lengths.',
              ),
            ),
          );
        }
      }
      _titleError = null;
      _yearError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _year = TextEditingController(text: e?.year == null ? '' : '${e!.year}');
    _runtime = TextEditingController(
      text: e?.runtime == null ? '' : '${e!.runtime}',
    );
    _episodes = TextEditingController(
      text: e?.episodes == null ? '' : '${e!.episodes}',
    );
    _watched = TextEditingController(
      text: (e == null || e.watched == 0) ? '' : '${e.watched}',
    );
    _director = TextEditingController(text: e?.director ?? '');
    _posterUrl = TextEditingController(text: e?.posterUrl ?? '');
    _watchUrl = TextEditingController(text: e?.watchUrl ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _seasons = TextEditingController(text: e?.seasons.join(', ') ?? '');
    _kind = e?.kind ?? 'film';
    _status = e?.status ?? 'watchlist';
    _viewings = (e?.viewings ?? const <Viewing>[]).map((v) => v.copy()).toList()
      ..sort(Viewing.compare);
    // Something filed straight under "seen" has usually just been watched.
    if (_status == 'seen' && _viewings.isEmpty) _viewings.add(Viewing.now());
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _year,
      _runtime,
      _episodes,
      _watched,
      _director,
      _posterUrl,
      _watchUrl,
      _note,
      _tags,
      _seasons,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _formError = null);
    final title = _title.text.trim();
    final yearText = _year.text.trim();
    final year = int.tryParse(yearText);
    // A typo'd year would quietly ruin sorting and the leader frame, so it
    // is the one field worth stopping for.
    final badYear =
        yearText.isNotEmpty && (year == null || year < 1870 || year > 2999);

    if (title.isEmpty || title.length > 1000 || badYear) {
      setState(() {
        _titleError = title.isEmpty
            ? 'Give the title a name.'
            : title.length > 1000
            ? 'Use at most 1,000 characters.'
            : null;
        _yearError = badYear ? 'Four digits, like 1999.' : null;
      });
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = widget.initial?.copy() ?? ShelfEntry.blank();
    entry.kind = _kind;
    entry.title = title;
    entry.year = year;
    entry.runtime = int.tryParse(_runtime.text.trim());
    entry.director = _director.text.trim();
    entry.posterUrl = _posterUrl.text.trim();
    entry.watchUrl = _watchUrl.text.trim();
    entry.note = _note.text.trim();
    entry.tags = _tags.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (entry.tags.length > 100) {
      setState(() => _formError = 'Use at most 100 tags per title.');
      return;
    }
    final rawSeasons = _seasons.text.trim();
    final seasons = rawSeasons.isEmpty
        ? <int>[]
        : rawSeasons
              .split(',')
              .map((s) => int.tryParse(s.trim()) ?? 0)
              .toList();
    if (isSeries && seasons.any((s) => s < 1 || s > 10000)) {
      setState(
        () => _formError =
            'Season lengths need positive episode counts, separated by commas.',
      );
      return;
    }
    entry.seasons = isSeries ? seasons : [];
    if (_runtime.text.trim().isNotEmpty &&
        (entry.runtime == null ||
            entry.runtime! <= 0 ||
            entry.runtime! > 100000)) {
      setState(
        () => _formError = 'Runtime needs a positive number of minutes.',
      );
      return;
    }
    entry.status = _status;

    if (isSeries) {
      final episodes = int.tryParse(_episodes.text.trim());
      final seasonTotal = seasons.fold(0, (a, b) => a + b);
      if ((_episodes.text.trim().isNotEmpty &&
              (episodes == null || episodes < 1 || episodes > 100000)) ||
          seasonTotal > 100000 ||
          seasons.length > 1000 ||
          (_watched.text.trim().isNotEmpty &&
              int.tryParse(_watched.text.trim()) == null)) {
        setState(
          () => _formError = 'Check the episode counts. Use positive season lengths and at most 100,000 episodes.',
        );
        return;
      }
      entry.episodes = (episodes != null && episodes > 0) ? episodes : null;
      if (seasonTotal > 0 &&
          entry.episodes != null &&
          entry.episodes != seasonTotal) {
        setState(
          () => _formError =
              'The season lengths must add up to the episode total.',
        );
        return;
      }
      var watched = int.tryParse(_watched.text.trim()) ?? 0;
      if (watched < 0) watched = 0;
      // You cannot have watched more episodes than exist; the tally would
      // over-report your hours for the rest of time.
      if (entry.episodes != null && watched > entry.episodes!) {
        watched = entry.episodes!;
      }
      entry.watched = watched;
      // Every episode accounted for means the thing is finished, and
      // leaving it queued would put it in a band it no longer belongs to.
      if (entry.status == 'watchlist' && entry.isFinished) {
        entry.status = 'seen';
      }
    } else {
      // Switching a series back to a film drops what only a series can
      // have, rather than leaving an orphan count in the backup.
      entry.episodes = null;
      entry.watched = 0;
    }

    // The log is kept whatever shelf the title ends up on — walking out of
    // a rewatch does not unmake the times you did sit through it.
    entry.viewings = [..._viewings]..sort(Viewing.compare);
    if (entry.status == 'seen') {
      if (entry.viewings.isEmpty) entry.viewings.add(Viewing.now());
      if (entry.isSeries && entry.episodes != null) {
        entry.watched = entry.episodes!;
      }
    }
    entry.lastUpdated = now;
    final duplicate = widget.state?.duplicateOf(entry);
    if (duplicate != null &&
        (widget.initial == null ||
            ImportPlan.identity(widget.initial!) !=
                ImportPlan.identity(entry) ||
            !widget.state!.entries.any((e) => e.id == entry.id))) {
      _saving = true;
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already on your shelf'),
          content: Text(
            'You already have ${duplicate.title}${duplicate.year == null ? '' : ' (${duplicate.year})'}. Add another copy?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add another'),
            ),
          ],
        ),
      );
      _saving = false;
      if (add != true || !mounted) return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    bool numeric = false,
    bool autofocus = false,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          maxLines: maxLines,
          onChanged: onChanged,
          style: (numeric ? Type.numberSm.copyWith(fontSize: 15) : Type.body)
              .copyWith(color: t.ink),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: errorText,
          ),
        ),
      ],
    );
  }

  /// Segmented control. Square-ish and ruled, and the selected one is
  /// marked by the same ink underline the status rail uses — never by the
  /// accent, which belongs to runtime alone.
  Widget _segments(
    List<(String, String)> options,
    String selected,
    ValueChanged<String> onSelect,
  ) => DropdownButtonFormField<String>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: options.first.$1 == 'film' ? 'Type' : 'Shelf',
    ),
    items: options
        .map(
          (option) =>
              DropdownMenuItem(value: option.$1, child: Text(option.$2)),
        )
        .toList(),
    onChanged: (value) {
      if (value != null) onSelect(value);
    },
  );

  // ----------------------------------------------------------- viewing log

  static const _precisionLabels = {
    'day': 'Day',
    'month': 'Month',
    'year': 'Year',
    'unknown': 'Not sure',
  };

  Future<void> _pickDate(Viewing v) async {
    final now = DateTime.now();
    final start = v.pickerDate.isAfter(now)
        ? now
        : v.pickerDate.isBefore(DateTime(1900))
        ? DateTime(1900)
        : v.pickerDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(1900),
      // You cannot have watched it after today.
      lastDate: now,
      // A coarse precision opens where the choice actually is.
      initialDatePickerMode: v.precision == 'day'
          ? DatePickerMode.day
          : DatePickerMode.year,
      // The system picker only deals in days, and its own headline will say
      // so. Rather than let that contradict the precision you chose, the
      // help text says which part of the answer is actually being kept.
      helpText: switch (v.precision) {
        'year' => 'ANY DAY IN THE RIGHT YEAR',
        'month' => 'ANY DAY IN THE RIGHT MONTH',
        _ => 'WHEN YOU WATCHED IT',
      },
    );
    if (picked != null) setState(() => v.setDate(picked, v.precision));
  }

  /// How much of this date you are willing to swear to. A menu rather than
  /// four more segments, because there is one of these per viewing and the
  /// row still has to hold a date and a way to delete it.
  Widget _precisionChip(Viewing v) {
    final t = context.tk;
    return PopupMenuButton<String>(
      tooltip: 'How well you remember this date',
      position: PopupMenuPosition.under,
      onSelected: (p) => setState(() => v.setPrecision(p)),
      itemBuilder: (_) => [
        for (final entry in _precisionLabels.entries)
          PopupMenuItem(
            value: entry.key,
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: v.precision == entry.key
                      ? Icon(Icons.check_rounded, size: 15, color: t.ink)
                      : null,
                ),
                Text(entry.value),
              ],
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Precision: ${_precisionLabels[v.precision]}. Change it',
        excludeSemantics: true,
        // Fixed to the widest label, so a column of these reads as a
        // column rather than three chips of three different sizes.
        child: Container(
          height: 44,
          width: 90,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(R.control),
            border: Border.all(color: t.rule),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _precisionLabels[v.precision]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.meta.copyWith(color: t.inkFaint),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, size: 15, color: t.inkFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewingRow(Viewing v) {
    final t = context.tk;
    final unknown = v.precision == 'unknown';
    final label = watchedLabel(v.at, v.precision);
    final canDelete = _viewings.length > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: !unknown,
              label: unknown ? 'No date on this viewing' : 'Watched $label',
              excludeSemantics: true,
              child: InkWell(
                onTap: unknown ? null : () => _pickDate(v),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: unknown ? t.rule : t.ruleStrong,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          unknown ? 'No date' : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.body.copyWith(
                            color: unknown ? t.inkGhost : t.ink,
                          ),
                        ),
                      ),
                      if (!unknown)
                        Icon(Icons.event_outlined, size: 17, color: t.inkFaint),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _precisionChip(v),
          Semantics(
            button: true,
            enabled: canDelete,
            label: 'Remove this viewing',
            excludeSemantics: true,
            child: InkResponse(
              radius: 22,
              // A seen title has been seen; removing the last viewing is a
              // change of shelf, not of tally.
              onTap: canDelete
                  ? () => setState(() => _viewings.remove(v))
                  : null,
              child: SizedBox(
                width: 40,
                height: 44,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: canDelete ? t.inkFaint : t.inkGhost,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Only a seen title has viewings to date, so the whole log belongs to
  /// the seen shelf and appears with it.
  Widget _viewingLog() {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: SectionLabel('Viewings')),
            Text(
              '${_viewings.length}',
              style: Type.meta.copyWith(color: t.inkGhost),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final v in _viewings) ...[
          _viewingRow(v),
          TextFormField(
            key: ValueKey((v, 'location')),
            initialValue: v.location,
            decoration: const InputDecoration(
              labelText: 'Where · cinema, home…',
            ),
            onChanged: (value) => v.location = value.trim(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey((v, 'company')),
            initialValue: v.company,
            decoration: const InputDecoration(
              labelText: 'With whom · optional',
            ),
            onChanged: (value) => v.company = value.trim(),
          ),
          const SizedBox(height: 18),
        ],
        const SizedBox(height: 4),
        Semantics(
          button: true,
          label: 'Add a viewing',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => _viewings.insert(0, Viewing.now())),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: t.rule)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: t.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    'Add a viewing',
                    style: Type.label.copyWith(color: t.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = widget.fullPage
        ? EdgeInsets.zero
        : MediaQuery.viewInsetsOf(context);
    final maxHeight =
        MediaQuery.sizeOf(context).height * (widget.fullPage ? 1 : .9);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SheetScaffold(
          title: isEdit ? 'Edit title' : 'Add a title',
          showHeader: !widget.fullPage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First, because it decides what the rest of the form even
                // asks for.
                const SizedBox(height: 8),
                _segments(
                  const [('film', 'Film'), ('series', 'Series')],
                  _kind,
                  (v) => setState(() => _kind = v),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _lookup,
                    icon: const Icon(Icons.search),
                    label: Text(isSeries ? 'Find a series' : 'Find a film'),
                  ),
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'Title',
                  controller: _title,
                  hint: isSeries ? 'Mr. Robot' : 'Heat',
                  autofocus: !isEdit,
                  capitalization: TextCapitalization.words,
                  errorText: _titleError,
                  onChanged: (_) {
                    if (_titleError != null) {
                      setState(() => _titleError = null);
                    }
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        label: isSeries ? 'First aired' : 'Year',
                        controller: _year,
                        hint: isSeries ? '2015' : '1995',
                        numeric: true,
                        keyboardType: TextInputType.number,
                        errorText: _yearError,
                        onChanged: (_) {
                          if (_yearError != null) {
                            setState(() => _yearError = null);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _field(
                        // The unit is the whole point: the shelf sorts by
                        // what one sitting costs, and for a series that is
                        // an episode.
                        label: isSeries
                            ? 'Minutes an episode'
                            : 'Runtime, minutes',
                        controller: _runtime,
                        hint: isSeries ? '45' : '170',
                        numeric: true,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                if (isSeries) ...[
                  const SizedBox(height: 18),
                  _field(
                    label: 'Episodes per season · optional',
                    controller: _seasons,
                    hint: '10, 10, 8',
                    keyboardType: TextInputType.text,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          label: 'Episodes',
                          controller: _episodes,
                          hint: 'blank if still running',
                          numeric: true,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _field(
                          label: 'Episodes watched',
                          controller: _watched,
                          hint: '0',
                          numeric: true,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                _field(
                  label: isSeries ? 'Created by' : 'Director',
                  controller: _director,
                  hint: isSeries ? 'Sam Esmail' : 'Michael Mann',
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 18),
                _field(
                  label: 'Where you watch it',
                  controller: _watchUrl,
                  hint: 'https://…',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 18),
                _field(
                  label: 'Poster image link',
                  controller: _posterUrl,
                  hint: 'https://…',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 18),
                _field(
                  label: 'What you thought',
                  controller: _note,
                  hint: 'One line, for when it comes up again',
                  maxLines: 2,
                  capitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 18),
                _field(
                  label: 'Tags · comma separated',
                  controller: _tags,
                  hint: 'with family, Criterion, cinema only',
                ),
                const SizedBox(height: 22),
                const SizedBox(height: 8),
                _segments(
                  const [
                    ('watchlist', 'Watchlist'),
                    ('seen', 'Seen'),
                    ('bailed', 'Bailed'),
                  ],
                  _status,
                  (v) => setState(() {
                    _status = v;
                    // Moving something onto the seen shelf means it was
                    // watched; the log needs a first entry to hold that.
                    if (v == 'seen' && _viewings.isEmpty) {
                      _viewings.add(Viewing.now());
                    }
                  }),
                ),
                // Sits directly under the control that summons it, so the
                // form reshapes where you are already looking.
                if (isSeen || _viewings.isNotEmpty) _viewingLog(),
                const SizedBox(height: 26),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _formError!,
                      style: Type.bodySm.copyWith(color: context.tk.danger),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(isEdit ? 'Save changes' : 'Add to shelf'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
