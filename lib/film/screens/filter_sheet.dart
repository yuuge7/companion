import 'package:flutter/material.dart';

import '../shelf_filter.dart';
import '../widgets/sheet.dart';

Future<ShelfFilter?> showFilterSheet(
  BuildContext context,
  ShelfFilter current,
  List<String> tags,
) => showModalBottomSheet<ShelfFilter>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _FilterSheet(current: current, tags: tags),
);

class _FilterSheet extends StatefulWidget {
  final ShelfFilter current;
  final List<String> tags;
  const _FilterSheet({required this.current, required this.tags});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final from = TextEditingController(
    text: widget.current.yearFrom?.toString() ?? '',
  );
  late final to = TextEditingController(
    text: widget.current.yearTo?.toString() ?? '',
  );
  late final minutes = TextEditingController(
    text: widget.current.minutes?.toString() ?? '',
  );
  late String kind = widget.current.kind ?? 'all';
  late String tag = widget.current.tag ?? '';
  late int rating = widget.current.minRating;
  String? error;
  @override
  void dispose() {
    from.dispose();
    to.dispose();
    minutes.dispose();
    super.dispose();
  }

  Widget _number(String label, TextEditingController ctrl) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
  );
  void _apply() {
    int? number(TextEditingController c) => int.tryParse(c.text.trim());
    final a = number(from), b = number(to), m = number(minutes);
    if ((from.text.isNotEmpty && (a == null || a < 1870 || a > 2999)) ||
        (to.text.isNotEmpty && (b == null || b < 1870 || b > 2999)) ||
        (a != null && b != null && a > b) ||
        (minutes.text.isNotEmpty && (m == null || m < 1 || m > 10000))) {
      setState(
        () => error = 'Check the year range and enter a positive time budget.',
      );
      return;
    }
    Navigator.pop(
      context,
      ShelfFilter()
        ..kind = kind == 'all' ? null : kind
        ..yearFrom = a
        ..yearTo = b
        ..minRating = rating
        ..tag = tag.isEmpty ? null : tag
        ..minutes = m,
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SheetScaffold(
        title: 'What fits tonight',
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            _number('I have this many minutes', minutes),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Only measured sittings that fit. Series show how many episodes fit.',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Films and series')),
                DropdownMenuItem(value: 'film', child: Text('Films')),
                DropdownMenuItem(value: 'series', child: Text('Series')),
              ],
              onChanged: (v) => kind = v!,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _number('From year', from)),
                const SizedBox(width: 16),
                Expanded(child: _number('To year', to)),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: rating,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Minimum rating'),
              items: [
                for (var i = 0; i <= 5; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(i == 0 ? 'Any rating' : '$i stars or more'),
                  ),
              ],
              onChanged: (v) => rating = v!,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: tag,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tag'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Any tag')),
                for (final t in {...widget.tags, if (tag.isNotEmpty) tag})
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => tag = v!,
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!),
              ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _apply, child: const Text('Apply filters')),
            TextButton(
              onPressed: () => Navigator.pop(context, ShelfFilter()),
              child: const Text('Clear all filters'),
            ),
          ],
        ),
      ),
    ),
  );
}
