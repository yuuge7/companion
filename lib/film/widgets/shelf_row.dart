import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models/shelf_entry.dart';
import '../theme.dart';
import 'leader_frame.dart';
import 'star_rating.dart';

/// One title on the shelf.
///
/// The row bleeds to both screen edges: the poster is a full-height block
/// on the left, and whatever this shelf actually wants doing is a flush
/// block on the right. What separates rows is a hairline, not a gap — so
/// scrolling reads as one continuous list rather than a stack of cards.
///
/// The right-hand block changes with what the thing is. A film is atomic:
/// there is one thing to do with it, so the block is one target. A series
/// is serial, so it gets a stepper — the same shape, counting episodes.
/// Once seen, either one affords only watching it again.
class ShelfRow extends StatelessWidget {
  // A poster is 2:3, so this pair is sized to it — the whole image fits with
  // little letterboxing, and the leader frame gets room for its perforations.
  static const posterWidth = 68.0;
  static const actionWidth = 56.0;
  static const minHeight = 102.0;

  final ShelfEntry item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMarkSeen;
  final VoidCallback onWatchAgain;
  final VoidCallback onUndoPlay;
  final void Function(int dir) onEpisode;
  final ValueChanged<String> onMove;
  final ValueChanged<int> onRate;
  final int? timeBudget;

