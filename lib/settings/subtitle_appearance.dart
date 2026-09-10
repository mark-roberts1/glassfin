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

  /// **The nullable fields are passed as closures, not as values.**
  ///
  /// Every one of these settings has "Default" as a real, selectable option that
  /// means *null* — leave mpv's own value alone. An ordinary
  /// `int? size` parameter cannot express that: `size ?? this.size` reads a null
  /// as "not specified" and quietly keeps the old value, so cycling a row round
  /// to Default would do nothing. Passing `size: () => null` says it plainly,
  /// and omitting the argument still means "leave this field as it is".
  SubtitleAppearance copyWith({
    ValueGetter<int?>? size,
    ValueGetter<String?>? font,
    ValueGetter<String?>? color,
    ValueGetter<String?>? borderColor,
    ValueGetter<int?>? borderSize,
    ValueGetter<String?>? backgroundColor,
    ValueGetter<String?>? backgroundTransparency,
    SubtitleAlignX? alignX,
    SubtitleAlignY? alignY,
    bool? assScaleBorderAndShadow,
    ValueGetter<String?>? assStyleOverride,
  }) => SubtitleAppearance(
    size: size == null ? this.size : size(),
    font: font == null ? this.font : font(),
    color: color == null ? this.color : color(),
    borderColor: borderColor == null ? this.borderColor : borderColor(),
    borderSize: borderSize == null ? this.borderSize : borderSize(),
    backgroundColor: backgroundColor == null
        ? this.backgroundColor
        : backgroundColor(),
    backgroundTransparency: backgroundTransparency == null
        ? this.backgroundTransparency
        : backgroundTransparency(),
    alignX: alignX ?? this.alignX,
    alignY: alignY ?? this.alignY,
    assScaleBorderAndShadow:
        assScaleBorderAndShadow ?? this.assScaleBorderAndShadow,
    assStyleOverride: assStyleOverride == null
        ? this.assStyleOverride
        : assStyleOverride(),
  );

  factory SubtitleAppearance.fromJson(Map<String, Object?> json) =>
      SubtitleAppearance(
        size: json['size'] as int?,
        font: json['font'] as String?,
        color: json['color'] as String?,
        borderColor: json['borderColor'] as String?,
        borderSize: json['borderSize'] as int?,
        backgroundColor: json['backgroundColor'] as String?,
        backgroundTransparency: json['backgroundTransparency'] as String?,
        alignX: SubtitleAlignX.values.byName(
          json['alignX'] as String? ?? SubtitleAlignX.center.name,
        ),
        alignY: SubtitleAlignY.values.byName(
          json['alignY'] as String? ?? SubtitleAlignY.bottom.name,
        ),
        assScaleBorderAndShadow:
            json['assScaleBorderAndShadow'] as bool? ?? true,
        assStyleOverride: json['assStyleOverride'] as String?,
      );

  /// Nulls are written out rather than omitted, so that "Default" survives a
  /// restart as the deliberate choice it is.
  Map<String, Object?> toJson() => {
    'size': size,
    'font': font,
    'color': color,
    'borderColor': borderColor,
    'borderSize': borderSize,
    'backgroundColor': backgroundColor,
    'backgroundTransparency': backgroundTransparency,
    'alignX': alignX.name,
    'alignY': alignY.name,
    'assScaleBorderAndShadow': assScaleBorderAndShadow,
    'assStyleOverride': assStyleOverride,
  };
}
