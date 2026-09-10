/// How subtitles are *drawn*.
///
/// These are stored as Glassfin's settings but applied as **mpv properties** —
/// libass draws the pixels, and no amount of Flutter can restyle them. That is
/// the line the settings split falls on: if a preference could be honoured by
/// either side, it belongs to whichever one actually acts on it.
///
/// The mapping onto mpv lives in `lib/playback/mpv_config.dart`.
library;

import 'package:flutter/foundation.dart';

/// Where subtitles sit horizontally. These are mpv's own `sub-align-x` values.
enum SubtitleAlignX { left, center, right }

/// Top or bottom of the frame.
enum SubtitleAlignY { top, bottom }

@immutable
class SubtitleAppearance {
  const SubtitleAppearance({
    this.size,
    this.font,
    this.color,
    this.borderColor,
    this.borderSize,
    this.backgroundColor,
    this.backgroundTransparency,
    this.alignX = SubtitleAlignX.center,
    this.alignY = SubtitleAlignY.bottom,
    this.assScaleBorderAndShadow = true,
    this.assStyleOverride,
  });

  /// Where 32 is "Normal" — mpv wants a *scale factor*, so this becomes
  /// `size / 32`. Null leaves mpv's own default alone.
  final int? size;

  final String? font;

  /// `#RRGGBB`.
  final String? color;
  final String? borderColor;
  final int? borderSize;

  /// `#RRGGBB`. Combined with [backgroundTransparency] into mpv's
  /// `#AARRGGBB` form.
  final String? backgroundColor;

  /// A two-digit hex **alpha byte**, and note the direction: in mpv's colour
  /// syntax this is transparency, not opacity, so `FF` is fully transparent.
  /// Inverting it makes the setting read backwards.
  final String? backgroundTransparency;

  final SubtitleAlignX alignX;
  final SubtitleAlignY alignY;

  /// Whether ASS borders and shadows scale with the video, or stay at the size
  /// the subtitle author specified.
  final bool assScaleBorderAndShadow;

  /// mpv's `sub-ass-override`. Empty leaves it alone.
  final String? assStyleOverride;

  SubtitleAppearance copyWith({
    int? size,
    String? font,
    String? color,
    String? borderColor,
    int? borderSize,
    String? backgroundColor,
    String? backgroundTransparency,
    SubtitleAlignX? alignX,
    SubtitleAlignY? alignY,
    bool? assScaleBorderAndShadow,
    String? assStyleOverride,
  }) => SubtitleAppearance(
    size: size ?? this.size,
    font: font ?? this.font,
    color: color ?? this.color,
    borderColor: borderColor ?? this.borderColor,
    borderSize: borderSize ?? this.borderSize,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundTransparency:
        backgroundTransparency ?? this.backgroundTransparency,
    alignX: alignX ?? this.alignX,
    alignY: alignY ?? this.alignY,
    assScaleBorderAndShadow:
        assScaleBorderAndShadow ?? this.assScaleBorderAndShadow,
    assStyleOverride: assStyleOverride ?? this.assStyleOverride,
  );
}
