import 'package:flutter/material.dart';

class SharedStarRating extends StatelessWidget {
  const SharedStarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 24,
    this.filledColor,
    this.emptyColor,
  });
  final num value;
  final ValueChanged<int>? onChanged;
  final double size;
  final Color? filledColor, emptyColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: value == 0 ? 'Not rated' : 'Rated $value out of 5',
    child: Wrap(
      children: List.generate(5, (i) {
        final n = i + 1;
        return Semantics(
          button: onChanged != null,
          label: value == n ? 'Clear rating' : 'Rate $n out of 5',
          excludeSemantics: true,
          child: Tooltip(
            message: value == n ? 'Clear rating' : '$n out of 5',
            child: InkResponse(
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(value == n ? 0 : n),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  n <= value
                      ? Icons.star_rounded
                      : n - .5 <= value
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
                  size: size,
                  color: n - .5 <= value
                      ? filledColor ?? Theme.of(context).colorScheme.onSurface
                      : emptyColor ?? Theme.of(context).dividerColor,
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );
}
