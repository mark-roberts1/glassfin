/// The colour system, transcribed from `docs/ui-spec.md` §1.2–1.5.
///
/// This is the only file in the application permitted to name a colour. It is
/// structured in three layers, and the distinction between them is load-bearing:
///
///  * [_Brand] — the style guide's own palette. **Never referenced by a widget.**
///  * [GlassfinTokens] — role tokens, redefined per theme. This is what widgets use.
///  * The `over*` fields — theme-invariant, for anything drawn over video or artwork.
library;

import 'package:flutter/widgets.dart';

/// The style guide's palette. Private on purpose: widgets name roles, not brand
/// colours, so that light mode is a matter of swapping one token set.
abstract final class _Brand {
  static const ink = Color(0xFF0E1518);
  static const paper = Color(0xFFF5F3EE);
  static const lead = Color(0xFFC68331);
  static const silver = Color(0xFF7A9D8F);
  static const trail = Color(0xFF5697DE);
  static const accent = Color(0xFFD5A051);

  /// Mist proper (`#7c8a90`) is not a role token anywhere: at 3.2:1 on paper it
  /// is fine on a printed sheet and not fine as hint text seen from three
  /// metres, so light's `inkFaint` is a darkened derivation of it instead.
  static const mistLight = Color(0xFF8DA0A8);
  static const tile = Color(0xFFE7E4DB);
  static const night = Color(0xFF0B1114);
}

/// One theme's worth of role tokens.
///
/// Light is **not an inversion** of dark: the shadows get lighter and shallower,
/// two colours are chosen for contrast rather than brand fidelity (see
/// [accentText] and [inkFaint]), and the `over*` family does not change at all.
@immutable
class GlassfinTokens {
  const GlassfinTokens({
    required this.ground,
    required this.raised,
    required this.edge,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.accent,
    required this.accentText,
    required this.danger,
    required this.focusRing,
    required this.ambientOpacity,
    required this.veilNear,
    required this.veilMid,
    required this.shadowFocus,
    required this.shadowLift,
    required this.shadowPoster,
    required this.fins,
    required this.brightness,
  });

  /// The page background.
  final Color ground;

  /// Panels, pills, settings rows — anything sitting a step above [ground].
  final Color raised;

  /// Hairline borders. Always a low-alpha [ink], never a solid grey.
  final Color edge;

  /// Body text, and the inverted surface of a primary action.
  final Color ink;

  /// Secondary text: shelf headings, settings values, metadata.
  final Color inkDim;

  /// Hint text. In light this is the guide's Mist darkened ~14% — Mist itself
  /// lands at 3.2:1 on paper, which is fine on a printed sheet and not fine as
  /// hint text seen from three metres.
  final Color inkFaint;

  /// Accent fills. Light uses Lead rather than Accent.
  final Color accent;

  /// Accent *text*, which is a different problem from accent fills: gold on
  /// white is far harder than gold on black, so light uses a deeper gold
  /// (4.5:1) where Lead would manage only 2.8:1.
  final Color accentText;

  /// Destructive actions — Sign out, errors.
  final Color danger;

  /// The focus ring.
  ///
  /// **Trail, not the page's ink.** The guide's blue is the one brand colour
  /// with no other job in the interface, which is exactly what a system signal
  /// wants: focus stops competing with content colour and cannot be mistaken
  /// for part of the artwork it surrounds. Light uses a deepened Trail —
  /// #5697DE manages only 2.75:1 on paper, below the 3:1 a non-text indicator
  /// needs, while the deeper mix reaches 3.9:1.
  final Color focusRing;

  /// Peak opacity of the ambient backdrop.
  final double ambientOpacity;

  /// The two stops of the ambient veil that tints every screen's left edge and
  /// bottom. See `docs/ui-spec.md` §1.9.
  final double veilNear;
  final double veilMid;

  /// Cast under a focused element, a lifted key, and a poster respectively.
  final List<BoxShadow> shadowFocus;
  final List<BoxShadow> shadowLift;
  final List<BoxShadow> shadowPoster;

  /// The twelve facet colours of the logo mark, warm to cool. The theme
  /// redefines these; see `docs/ui-spec.md` §4.4.
  final List<Color> fins;

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  // ---------------------------------------------------------------------------
  // The primary action.
  //
  // Derived rather than stored: these are compositions of the role tokens above,
  // and writing them as fields would mean two more entries in each theme that
  // could drift apart from the gold they are made of.
  //
  // **Outlined, not filled.** The near-white primary Glassfin started with was
  // inherited from the old Svelte app's `.primary { background: var(--ink) }` —
  // it was never from the style guide, which is an identity guide and says
  // nothing about buttons. Filling the largest control on the screen with the
  // brightest colour in the palette makes it the brightest *object* in a dark
  // room, which is the one thing a television interface cannot afford. A gold
  // rule and a gold label on [raised] carries the same "this is the thing you
  // came to do" without anything on screen exceeding the brightness of body
  // text. Four treatments were trialled on the actual panel; this one won.
  // ---------------------------------------------------------------------------

