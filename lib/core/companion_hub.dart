import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'backup_type.dart';
import 'companion_data.dart';
import 'companion_backup_screen.dart';
import 'library.dart';
import 'physical_collection.dart';

const _modeIcons = [
  Icons.menu_book_outlined,
  Icons.auto_stories_outlined,
  Icons.movie_outlined,
  Icons.live_tv_outlined,
];

class CompanionHub extends StatelessWidget {
  const CompanionHub({
    super.key,
    required this.data,
    required this.libraries,
    this.initialTab = 0,
    this.initialDay,
  });
  final CompanionData data;
  final List<LibraryController> libraries;
  final int initialTab;
  final DateTime? initialDay;
  Future<void> _open(
    BuildContext context,
    CompanionMode mode,
    String id, {
    bool edit = false,
  }) async {
    final rows = libraries[mode.index].rows(
      LibraryDisplayQuery()..ignoreFilters = true,
    );
    final row = rows.where((r) => r.id == id).firstOrNull;
    if (row == null) return;
    if (edit) {
      await row.edit(context);
    } else {
      await row.details(context);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    initialIndex: initialTab,
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Your Companion'),
        actions: [
          IconButton(
            tooltip: 'Complete backup',
            icon: const Icon(Icons.backup_outlined),
            onPressed: () =>
                openLibraryPage(context, CompanionBackupScreen(data: data)),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: [
            Tab(text: 'Activity'),
            Tab(text: 'Rediscover'),
            Tab(text: 'Collection'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: data,
        builder: (context, _) => Column(
          children: [
            if (data.hasLoadFailure)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'One library needs recovery. These views may be incomplete. Open its import and recovery tools.',
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _Diary(
                    events: data.diary(),
                    initialDay: initialDay,
                    firstDay: data.settings.firstDayOfWeek,
                    onOpen: (e) => _open(context, e.mode, e.entryId),
                  ),
                  _Rediscover(
                    items: data.rediscover(),
                    onOpen: (e) => _open(context, e.mode, e.id),
                  ),
                  _Collection(
                    items: data.collection(),
                    onOpen: (e) => _open(context, e.mode, e.id, edit: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Diary extends StatefulWidget {
  const _Diary({
    required this.events,
    required this.onOpen,
    required this.firstDay,
    this.initialDay,
  });
  final List<DiaryEvent> events;
  final ValueChanged<DiaryEvent> onOpen;
  final int firstDay;
  final DateTime? initialDay;
  @override
  State<_Diary> createState() => _DiaryState();
}

class _DiaryState extends State<_Diary> {
  late DateTime _day = calendarDay(widget.initialDay ?? DateTime.now());
  CompanionMode? _mode;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final events = widget.events
        .where((e) => _mode == null || e.mode == _mode)
        .toList();
    final days = <DateTime, int>{};
    for (final event in events.where((e) => e.hasDay && e.isActivity)) {
      final key = calendarDay(event.date!);
      days[key] = (days[key] ?? 0) + 1;
    }
    final years = {
      DateTime.now().year,
      _day.year,
      ...widget.events.where((e) => e.date != null).map((e) => e.year!),
    }.toList()..sort((a, b) => b.compareTo(a));
    final first = DateTime(_day.year, _day.month);
    final startOffset =
        (first.weekday - (widget.firstDay == 0 ? 7 : 1) + 7) % 7;
    final count = DateTime(_day.year, _day.month + 1, 0).day;
    final selected = events
        .where((e) => e.hasDay && calendarDay(e.date!) == _day)
        .toList();
    final uncertain = events
        .where((e) => e.date != null && !e.hasDay && e.date!.year == _day.year)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          'A day in your library',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Reading and watching, together. Choose a day to revisit what you logged.',
        ),
        const SizedBox(height: 16),
        _ModeFilter(
          value: _mode,
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: _day.year,
              onChanged: (year) {
                if (year != null) {
                  setState(
                    () => _day = DateTime(
                      year,
                      _day.month,
                      min(_day.day, DateTime(year, _day.month + 1, 0).day),
                    ),
                  );
                }
              },
              items: years
                  .map(
                    (year) =>
                        DropdownMenuItem(value: year, child: Text('$year')),
                  )
                  .toList(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Year in review'),
              onPressed: () => openLibraryPage(
                context,
                _YearReview(events: widget.events, initialYear: _day.year),
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  setState(() => _day = DateTime(_day.year, _day.month - 1)),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(_day),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: () =>
                  setState(() => _day = DateTime(_day.year, _day.month + 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      DateFormat.E().format(
                        DateTime(2024, 1, widget.firstDay == 0 ? 7 + i : 1 + i),
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: ((startOffset + count + 6) ~/ 7) * 7,
          itemBuilder: (context, index) {
            final number = index - startOffset + 1;
            if (number < 1 || number > count) return const SizedBox.shrink();
            final date = DateTime(_day.year, _day.month, number);
            final activity = days[date] ?? 0;
            final selected = date == _day;
            final intensity = activity == 0
                ? 0.0
                : min(.18 + activity * .16, 1.0);
            return Semantics(
              button: true,
              selected: selected,
              label:
                  '${DateFormat.yMMMMd().format(date)}, $activity activities',
              child: Material(
                color: Color.lerp(
                  colors.surfaceContainerHighest,
                  colors.primary,
                  intensity,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: selected
                      ? BorderSide(color: colors.onSurface, width: 2)
                      : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _day = date),
                  child: Center(
                    child: ExcludeSemantics(
                      child: Text(
                        '$number',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: intensity > .6
                              ? colors.onPrimary
                              : colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Less', style: Theme.of(context).textTheme.labelSmall),
            for (final intensity in [0.0, .35, .65, 1.0])
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Color.lerp(
                      colors.surfaceContainerHighest,
                      colors.primary,
                      intensity,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text('More', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  setState(() => _day = calendarDay(DateTime.now())),
              child: const Text('Today'),
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          DateFormat.yMMMMEEEEd().format(_day),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (selected.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No activity logged on this day. Progress and dated reads or viewings appear here.',
            ),
          ),
        for (final event in selected)
          _EventTile(event: event, onTap: () => widget.onOpen(event)),
        if (uncertain.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Dates remembered more roughly'),
            subtitle: Text(
              '${uncertain.length} records in ${_day.year} · excluded from the daily heatmap',
            ),
            children: [
              for (final event in uncertain)
                _EventTile(
                  event: event,
                  onTap: () => widget.onOpen(event),
                  showDate: true,
                ),
            ],
          ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.onTap,
    this.showDate = false,
  });
  final DiaryEvent event;
  final VoidCallback onTap;
  final bool showDate;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(_modeIcons[event.mode.index]),
    title: Text(event.title),
    subtitle: Text(
      '${event.mode.label} · ${event.detail}${showDate ? '\n${event.precision == 'year' ? event.date!.year : DateFormat.yMMM().format(event.date!)} (approximate)' : ''}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _YearReview extends StatefulWidget {
  const _YearReview({required this.events, required this.initialYear});
  final List<DiaryEvent> events;
  final int initialYear;
  @override
  State<_YearReview> createState() => _YearReviewState();
}

class _YearReviewState extends State<_YearReview> {
  late int _year = widget.initialYear;
  @override
  Widget build(BuildContext context) {
    final years = {
      DateTime.now().year,
      _year,
      ...widget.events.where((e) => e.date != null).map((e) => e.year!),
    }.toList()..sort((a, b) => b.compareTo(a));
    final events = widget.events.where((e) => e.year == _year).toList();
    final activeDays = events
        .where((e) => e.hasDay && e.isActivity)
        .map((e) => calendarDay(e.date!))
        .toSet();
    final titles = events
        .where((e) => e.isActivity)
        .map((e) => '${e.mode.name}:${e.entryId}')
        .toSet();
    final units = <String, int>{};
    for (final event in events.where((e) => e.unit.isNotEmpty)) {
      units.update(
        event.unit,
        (v) => v + event.amount,
        ifAbsent: () => event.amount,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Year in review')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButton<int>(
            value: _year,
            items: years
                .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                .toList(),
            onChanged: (y) => setState(() => _year = y!),
          ),
          Text(
            'Your year, across every shelf',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            '${activeDays.length} active days · ${titles.length} titles revisited',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          if (events.isEmpty)
            const Text(
              'No dated activity this year. Your next logged read or viewing starts the story.',
            ),
          for (final mode in CompanionMode.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_modeIcons[mode.index]),
              title: Text(mode.label),
              subtitle: Text(
                '${events.where((e) => e.mode == mode && e.completed).length} completed reads or viewings · '
                '${events.where((e) => e.mode == mode && e.isActivity).map((e) => e.entryId).toSet().length} titles',
              ),
            ),
          if (units.isNotEmpty) ...[
            const Divider(height: 32),
            Text(
              'Logged progress',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final unit in units.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(unit.key),
                trailing: Text('${max(0, unit.value)}'),
              ),
          ],
          const Divider(height: 32),
          Text(
            'Through the months',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (var month = 1; month <= 12; month++)
            Builder(
              builder: (context) {
                final count = activeDays
                    .where((day) => day.month == month)
                    .length;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          DateFormat.MMM().format(DateTime(_year, month)),
                        ),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: count / DateTime(_year, month + 1, 0).day,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(3),
                          semanticsLabel: '$count active days',
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text('$count', textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          const Text(
            'Based on recorded history. Undated activity is excluded; approximate dates count toward the year but never toward active days. Progress corrections are included. Reading and watching minutes are kept separate.',
          ),
        ],
      ),
    );
  }
}

class _ModeFilter extends StatelessWidget {
  const _ModeFilter({required this.value, required this.onChanged});
  final CompanionMode? value;
  final ValueChanged<CompanionMode?> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final mode in [null, ...CompanionMode.values])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(mode?.label ?? 'All libraries'),
              labelStyle: TextStyle(
                color: value == mode
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              selected: value == mode,
              onSelected: (_) => onChanged(mode),
            ),
          ),
      ],
    ),
  );
}

class _Rediscover extends StatefulWidget {
  const _Rediscover({required this.items, required this.onOpen});
  final List<Rediscovery> items;
  final ValueChanged<Rediscovery> onOpen;
  @override
  State<_Rediscover> createState() => _RediscoverState();
}

class _RediscoverState extends State<_Rediscover> {
  CompanionMode? _mode;
  @override
  Widget build(BuildContext context) {
    final items = widget.items
        .where((e) => _mode == null || e.mode == _mode)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Something worth coming back to',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Older additions, paused reads and shows close to the finish. Titles active in the last two weeks get time to breathe.',
        ),
        const SizedBox(height: 16),
        _ModeFilter(value: _mode, onChanged: (v) => setState(() => _mode = v)),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const Text(
            'Nothing forgotten here yet. Older unfinished titles will appear with a reason to return.',
          ),
        for (final item in items)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Icon(_modeIcons[item.mode.index]),
            title: Text(item.title),
            subtitle: Text('${item.mode.label}\n${item.reasons.join(' · ')}'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onOpen(item),
          ),
      ],
    );
  }
}

class _Collection extends StatefulWidget {
  const _Collection({required this.items, required this.onOpen});
  final List<CollectionItem> items;
  final ValueChanged<CollectionItem> onOpen;
  @override
  State<_Collection> createState() => _CollectionState();
}

class _CollectionState extends State<_Collection> {
  String _filter = 'all', _query = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.items.where((e) {
      final c = e.collection;
      final matches = switch (_filter) {
        'owned' => c.ownership == Ownership.owned,
        'borrowed' => c.ownership == Ownership.borrowed,
        'lent' => c.lentTo.isNotEmpty,
        'missing' => c.missingVolumes.isNotEmpty,
        _ => true,
      };
      return matches &&
          '${e.title} ${c.shelf} ${c.borrowedFrom} ${c.lentTo}'
              .toLowerCase()
              .contains(_query.toLowerCase());
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Know where every volume is',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Books and manga you own, borrow or lend. Edit an entry’s physical collection details to track it here.',
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            labelText: 'Search titles, shelves or people',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (id, label) in [
                ('all', 'All'),
                ('owned', 'Owned'),
                ('borrowed', 'Borrowed'),
                ('lent', 'Lent out'),
                ('missing', 'Missing volumes'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    labelStyle: TextStyle(
                      color: _filter == id
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    selected: _filter == id,
                    onSelected: (_) => setState(() => _filter = id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const Text(
            'No matching collection entries. Open a book or manga editor and expand “Physical collection” to add ownership, shelf or loan details.',
          ),
        for (final item in items)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Icon(_modeIcons[item.mode.index]),
            title: Text(item.title),
            subtitle: Text(
              '${item.collection.summary}${item.collection.missingVolumes.isEmpty ? '' : '\nMissing: ${item.collection.missingVolumes.take(20).join(', ')}${item.collection.missingVolumes.length > 20 ? '…' : ''}'}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => widget.onOpen(item),
          ),
      ],
    );
  }
}
