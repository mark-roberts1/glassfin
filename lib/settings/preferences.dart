/// Behaviour preferences — **Glassfin's own**, as opposed to the ones that are
/// really mpv's.
///
/// The split matters: these are decisions the application acts on (which track
/// to pick, whether to skip an intro, which palette to draw). Anything that is
/// mpv drawing pixels lives in [SubtitleAppearance] instead.
library;

import 'package:flutter/foundation.dart';

import '../jellyfin/track_choice.dart';

enum ThemePreference { dark, light, system }

/// What to do when an intro or credits marker is reached.
enum SkipMode {
  /// Ignore markers entirely.
  off,

  /// Offer a button, and leave it to the viewer.
  prompt,

  /// Seek past it without asking.
  auto,
}

@immutable
class Preferences {
  const Preferences({
    this.theme = ThemePreference.dark,
    this.audioLanguage = '',
    this.subtitleMode = SubtitleMode.off,
    this.subtitleLanguage = '',
    this.introSkip = SkipMode.prompt,
    this.outroSkip = SkipMode.prompt,
  });

  factory Preferences.fromJson(Map<String, Object?> json) => Preferences(
    theme: ThemePreference.values.byName(
      json['theme'] as String? ?? ThemePreference.dark.name,
    ),
    audioLanguage: json['audioLanguage'] as String? ?? '',
    subtitleMode: SubtitleMode.values.byName(
      json['subtitleMode'] as String? ?? SubtitleMode.off.name,
    ),
    subtitleLanguage: json['subtitleLanguage'] as String? ?? '',
    introSkip: SkipMode.values.byName(
      json['introSkip'] as String? ?? SkipMode.prompt.name,
    ),
    outroSkip: SkipMode.values.byName(
      json['outroSkip'] as String? ?? SkipMode.prompt.name,
    ),
  );

  /// Dark by default rather than "follow the system": a television in a dark
  /// room is the case to be right about, and most shells have no palette
  /// preference worth consulting.
  final ThemePreference theme;

  /// An ISO 639-2 code, or empty for "whatever the file defaults to".
  final String audioLanguage;

  final SubtitleMode subtitleMode;
  final String subtitleLanguage;

  final SkipMode introSkip;
  final SkipMode outroSkip;

  SkipMode skipModeFor(SegmentIntent intent) => switch (intent) {
    SegmentIntent.intro => introSkip,
    SegmentIntent.outro => outroSkip,
  };

  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'audioLanguage': audioLanguage,
    'subtitleMode': subtitleMode.name,
    'subtitleLanguage': subtitleLanguage,
    'introSkip': introSkip.name,
    'outroSkip': outroSkip.name,
  };

  Preferences copyWith({
    ThemePreference? theme,
    String? audioLanguage,
    SubtitleMode? subtitleMode,
    String? subtitleLanguage,
    SkipMode? introSkip,
    SkipMode? outroSkip,
  }) => Preferences(
    theme: theme ?? this.theme,
    audioLanguage: audioLanguage ?? this.audioLanguage,
    subtitleMode: subtitleMode ?? this.subtitleMode,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    introSkip: introSkip ?? this.introSkip,
    outroSkip: outroSkip ?? this.outroSkip,
  );
}

/// The two kinds of segment Glassfin acts on.
///
/// The server may report recaps, previews and adverts too; those are read and
/// ignored, because there is no preference for them and silently skipping a
/// recap is not obviously wanted.
enum SegmentIntent { intro, outro }
