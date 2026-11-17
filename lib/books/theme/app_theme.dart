import 'package:flutter/material.dart';

import '../../core/theme.dart';

abstract final class AppTheme {
  static ThemeData light() => buildCompanionTheme(Brightness.light);
  static ThemeData dark() => buildCompanionTheme(Brightness.dark);
  static ThemeData fromScheme(ColorScheme scheme) =>
      buildCompanionTheme(scheme.brightness, scheme: scheme);
}
