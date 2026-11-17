import 'package:flutter/material.dart';

import '../core/design.dart';

/// Design tokens for the "Booth" direction.
///
/// The room is warm and dark — bitumen with a plum cast in the dark theme,
/// a warm neutral lobby grey in the light one. The light coming off the
/// screen is cold. That opposition is the whole palette: warm room, cold
/// beam. Structure is carried by hairline rules, never by elevation.
///
/// The accent (beam blue) has exactly one meaning: how long a film takes.
/// It is allowed on the runtime numeral and nowhere else — not on
/// navigation, headings, buttons, ratings, or poster art.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  // Ground and surfaces.
  final Color ground;
  final Color groundSunken;
  final Color surface;
  final Color surfaceAlt;
  final Color rule;
  final Color ruleStrong;

  // Ink.
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color inkGhost;

  // Meaningful colour.
  final Color accent; // runtime, only
  final Color accentQuiet; // accent at low emphasis, e.g. text selection
  final Color onAccent;
  final Color danger;

  /// The watched/rewatch block: a control panel lifted off the row. In both
  /// themes it reads as raised, because the app's primary action must never
  /// be the least visible thing on the row.
  final Color raised;

  const AppTokens({
    required this.ground,
    required this.groundSunken,
    required this.surface,
    required this.surfaceAlt,
    required this.rule,
    required this.ruleStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkGhost,
    required this.accent,
    required this.accentQuiet,
    required this.onAccent,
    required this.danger,
    required this.raised,
  });

  /// The auditorium: lights down, screen on.
  static const dark = AppTokens(
    ground: Color(0xFF1A151C),
    groundSunken: Color(0xFF131016),
    surface: Color(0xFF241F27),
    surfaceAlt: Color(0xFF2B252E),
    rule: Color(0xFF362E3A),
    ruleStrong: Color(0xFF483E4C),
    ink: Color(0xFFEDE7E4),
    inkMuted: Color(0xFFB3A9B1),
    inkFaint: Color(0xFF918694),
    inkGhost: Color(0xFF695F6D),
    accent: Color(0xFF9DB4F2),
    accentQuiet: Color(0xFF4C5680),
    onAccent: Color(0xFF12101A),
    danger: Color(0xFFDB7A70),
    raised: Color(0xFF332C39),
  );

  /// The lobby: same room with the house lights up.
  static const light = AppTokens(
    ground: Color(0xFFE7E3E4),
    groundSunken: Color(0xFFD9D4D6),
    surface: Color(0xFFF4F1F2),
    surfaceAlt: Color(0xFFDFDADC),
    rule: Color(0xFFCAC3C6),
    ruleStrong: Color(0xFFA9A0A5),
    ink: Color(0xFF1B171C),
    inkMuted: Color(0xFF4E4753),
    inkFaint: Color(0xFF5F5765),
    inkGhost: Color(0xFF877E8C),
    accent: Color(0xFF31408C),
    accentQuiet: Color(0xFF7B86C4),
    onAccent: Color(0xFFF7F5F6),
    danger: Color(0xFFA33A31),
    raised: Color(0xFFFBFAFA),
  );

  /// Leader tints for films with no poster. Hand-picked, not generated:
  /// six film-stock casts — the colours a frame goes when the emulsion,
  /// the print or the projector bulb is having an opinion.
  static const leaderTints = <Color>[
    Color(0xFF3B464C), // silver halide
    Color(0xFF503E31), // sepia print
    Color(0xFF33463C), // technicolor green
    Color(0xFF473341), // magenta fade
    Color(0xFF4E4029), // tungsten
    Color(0xFF344049), // day-for-night
  ];

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) =>
      t < 0.5 ? this : (other as AppTokens? ?? this);
}

extension TokensOf on BuildContext {
  AppTokens get tk => Theme.of(this).extension<AppTokens>()!;
}

/// Radius scale. Structure is square — a frame has corners; only controls
/// are softened.
abstract class R {
  static const badge = Radius.circular(2);
  static const control = Radius.circular(5);
  static const sheet = Radius.circular(12);
}

/// Motion. Two things animate in this app: the rewatch tally when it
/// changes, and a poster fading in once it loads.
abstract class Motion {
  static const micro = Duration(milliseconds: 140);
  static const state = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  /// Honours the platform "remove animations" accessibility setting.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

abstract class Faces {
  /// Oswald. Condensed signage — it names films and shouts headings, and
  /// its narrow set width is why a three-word title still fits one line.
  static const marquee = 'Marquee';

  /// Archivo. The grotesque that explains things.
  static const body = CompanionFonts.body;

  /// DM Mono. Counts things, with tabular figures.
  static const readout = 'Readout';
}

/// Type scale. Face is tied to role: the marquee names things, the
/// grotesque explains things, the readout counts things.
abstract class Type {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Sheet titles and the wordmark. Set in caps with wide tracking
  /// wherever it appears — that is the marquee.
  static const display = CompanionType.heading;

  /// A film title, on a row.
  static const title = CompanionType.title;

  static const body = TextStyle(
    fontFamily: Faces.body,
    fontSize: 14,
    height: 1.45,
  );

  static const bodySm = TextStyle(
    fontFamily: Faces.body,
    fontSize: 13,
    height: 1.45,
  );

  /// Button and control text.
  static const label = TextStyle(
    fontFamily: Faces.body,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// How long the film takes. The one place the accent is allowed.
  static const number = TextStyle(
    fontFamily: Faces.readout,
    fontSize: 21,
    fontWeight: FontWeight.w500,
    height: 1.0,
    letterSpacing: -0.6,
    fontFeatures: _tabular,
  );

  static const numberSm = TextStyle(
    fontFamily: Faces.readout,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.0,
    fontFeatures: _tabular,
  );

  /// Years, directors, timestamps — anything catalogued or measured.
  static const meta = TextStyle(
    fontFamily: Faces.readout,
    fontSize: 11.5,
    height: 1.25,
    letterSpacing: 0.1,
    fontFeatures: _tabular,
  );

  /// Section and band headings. Marquee caps, tracked wide.
  static const eyebrow = TextStyle(
    fontFamily: Faces.marquee,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 1.6,
  );
}