  const ShelfRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onMarkSeen,
    required this.onWatchAgain,
    required this.onUndoPlay,
    required this.onEpisode,
    required this.onMove,
    required this.onRate,
    this.timeBudget,
  });

  Future<void> _openWatchUrl(BuildContext context) async {
    final uri = Uri.tryParse(item.watchUrl);
    final messenger = ScaffoldMessenger.of(context);
    if (uri == null || !uri.hasScheme) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'That link is not a valid web address. Edit the title '
            'to fix it.',
          ),
        ),
      );
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No app on this phone can open that link.'),
        ),
      );
    }
  }

  // --------------------------------------------------------------- poster

  Widget _poster(BuildContext context) {
    final leader = LeaderFrame(title: item.title, year: item.year);
    final art = item.posterUrl.isEmpty
        ? leader
        : CachedNetworkImage(
            imageUrl: item.posterUrl,
            // Contain, not cover: the whole image shows, never a crop of it.
            fit: BoxFit.contain,
            memCacheWidth:
                (posterWidth * MediaQuery.devicePixelRatioOf(context)).ceil(),
            fadeInDuration: Motion.of(context, Motion.state),
            // A poster this size leaves a conspicuous hole while it loads,
            // so the leader stands in for it. Failure lands on the same
            // thing.
            placeholder: (_, _) => leader,
            errorWidget: (_, _, _) => leader,
          );

    return Semantics(
      button: item.watchUrl.isNotEmpty,
      label: item.watchUrl.isEmpty
          ? 'Poster for ${item.title}'
          : 'Open ${item.title} where you watch it',
      child: GestureDetector(
        onTap: item.watchUrl.isEmpty ? null : () => _openWatchUrl(context),
        child: SizedBox(width: posterWidth, child: art),
      ),
    );
  }

  // --------------------------------------------------------------- action

  Widget _actionBlock(
    BuildContext context, {
    required int flex,
    required bool primary,
    required IconData icon,
    required double iconSize,
    required bool enabled,
    required String semanticLabel,
    required VoidCallback onTap,
    Color? tint,
    Border? border,
  }) {
    final t = context.tk;
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel,
        excludeSemantics: true,
        child: Material(
          color: enabled ? (primary ? t.raised : t.ground) : t.groundSunken,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: DecoratedBox(
              decoration: BoxDecoration(border: border),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: enabled ? (tint ?? t.ink) : t.inkGhost,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The stepper shape: one big primary block, one small undo beneath it.
  Widget _stepper(
    BuildContext context, {
    required IconData icon,
    required String primaryLabel,
    required VoidCallback onPrimary,
    required String undoLabel,
    required bool canUndo,
    required VoidCallback onUndo,
  }) {
    final t = context.tk;
    return SizedBox(
      width: actionWidth,
      child: Column(
        children: [
          _actionBlock(
            context,
            flex: 5,
            primary: true,
            icon: icon,
            iconSize: 21,
            enabled: true,
            semanticLabel: primaryLabel,
            onTap: onPrimary,
            border: Border(left: BorderSide(color: t.rule)),
          ),
          _actionBlock(
            context,
            flex: 4,
            primary: false,
            icon: Icons.remove_rounded,
            iconSize: 16,
            enabled: canUndo,
            tint: t.inkFaint,
            semanticLabel: undoLabel,
            onTap: onUndo,
            border: Border(
              left: BorderSide(color: t.rule),
              top: BorderSide(color: t.rule),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final t = context.tk;

    if (item.isSeen) {
      return _stepper(
        context,
        icon: Icons.replay_rounded,
        primaryLabel: 'Log another time through ${item.title}',
        onPrimary: onWatchAgain,
        undoLabel: 'Take back a viewing of ${item.title}',
        canUndo: item.plays > 1,
        onUndo: onUndoPlay,
      );
    }

    // A series is serial, so the block counts episodes. Reaching the last
    // one moves the whole thing to seen, which is why there is no separate
    // "finished" control here.
    if (item.isSeries) {
      return _stepper(
        context,
        icon: Icons.add_rounded,
        primaryLabel: 'Log episode ${item.watched + 1} of ${item.title}',
        onPrimary: () => onEpisode(1),
        undoLabel: 'Take back episode ${item.watched} of ${item.title}',
        canUndo: item.watched > 0,
        onUndo: () => onEpisode(-1),
      );
    }

    // A film is atomic: there is exactly one thing to do with it, so it
    // gets the whole block rather than being split with a control that
    // would have nothing to count.
    return SizedBox(
      width: actionWidth,
      child: Column(
        children: [
          _actionBlock(
            context,
            flex: 1,
            primary: true,
            icon: Icons.check_rounded,
            iconSize: 22,
            enabled: true,
            semanticLabel: 'Mark ${item.title} as seen',
            onTap: onMarkSeen,
            border: Border(left: BorderSide(color: t.rule)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- content

  Widget _title(BuildContext context) {
    final t = context.tk;
    final linked = item.watchUrl.isNotEmpty;
    return Semantics(
      button: linked,
      label: linked ? 'Open ${item.title} where you watch it' : null,
      child: GestureDetector(
        onTap: linked ? () => _openWatchUrl(context) : null,
        behavior: HitTestBehavior.opaque,
        // Matches the height of the menu button beside it, so a one-line
        // title is still a full-size target. Costs no extra row height.
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              text: item.title,
              children: linked
                  ? [
                      const TextSpan(text: ' '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                          Icons.north_east_rounded,
                          size: 13,
                          color: t.inkFaint,
                        ),
                      ),
                    ]
                  : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Type.title.copyWith(color: t.ink),
          ),
        ),
      ),
    );
  }

  /// What one sitting costs. The accent lives here and nowhere else — and
  /// the unit is what keeps it honest across a film and an episode.
  Widget _runtime(BuildContext context) {
    final t = context.tk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          item.hasRuntime ? '${item.runtime}' : '—',
          style: Type.number.copyWith(
            color: item.hasRuntime ? t.accent : t.inkGhost,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Text(
            runtimeUnit(series: item.isSeries),
            style: Type.numberSm.copyWith(
              color: item.hasRuntime ? t.inkFaint : t.inkGhost,
            ),
          ),
        ),
      ],
    );
  }

  Widget _badge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(R.badge),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: Type.numberSm.copyWith(fontSize: 11, color: color),
      ),
    );
  }

  /// Wraps a badge so it slides when the number behind it changes — the
  /// one bit of motion a tap on this row can cause.
  Widget _tickingBadge(BuildContext context, String text, Color color) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.micro),
      switchInCurve: Motion.curve,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(text),
        child: _badge(context, text, color),
      ),
    );
  }

  Widget _overflow(BuildContext context) {
    final t = context.tk;
    return SizedBox(
      width: 44,
      height: 44,
      child: PopupMenuButton<String>(
        tooltip: 'More actions for ${item.title}',
        icon: Icon(Icons.more_horiz_rounded, size: 18, color: t.inkFaint),
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'delete':
              onDelete();
            default:
              onMove(value);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', height: 44, child: Text('Edit')),
          for (final (id, label) in const [
            ('watchlist', 'Move to watchlist'),
            ('seen', 'Move to seen'),
            ('bailed', 'Move to bailed'),
          ])
            if (item.status != id)
              PopupMenuItem(value: id, height: 44, child: Text(label)),
          PopupMenuItem(
            value: 'delete',
            height: 44,
            child: Text('Delete', style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final seen = item.isSeen;
    final credits = provenance(year: item.year, director: item.director);
    final note = item.note.trim();
    final logged = seen
        ? watchedStamp(item.watchedAt, item.watchedPrecision)
        : '';
    final episodes = item.isSeries
        ? '${item.seasonProgress.isEmpty ? '' : '${item.seasonProgress} · '}${episodeLine(watched: item.watched, episodes: item.episodes)}'
        : '';

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        // Content determines height once. Positioned art and controls fill
        // that height without an intrinsic measurement of every text span.
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                posterWidth + 13,
                9,
                actionWidth + 4,
                10,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _title(context)),
                      _overflow(context),
                    ],
                  ),
                  if (credits.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1, bottom: 2),
                      child: Text(
                        credits,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.meta.copyWith(color: t.inkFaint),
                      ),
                    ),
                  const SizedBox(height: 6),
                  // Figures on the baseline, the log stamp at the right
                  // margin — the Wrap absorbs a large text scale without
                  // pushing the stamp off the row.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _runtime(context),
                            if (episodes.isNotEmpty)
                              _tickingBadge(context, episodes, t.inkMuted),
                            if (item.plays > 1)
                              _tickingBadge(
                                context,
                                'SEEN ${item.plays}×',
                                t.inkMuted,
                              ),
                            if (seen)
                              StarRating(value: item.rating, onChanged: onRate),
                          ],
                        ),
                      ),
                      if (logged.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            logged,
                            style: Type.meta.copyWith(color: t.inkGhost),
                          ),
                        ),
                    ],
                  ),
                  if (seen && note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 8),
                      child: Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.bodySm.copyWith(color: t.inkMuted),
                      ),
                    ),
                  if (item.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        item.tags.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.meta.copyWith(color: t.inkFaint),
                      ),
                    ),
                  if (timeBudget != null && item.isSeries && item.hasRuntime)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${item.episodesThatFit(timeBudget!)} episodes fit · ${item.nextEpisode}',
                        style: Type.meta.copyWith(color: t.inkMuted),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: posterWidth,
              child: _poster(context),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: actionWidth,
              child: _action(context),
            ),
          ],
        ),
      ),
    );
  }
}
