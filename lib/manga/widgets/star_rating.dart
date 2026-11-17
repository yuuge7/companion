import 'package:flutter/material.dart';

import '../../core/widgets/star_rating.dart';
import '../theme.dart';

class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 24,
  });
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SharedStarRating(
      value: value,
      onChanged: onChanged,
      size: size,
      filledColor: t.ink,
      emptyColor: t.ruleStrong,
    );
  }
}
