import 'package:flutter/material.dart';

import 'tokens.dart';

/// Typography, transcribed from `docs/ui-spec.md` §1.1.
///
/// **Only weights 400 and 500 exist.** `FontWeight.w600` and above synthesise
/// fake bold, which on a television reads as a rendering fault rather than as
/// emphasis. Every "bold" in this application is [medium].
abstract final class Type {
  static const family = 'Space Grotesk';

  /// Used when Space Grotesk has no glyph — CJK titles, unusual punctuation in
  /// a film name. Without a fallback list those render as tofu.
  static const fallback = ['Segoe UI', 'Noto Sans', 'DejaVu Sans'];

  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;

  /// CSS letter-spacing is in `em`; Flutter's is in logical pixels. Sizes in
  /// the spec are given with `em` tracking, so convert rather than baking in
  /// pre-multiplied constants that stop meaning anything if a size changes.
  static double tracking(double em, double fontSize) => em * fontSize;

  /// Body tracking, `-0.005em`.
  static const bodyEm = -0.005;

  /// Heading tracking, `-0.02em`.
  static const headingEm = -0.02;

  static TextStyle _base(
    double size,
    FontWeight weight,
    double em,
    double height,
  ) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: tracking(em, size),
  );

  /// A style at a size given in the spec's own `rem` figures.
  ///
  /// `docs/ui-spec.md` quotes nearly every size as a `rem` value, and the root
  /// font size is never set — so `1rem` is 16px even though body text renders at
  /// 18px. This exists so those figures can be transcribed literally instead of
  /// pre-multiplied into magic numbers nobody can trace back to the spec.
  static TextStyle rem(
    double rems, {
    FontWeight weight = regular,
    double em = bodyEm,
    double height = 1.45,
  }) => _base(rems * 16, weight, em, height);

  /// A style at an explicit pixel size, for the handful of places the spec gives
  /// one — body text, the logo wordmark, a viewport-derived title.
  static TextStyle px(
    double size, {
    FontWeight weight = regular,
    double em = bodyEm,
    double height = 1.45,
  }) => _base(size, weight, em, height);

  /// 18px — the body size the whole interface is calibrated against.
  static TextStyle get body => px(18);

  /// 18px at weight 500, for a row's own name against its dimmed value.
  static TextStyle get bodyMedium => px(18, weight: medium);

  /// `1.05rem` — shelf headings, library tile names, settings section titles.
  static TextStyle get heading => rem(1.05, weight: medium, em: headingEm);

  /// `0.95rem` — pills and other chrome.
  static TextStyle get label => rem(0.95, weight: medium);

  /// A screen title.
  static TextStyle get title => px(34, weight: medium, em: headingEm);

  /// A detail screen's film or series name.
  static TextStyle get display => px(56, weight: medium, em: headingEm);
}

/// Provides [GlassfinTokens] to the widget tree.
///
/// Widgets read `context.tokens`. Nothing reads [GlassfinTokens.dark] or
/// [GlassfinTokens.light] directly — that is what makes the theme switchable.
class GlassfinTheme extends InheritedWidget {
  const GlassfinTheme({required this.tokens, required super.child, super.key});

  final GlassfinTokens tokens;

  static GlassfinTokens of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<GlassfinTheme>();
    assert(theme != null, 'No GlassfinTheme in the tree above this widget.');
    return theme!.tokens;
  }

  @override
  bool updateShouldNotify(GlassfinTheme oldWidget) =>
      tokens != oldWidget.tokens;

  /// The Material theme underneath. Glassfin draws almost nothing with Material
  /// widgets, so this exists to make the defaults harmless — the right font, the
  /// right background, and no Material focus or splash decoration fighting the
  /// app's own focus treatment.
  static ThemeData materialTheme(GlassfinTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.accent,
      brightness: tokens.brightness,
      surface: tokens.ground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: scheme,
      fontFamily: Type.family,
      fontFamilyFallback: Type.fallback,
      scaffoldBackgroundColor: tokens.ground,
      canvasColor: tokens.ground,
      // Focus is drawn by the app, never by the platform: a Material focus
      // highlight or an ink splash next to a scaled card and a 3px ring reads as
      // two competing indicators.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      splashColor: Colors.transparent,
      textTheme: TextTheme(
        bodyLarge: Type.body,
        bodyMedium: Type.body,
        titleMedium: Type.heading,
        titleLarge: Type.title,
        labelLarge: Type.label,
      ).apply(bodyColor: tokens.ink, displayColor: tokens.ink),
    );
  }
}

extension TokensContext on BuildContext {
  GlassfinTokens get tokens => GlassfinTheme.of(this);
}