  /// The surface of a primary action: [raised], the same as any other button.
  /// The signal is the gold, not the fill.
  Color get primaryFill => raised;

  /// Its label — [accentText], which is one of the two places gold appears as
  /// text.
  Color get primaryInk => accentText;

  /// Its rule. [accentText] rather than [accent] so the rule and the label are
  /// the same gold: in dark they are already the same colour, and in light the
  /// deeper gold takes the boundary from 2.5:1 against `raised` to 4.5:1.
  Color get primaryBorder => accentText;

  // ---------------------------------------------------------------------------
  // The over* family — identical in both themes.
  //
  // A photograph has no light mode. The transport, the track menu, the skip
  // prompt, the overlay, the wash and name on a library tile, and the resume bar
  // and watched tick on a card are all read against artwork, so they stay dark
  // whatever the page is doing. Getting this wrong looks fine in review and is
  // unreadable the moment a film starts.
  // ---------------------------------------------------------------------------

  /// Full-bleed dimming behind a modal.
  static const overScrim = Color(0xDB0B1114); // rgba(11,17,20,0.86)

  /// Panels floating over video: the transport, the track menu.
  static const overPanel = Color(0xEB162026); // rgba(22,32,38,0.92)

  /// A wash over artwork, so text on top of it stays legible.
  static const overArtwork = Color(0x8C0B1114); // rgba(11,17,20,0.55)

  static const overEdge = Color(0x24F5F3EE); // rgba(245,243,238,0.14)
  static const overInk = Color(0xFFF5F3EE);

  /// Content drawn *on* [overInk] — the glyph inside a card's watched tick, and
  /// the label on an accent-filled button. Brand Night, and fixed like
  /// everything else in this family.
  static const overOnInk = _Brand.night;

  /// The focused surface of anything drawn over the film: the circle behind a
  /// transport control, the lit row in a track menu.
  ///
  /// **Nothing over the film takes a focus ring.** A rectangle drawn around
  /// every control is what a page does, and the transport is not a page — it is
  /// a row of glyphs on a photograph. Focus there is carried by scale and by
  /// this wash, which is the reference client's own answer.
  ///
  /// Translucent Paper, and safe at this alpha because the transport lays a
  /// near-black gradient over the picture before any of it is drawn — the
  /// backdrop is dark whatever the film is doing.
  static const overHighlight = Color(0x2EF5F3EE); // rgba(245,243,238,0.18)

  static const overInkDim = Color(0xA3F5F3EE); // rgba(245,243,238,0.64)
  static const overInkFaint = Color(0xFF8DA0A8);
  static const overAccent = Color(0xFFD5A051);
  static const overDanger = Color(0xFFE0908C);

  /// The dark end of the transport's gradient — `rgba(0,0,0,0.92)`. Pure black
  /// rather than Night, because it fades into the film itself rather than into
  /// any surface of ours.
  static const overVideoScrim = Color(0xEB000000);

  /// The unplayed part of the scrub bar — `rgba(255,255,255,0.22)`. Neutral
  /// white, so it does not tint against whatever the frame behind it is doing.
  static const overTrack = Color(0x38FFFFFF);

