import 'package:flutter/material.dart';

import '../../core/widgets/sheet.dart';
import '../theme.dart';

class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showHeader = true,
  });
  final String title;
  final Widget child;
  final bool showHeader;
  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SharedSheet(
      title: title,
      titleStyle: Type.display.copyWith(color: t.ink),
      ruleColor: t.rule,
      closeColor: t.inkMuted,
      showHeader: showHeader,
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Type.eyebrow.copyWith(color: context.tk.inkFaint),
    );
  }
}

/// The form field label, sitting on the same ruled baseline as its input.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SectionLabel(text),
    );
  }
}
