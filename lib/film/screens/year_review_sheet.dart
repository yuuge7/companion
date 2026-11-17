import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models/viewing.dart';
import '../theme.dart';
import '../widgets/sheet.dart';

Future<void> showYearReviewSheet(BuildContext context, AppState state) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _YearReviewSheet(state: state),
    );

class _YearReviewSheet extends StatefulWidget {
  final AppState state;
  const _YearReviewSheet({required this.state});
  @override
  State<_YearReviewSheet> createState() => _YearReviewSheetState();
}

class _YearReviewSheetState extends State<_YearReviewSheet> {
  int year = DateTime.now().year;
  @override
  Widget build(BuildContext context) {
    final review = widget.state.review(year);
    final years = {
      DateTime.now().year,
      for (final e in widget.state.entries)
        for (final v in e.viewings)
          if (v.isDated) DateTime.fromMillisecondsSinceEpoch(v.at!).year,
    }.toList()..sort((a, b) => b.compareTo(a));
    final log = [...review.viewings]
      ..sort((a, b) => Viewing.compare(a.$2, b.$2));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SheetScaffold(
        title: 'Year in review',
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButton<int>(
              value: year,
              items: [
                for (final y in years)
                  DropdownMenuItem(
                    value: y,
                    child: Text('$y', style: Type.numberSm),
                  ),
              ],
              onChanged: (v) => setState(() => year = v!),
            ),
            const SizedBox(height: 16),
            Text(
              review.viewings.isEmpty
                  ? 'No dated viewings on record for $year.'
                  : 'In $year, you logged ${review.films} film viewings and ${review.series} complete series viewings — ${spanOfTime(review.minutes)} on record.',
              style: Type.body,
            ),
            const SizedBox(height: 12),
            const Text(
              'Only viewings dated to at least a year count here. Partial series progress has no dated viewing and is excluded.',
            ),
            if (review.unmeasured > 0)
              Text(
                '${review.unmeasured} viewings have no measured runtime or series length.',
              ),
            const SizedBox(height: 24),
            const SectionLabel('The ledger'),
            for (final (entry, viewing) in log)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.title, style: Type.title),
                subtitle: Text(watchedLabel(viewing.at, viewing.precision)),
                trailing: Text(
                  entry.isSeries ? 'Series' : runtimeLong(entry.runtime),
                  style: Type.meta,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