  /// The wash that carries a Home library tile's name. Fixed dark in both
  /// themes, like everything else that sits on artwork.
  static const overTileVeil = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xD90B1114), // rgba(11,17,20,0.85)
      Color(0x260B1114), // rgba(11,17,20,0.15)
    ],
    stops: [0.12, 0.7],
  );

  // ---------------------------------------------------------------------------
  // The two themes.
  //
  // Dark is the default, not "follow the system". A television in a dark room is
  // the case to be right about, and most shells have no palette preference worth
  // consulting.
  // ---------------------------------------------------------------------------

  static const dark = GlassfinTokens(
    brightness: Brightness.dark,
    ground: _Brand.night,
    raised: Color(0xFF162026),
    edge: Color(0x1AF5F3EE), // rgba(245,243,238,0.10)
    ink: _Brand.paper,
    inkDim: Color(0xA3F5F3EE), // rgba(245,243,238,0.64)
    inkFaint: _Brand.mistLight,
    accent: _Brand.accent,
    accentText: _Brand.accent,
    danger: Color(0xFFE0908C),
    focusRing: _Brand.trail,
    ambientOpacity: 0.28,
    veilNear: 0.35,
    veilMid: 0.78,
    shadowFocus: [
      BoxShadow(
        offset: Offset(0, 18),
        blurRadius: 44,
        color: Color(0xB3000000),
      ),
    ],
    shadowLift: [
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 24,
        color: Color(0x99000000),
      ),
    ],
    shadowPoster: [
      BoxShadow(
        offset: Offset(0, 24),
        blurRadius: 60,
        color: Color(0x99000000),
      ),
    ],
    // dart format off
    fins: [
      Color(0xFFF4B46D), Color(0xFFE0BE76), Color(0xFFCDC586), Color(0xFFBEC998),
      Color(0xFFB4CBA9), Color(0xFFB1CAB6), Color(0xFFABCBBE), Color(0xFF9DCEC7),
      Color(0xFF8ED0D5), Color(0xFF83D0E6), Color(0xFF81CDF9), Color(0xFF95C7FF),
    ],
    // dart format on
  );

  static const light = GlassfinTokens(
    brightness: Brightness.light,
    ground: _Brand.paper,
    raised: _Brand.tile,
    edge: Color(0x240E1518), // rgba(14,21,24,0.14)
    ink: _Brand.ink,
    inkDim: Color(0xA80E1518), // rgba(14,21,24,0.66)
    inkFaint: Color(0xFF6B777C), // Mist darkened ~14%
    accent: _Brand.lead,
    accentText: Color(0xFF986424), // deeper than Lead, for 4.5:1 on paper
    danger: Color(0xFFA6323F),
    focusRing: Color(0xFF3F7CBF), // Trail deepened, for 3.9:1 on paper
    ambientOpacity: 0.16,
    veilNear: 0.62,
    veilMid: 0.90,
    shadowFocus: [
      BoxShadow(
        offset: Offset(0, 14),
        blurRadius: 32,
        color: Color(0x2E0E1518),
      ),
    ],
    shadowLift: [
      BoxShadow(offset: Offset(0, 8), blurRadius: 18, color: Color(0x240E1518)),
    ],
    shadowPoster: [
      BoxShadow(
        offset: Offset(0, 20),
        blurRadius: 44,
        color: Color(0x380E1518),
      ),
    ],
    // Light's facets run Lead → Silver → Trail: the three brand colours with a
    // ten-step ramp interpolated between them.
    // dart format off
    fins: [
      _Brand.lead,       Color(0xFFB28E3E), Color(0xFF9F9652), Color(0xFF8F9A67),
      Color(0xFF859C79), Color(0xFF819C87), _Brand.silver,     Color(0xFF6BA098),
      Color(0xFF59A1A7), Color(0xFF4BA1B9), Color(0xFF489ECC), _Brand.trail,
    ],
    // dart format on
  );

  /// The ambient veil: a vertical wash plus a left-edge wash, in [ground].
  ///
  /// It is present on every screen, even when there is no ambient image behind
  /// it — it is what gives the interface its edges.
  List<Gradient> get ambientVeil => [
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        ground.withValues(alpha: veilNear),
        ground.withValues(alpha: 0.20),
        ground,
      ],
      stops: const [0.0, 0.35, 0.92],
    ),
    LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [ground, ground.withValues(alpha: 0.0)],
      stops: const [0.0, 0.45],
    ),
  ];
}

/// Durations and the curve. One duration and one curve, everywhere.
abstract final class Motion {
  /// Focus transform and shadow.
  static const fast = Duration(milliseconds: 180);

  /// Ambient opacity, transport fade.
  static const slow = Duration(milliseconds: 420);

  /// `cubic-bezier(0.22, 0.61, 0.36, 1)`.
  static const ease = Cubic(0.22, 0.61, 0.36, 1);
}

/// Corner radii.
abstract final class Radii {
  static const small = Radius.circular(10);
  static const large = Radius.circular(16);

  static const br = BorderRadius.all(small);
  static const brLarge = BorderRadius.all(large);

  /// Fully rounded: Home's chrome pills, the Back button, season pills. A number
  /// far larger than any element it is applied to, which is how CSS's `999px`
  /// idiom works.
  static const pill = BorderRadius.all(Radius.circular(999));

  /// The rating chip on Detail's meta line and the badges in the track menu.
  static const chip = BorderRadius.all(Radius.circular(4));

  /// Detail's media badges, a hair softer than a chip.
  static const badge = BorderRadius.all(Radius.circular(5));
}
