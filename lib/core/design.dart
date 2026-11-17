import 'package:flutter/material.dart';

/// One visual vocabulary for every library and its supporting screens.
abstract final class CompanionFonts {
  static const display = 'PlexSans';
  static const body = 'PlexSans';
  static const utility = 'PlexMono';
}

abstract final class CompanionType {
  static const heading = TextStyle(
    fontFamily: CompanionFonts.display,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -.35,
    height: 1.25,
  );
  static const title = TextStyle(
    fontFamily: CompanionFonts.body,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const body = TextStyle(
    fontFamily: CompanionFonts.body,
    fontSize: 14,
    height: 1.45,
  );
  static const small = TextStyle(
    fontFamily: CompanionFonts.body,
    fontSize: 12,
    height: 1.4,
  );
  static const number = TextStyle(
    fontFamily: CompanionFonts.utility,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
