import 'package:flutter/material.dart';

class SharedSheet extends StatelessWidget {
  const SharedSheet({
    super.key,
    required this.title,
    required this.child,
    required this.titleStyle,
    required this.ruleColor,
    required this.closeColor,
    this.showHeader = true,
  });
  final String title;
  final Widget child;
  final TextStyle titleStyle;
  final Color ruleColor, closeColor;
  final bool showHeader;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ruleColor)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: closeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Flexible(child: child),
      ],
    ),
  );
}
