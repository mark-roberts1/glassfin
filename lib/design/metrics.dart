import 'package:flutter/widgets.dart';

/// Viewport-derived geometry, transcribed from `docs/ui-spec.md` §1.6.
///
/// These were `vw`/`vh` units in the CSS **on purpose**: the interface is
/// designed to hold its proportions at 1080p and 4K without a breakpoint, since
/// the viewing distance does not change with the panel. Deriving them from
/// [MediaQuery] keeps that property.
///
/// Nothing outside `lib/design/` should compute a size from the window itself.
@immutable
class Metrics {
  const Metrics._({
    required this.safeX,
    required this.safeY,
    required this.posterWidth,
    required this.stillWidth,
    required this.focusRoom,
    required this.heroHeight,
    required this.menuMaxHeight,
    required this.detailPosterWidth,
    required this.panelWidth,
    required this.detailTitleSize,
  });

  factory Metrics.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final posterWidth = size.width * 0.155;
    return Metrics._(
      safeX: size.width * 0.045,
      safeY: size.height * 0.04,
      posterWidth: posterWidth,
      stillWidth: size.width * 0.26,
      // Half the extra *height* a focused 2:3 poster gains at scale 1.06,
      // plus 8px of air. See the focusRoom contract below.
      focusRoom: posterWidth * 0.045 + 8,
      heroHeight: size.height * 0.62,
      menuMaxHeight: size.height * 0.58,
      detailPosterWidth: size.width * 0.17 > 260 ? 260 : size.width * 0.17,
      panelWidth: size.width * 0.74 > 520 ? 520 : size.width * 0.74,
      detailTitleSize: (size.width * 0.034).clamp(rem(2), rem(3.2)),
    );
  }

  /// Horizontal page inset — `4.5vw`, ≈86.4px at 1920.
  final double safeX;

  /// Vertical page inset — `4vh`, ≈43.2px at 1080.
  final double safeY;

  /// A poster card's width — `15.5vw`, ≈297.6px at 1920.
  final double posterWidth;

  /// A still (16:9 episode/resume) card's width — `26vw`, ≈499.2px at 1920.
  final double stillWidth;

  /// The space a focused card's growth needs on one side — ≈21.4px at 1920.
  ///
  /// **A contract with two consumers, and both must honour it:**
  ///
  ///  1. A horizontally scrolling row uses it as **top padding**. A scrolling
  ///     box clips its own overflow, so without it the top of the focus ring is
  ///     sliced off — and that is the half of the highlight that reads from a
  ///     sofa.
  ///  2. A card's label uses it as **top margin**, so a focused card lifts off
  ///     its own title instead of sitting on it.
  ///
  /// A row that substitutes its own round number breaks both.
  final double focusRoom;

  /// Posters are 2:3.
  double get posterHeight => posterWidth * 1.5;

  /// Stills are 16:9.
  double get stillHeight => stillWidth * 9 / 16;

  /// A Home library tile: wider *and* shorter than a poster on purpose, because
  /// a library is a place rather than a title.
  double get libraryTileWidth => posterWidth * 1.6;
  double get libraryTileHeight => libraryTileWidth * 9 / 16;

  /// Detail's backdrop — `62vh`. Sharp and full strength, as opposed to the
  /// blurred ambient wash every other screen uses; they are not the same thing.
  final double heroHeight;

  /// The track menu is capped at `58vh` so it never reaches the transport.
  final double menuMaxHeight;

  /// Detail's poster — `17vw`, capped at 260px. The cap is what stops it
  /// dominating the masthead on a very wide panel.
  final double detailPosterWidth;

  /// The sign-in panel — `min(520px, 74vw)`.
  final double panelWidth;

  /// Detail's title — `clamp(2rem, 3.4vw, 3.2rem)`. The one place a *font* size
  /// is viewport-derived, because a film's name is the largest thing on screen
  /// and should grow with the panel.
  final double detailTitleSize;

  /// The CSS never set a root font size, so `1rem` is 16px even though body
  /// text renders at 18px. Every `rem` figure in the spec is ×16, and this
  /// exists so those figures can be transcribed literally rather than
  /// pre-multiplied into magic numbers.
  static double rem(double value) => value * 16;
}

extension MetricsContext on BuildContext {
  Metrics get metrics => Metrics.of(this);
}
