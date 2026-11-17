import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/sheet.dart';

Future<void> showStatsSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StatsSheet(state: state),
  );
}

/// Read as a statement, not as a dashboard: one sentence that says what all
/// of this adds up to, then label on the left and figure on the right,
/// every figure in tabular mono so the column aligns down the page.
class _StatsSheet extends StatelessWidget {
  final AppState state;
  const _StatsSheet({required this.state});

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    bool total = false,
  }) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: (total ? Type.label : Type.bodySm).copyWith(
                color: total ? t.ink : t.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: total
                ? Type.number.copyWith(fontSize: 18, color: t.ink)
                : Type.numberSm.copyWith(fontSize: 15, color: t.ink),
          ),
        ],
      ),
    );
  }

  /// The sentence the rest of the sheet is footnotes to.
  Widget _lede(BuildContext context) {
    final t = context.tk;
    final seen = state.countFor('seen');
    final minutes = state.minutesWatched;
    if (minutes == 0) {
      return Text(
        'Nothing logged yet. Finish a film, or one episode of a series, and '
        'its runtime starts counting here.',
        style: Type.body.copyWith(color: t.inkMuted),
      );
    }
    final episodes = state.episodesWatched;
    return Text.rich(
      TextSpan(
        style: Type.body.copyWith(color: t.inkMuted, fontSize: 15),
        children: [
          const TextSpan(text: 'You have sat through '),
          TextSpan(
            text: spanOfTime(minutes),
            style: Type.numberSm.copyWith(fontSize: 15, color: t.ink),
          ),
          TextSpan(
            text: episodes == 0
                ? ' of screen time, across ${titleCount(seen)}.'
                : ' of screen time — ${titleCount(seen)} finished, and '
                      '$episodes ${episodes == 1 ? 'episode' : 'episodes'} '
                      'along the way.',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final avg = state.averageRating;
    final rated = state.entries
        .where((e) => e.status == 'seen' && e.rating > 0)
        .length;
    final queued = state.minutesQueued;
    final unmeasured = state.unmeasuredQueued;
    final earliest = state.earliestYearSeen;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SheetScaffold(
        title: 'Stats',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lede(context),
              const SizedBox(height: 24),
              const SectionLabel('By shelf'),
              const SizedBox(height: 4),
              _line(context, 'Watchlist', '${state.countFor('watchlist')}'),
              Divider(color: t.rule, height: 1),
              _line(context, 'Seen', '${state.countFor('seen')}'),
              Divider(color: t.rule, height: 1),
              _line(context, 'Bailed', '${state.countFor('bailed')}'),
              Container(
                margin: const EdgeInsets.only(top: 4),
                height: 1,
                color: t.ruleStrong,
              ),
              _line(
                context,
                'Titles tracked',
                '${state.entries.length}',
                total: true,
              ),
              const SizedBox(height: 22),
              const SectionLabel('What it is'),
              const SizedBox(height: 4),
              _line(context, 'Films', '${state.countOfKind('film')}'),
              Divider(color: t.rule, height: 1),
              _line(context, 'Series', '${state.countOfKind('series')}'),
              Divider(color: t.rule, height: 1),
              _line(context, 'Episodes watched', '${state.episodesWatched}'),
              const SizedBox(height: 22),
              const SectionLabel('Time'),
              const SizedBox(height: 4),
              _line(context, 'Watched', spanOfTime(state.minutesWatched)),
              Divider(color: t.rule, height: 1),
              _line(context, 'Queued up', spanOfTime(queued)),
              Divider(color: t.rule, height: 1),
              _line(
                context,
                'Of that, rewatching',
                spanOfTime(state.rewatchMinutes),
              ),
              if (unmeasured > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'The queue is short by $unmeasured '
                    '${unmeasured == 1 ? 'title' : 'titles'} — no runtime '
                    'yet, or a series still running with no episode count.',
                    style: Type.bodySm.copyWith(color: t.inkFaint),
                  ),
                ),
              const SizedBox(height: 22),
              const SectionLabel('Verdicts'),
              const SizedBox(height: 4),
              _line(
                context,
                rated == 0 ? 'Average rating' : 'Average of $rated ratings',
                avg == 0 ? '—' : '${avg.toStringAsFixed(1)} / 5',
              ),
              Divider(color: t.rule, height: 1),
              _line(context, 'Viewings logged', '${state.viewingsLogged}'),
              Divider(color: t.rule, height: 1),
              _line(context, 'Of those, rewatches', '${state.rewatches}'),
              Divider(color: t.rule, height: 1),
              _line(
                context,
                'Oldest thing seen',
                earliest == null ? '—' : '$earliest',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
