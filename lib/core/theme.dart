import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../books/theme/tokens.dart';
import '../film/tokens.dart' as film;
import '../manga/tokens.dart' as manga;
import 'design.dart';

/// The feature token extensions are compatibility adapters, never separate themes.
ThemeData buildCompanionTheme(Brightness brightness, {ColorScheme? scheme}) {
  final c = scheme == null
      ? (brightness == Brightness.dark ? LedgerColors.dark : LedgerColors.light)
      : LedgerColors.fromScheme(scheme);
  final colors =
      scheme ??
      ColorScheme(
        brightness: brightness,
        primary: c.ink,
        onPrimary: c.onInk,
        secondary: c.accent,
        onSecondary: c.onInk,
        surface: c.ground,
        onSurface: c.ink,
        surfaceContainerLow: c.panel,
        surfaceContainer: c.panel,
        surfaceContainerHigh: c.panel,
        surfaceContainerHighest: c.well,
        onSurfaceVariant: c.inkMuted,
        outline: c.ruleStrong,
        outlineVariant: c.rule,
        error: c.danger,
        onError: c.onInk,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: CompanionFonts.body,
    colorScheme: colors,
  );
  return base.copyWith(
    extensions: [
      c,
      manga.AppTokens(
        ground: c.ground,
        groundSunken: c.well,
        surface: c.panel,
        surfaceAlt: c.well,
        rule: c.rule,
        ruleStrong: c.ruleStrong,
        ink: c.ink,
        inkMuted: c.inkMuted,
        inkFaint: c.inkMuted,
        inkGhost: c.inkFaint,
        accent: c.accent,
        accentQuiet: c.well,
        onAccent: c.onInk,
        done: c.accent,
        danger: c.danger,
        raised: c.panel,
      ),
      film.AppTokens(
        ground: c.ground,
        groundSunken: c.well,
        surface: c.panel,
        surfaceAlt: c.well,
        rule: c.rule,
        ruleStrong: c.ruleStrong,
        ink: c.ink,
        inkMuted: c.inkMuted,
        inkFaint: c.inkMuted,
        inkGhost: c.inkFaint,
        accent: c.accent,
        accentQuiet: c.well,
        onAccent: c.onInk,
        danger: c.danger,
        raised: c.panel,
      ),
    ],
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    dividerColor: c.rule,
    textTheme: base.textTheme.copyWith(
      headlineSmall: CompanionType.heading.copyWith(fontSize: 24, color: c.ink),
      headlineMedium: CompanionType.heading.copyWith(
        fontSize: 28,
        color: c.ink,
      ),
      titleLarge: CompanionType.heading.copyWith(color: c.ink),
      titleMedium: CompanionType.title.copyWith(color: c.ink),
      titleSmall: CompanionType.title.copyWith(fontSize: 15, color: c.ink),
      bodyLarge: CompanionType.body.copyWith(fontSize: 16, color: c.ink),
      bodyMedium: CompanionType.body.copyWith(color: c.ink),
      bodySmall: CompanionType.small.copyWith(color: c.inkMuted),
      labelLarge: CompanionType.body.copyWith(
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: CompanionType.heading.copyWith(color: c.ink),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.inkMuted, size: 22),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: CompanionType.body.copyWith(color: c.inkMuted),
      hintStyle: CompanionType.body.copyWith(color: c.inkFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.ink, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: c.ink,
        foregroundColor: c.onInk,
        shape: shape,
        textStyle: CompanionType.body.copyWith(fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: c.ink,
        side: BorderSide(color: c.ruleStrong),
        shape: shape,
        textStyle: CompanionType.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: c.ink,
        shape: shape,
        textStyle: CompanionType.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.ink,
      foregroundColor: c.onInk,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      shape: shape,
      extendedTextStyle: CompanionType.body.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.panel,
      selectedColor: c.ink,
      labelStyle: CompanionType.small.copyWith(fontWeight: FontWeight.w600),
      shape: shape,
      side: BorderSide(color: c.rule),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: CompanionType.heading.copyWith(
        fontSize: 20,
        color: c.ink,
      ),
      contentTextStyle: CompanionType.body.copyWith(color: c.inkMuted),
      elevation: 0,
      shape: shape,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
      textStyle: CompanionType.body.copyWith(color: c.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      actionTextColor: c.onInk,
      contentTextStyle: CompanionType.body.copyWith(color: c.onInk),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: shape,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.well,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => CompanionType.small.copyWith(
          color: states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: c.ink)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.panel,
      indicatorColor: c.well,
      selectedLabelTextStyle: CompanionType.small.copyWith(
        color: c.ink,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: CompanionType.small.copyWith(color: c.inkMuted),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.well,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionColor: c.accent.withValues(alpha: .2),
      selectionHandleColor: c.ink,
    ),
  );
}
