/// How a primary action is filled — **a live experiment, not a settled token.**
///
/// The style guide is an identity guide: the mark, six colours and the type
/// stack. It says nothing about buttons, and the near-white primary Glassfin
/// inherited is not from it — it came from the old Svelte app's
/// `.primary { background: var(--ink) }`, which `docs/ui-spec.md` recorded
/// faithfully because that is what the interface did.
///
/// Judging "too bright" from a description is guesswork, so the candidates live
/// here behind a debug key and get compared on the actual panel. **Once one is
/// chosen, this file collapses into whichever branch won** and the cycling goes
/// away — it is scaffolding with a deadline, not a user-facing setting.
library;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum PrimaryTreatment {
  /// What shipped: Paper at full strength. The baseline to beat.
  paper('Paper (current)'),

  /// The guide's Accent, filled. Brings the brand's signature colour to the one
  /// place the eye is already going.
  gold('Accent gold fill'),

  /// The same inverted idea, dropped about 20% in luminance so it reads as a
  /// button rather than a light source.
  dimPaper('Dimmed paper fill'),

  /// No large fill at all: a gold rule and a gold label on the raised surface.
  /// Nothing on screen then exceeds the brightness of body text.
  outlinedGold('Outlined gold');

  const PrimaryTreatment(this.label);

  /// Shown in the debug badge, so a screenshot says which one it is.
  final String label;
}

/// The resolved colours for one treatment.
@immutable
class PrimaryColours {
  const PrimaryColours({
    required this.fill,
    required this.ink,
    required this.border,
  });

  final Color? fill;
  final Color ink;
  final Color border;
}

abstract final class PrimaryStyle {
  /// Paper is the current behaviour, so the app looks unchanged until the key is
  /// pressed.
  static final ValueNotifier<PrimaryTreatment> current =
      ValueNotifier<PrimaryTreatment>(PrimaryTreatment.paper);

  static void cycle() {
    const values = PrimaryTreatment.values;
    current.value = values[(current.value.index + 1) % values.length];
  }

  static PrimaryColours resolve(GlassfinTokens tokens) =>
      switch (current.value) {
        PrimaryTreatment.paper => PrimaryColours(
          fill: tokens.ink,
          ink: tokens.ground,
          border: tokens.ink,
        ),

        // Night rather than the page ground: it is legible on both the dark
        // theme's Accent (7.7:1) and the light theme's Lead (5.7:1), where the
        // paper ground would vanish on Lead.
        PrimaryTreatment.gold => PrimaryColours(
          fill: tokens.accent,
          ink: GlassfinTokens.overOnInk,
          border: tokens.accent,
        ),

        PrimaryTreatment.dimPaper => PrimaryColours(
          fill: _dimmed(tokens.ink),
          ink: tokens.ground,
          border: _dimmed(tokens.ink),
        ),

        PrimaryTreatment.outlinedGold => PrimaryColours(
          fill: tokens.raised,
          ink: tokens.accentText,
          border: tokens.accent,
        ),
      };

  /// Toward the page ground rather than toward grey, so the fill keeps the
  /// palette's warmth instead of turning to ash.
  static Color _dimmed(Color ink) =>
      Color.lerp(ink, const Color(0xFF6B675F), 0.22)!;
}
