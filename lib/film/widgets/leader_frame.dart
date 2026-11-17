import 'package:flutter/material.dart';

import '../theme.dart';

/// What a film looks like before its poster arrives — or when it never
/// does.
///
/// Rather than a blank rectangle, the frame borrows the Academy leader that
/// used to run at the head of every print: sprocket holes down both edges,
/// a crosshair through the gate, and a number ringed in the middle. The
/// number here is the year, so a missing poster still tells you something
/// the row would otherwise have to repeat.
class LeaderFrame extends StatelessWidget {
  final String title;
  final int? year;

  const LeaderFrame({super.key, required this.title, this.year});

  /// Stock tint, chosen by the title so a given film always comes back the
  /// same colour.
  Color get tint {
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return AppTokens.leaderTints[hash % AppTokens.leaderTints.length];
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      isComplex: true,
      painter: _LeaderPainter(
        tint: tint,
        label: (year != null && year! > 0) ? '$year' : '',
      ),
      // The painter draws to whatever it is given; nothing here reports an
      // intrinsic size, so a long title can never stretch the row.
      child: const SizedBox.expand(),
    );
  }
}

class _LeaderPainter extends CustomPainter {
  final Color tint;
  final String label;

  _LeaderPainter({required this.tint, required this.label});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = tint);

    // Sprocket holes. Punched, so they are darker than the stock rather
    // than lighter.
    final holeW = w * 0.058;
    final holeH = holeW * 1.65;
    final pitch = holeH * 2.1;
    final inset = w * 0.045;
    final holePaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.46);
    for (var y = pitch * 0.4; y + holeH < h; y += pitch) {
      for (final x in [inset, w - inset - holeW]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, holeW, holeH),
            Radius.circular(holeW * 0.3),
          ),
          holePaint,
        );
      }
    }

    // The gate: everything between the two perforated edges.
    final gateLeft = inset * 2 + holeW;
    final gateRight = w - gateLeft;
    final cx = w / 2;
    final cy = h / 2;

    final hair = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(gateLeft, cy), Offset(gateRight, cy), hair);
    canvas.drawLine(Offset(cx, 0), Offset(cx, h), hair);

    final radius = (gateRight - gateLeft) * 0.42;
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.32)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke,
    );

    if (label.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: Type.meta.copyWith(
          fontSize: radius * 0.68,
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.84),
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // The ring is drawn to fit four digits; if a caller ever hands it
    // something wider, let the text win and skip the ring's inner margin.
    painter.paint(
      canvas,
      Offset(cx - painter.width / 2, cy - painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_LeaderPainter old) =>
      old.tint != tint || old.label != label;
}
