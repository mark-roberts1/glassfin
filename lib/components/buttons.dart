/// The two button shapes the interface uses, and nothing else.
///
/// [Pill] is chrome — Home's Search and Settings, the Back button, a season
/// selector. [GlassButton] is everything with a job: Detail's actions, Library's
/// "Show more", Login's stages, a Settings row.
///
/// They differ in more than their corners. A pill **inverts and scales** on
/// focus; a button takes **the ring alone**, because at that size the content is
/// mostly text and scaling text resamples it into a blur. See `docs/ui-spec.md`
/// §1.8.
library;

import 'package:flutter/widgets.dart';

import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/primary_style.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// How a [GlassButton] presents itself, independently of focus.
enum ButtonTone {
  /// Raised, with a hairline edge. The default.
  plain,

  /// Inverted: ink background, ground text, weight 500. One per screen at most —
  /// it is the thing the viewer came to do.
  primary,

  /// Transparent, in dimmed ink. For "Change server", "Cancel", "Back": ways
  /// out, which should be findable without competing with the way forward.
  quiet,
}

class GlassButton extends StatelessWidget {
  const GlassButton({
    required this.label,
    required this.group,
    this.onSelect,
    this.tone = ButtonTone.plain,
    this.priority = 0,
    this.enabled = true,
    this.centred = false,
    this.padding,
    this.textStyle,
    super.key,
  });

  final String label;
  final String group;
  final VoidCallback? onSelect;
  final ButtonTone tone;
  final int priority;
  final bool enabled;

  /// Primary actions and quiet ways out are centred; a field or a list row reads
  /// better left-aligned, so that is the default.
  final bool centred;

  final EdgeInsets? padding;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final inverted = tone == ButtonTone.primary;
    final primary = PrimaryStyle.resolve(tokens);

    return Focusable(
      group: group,
      visual: FocusVisual.ringOnly,
      onSelect: onSelect,
      priority: priority,
      enabled: enabled && onSelect != null,
      child: (context, focused) => Container(
        padding:
            padding ??
            EdgeInsets.symmetric(
              horizontal: Metrics.rem(1),
              vertical: Metrics.rem(0.85),
            ),
        decoration: BoxDecoration(
          borderRadius: Radii.br,
          color: switch (tone) {
            ButtonTone.primary => primary.fill,
            ButtonTone.quiet => null,
            ButtonTone.plain => tokens.raised,
          },
          border: tone == ButtonTone.quiet
              ? null
              : Border.all(color: inverted ? primary.border : tokens.edge),
        ),
        // **Align, not Container.alignment.** A Container given an alignment
        // expands to fill whatever it is offered, so in a Wrap — Detail's
        // actions, the keyboard's controls — every button took the full width
        // and stacked one per line. Align with a width factor shrink-wraps
        // under loose constraints and still fills under tight ones, so Login's
        // stretched column keeps its full-width buttons either way.
        child: Align(
          alignment: centred ? Alignment.center : Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            textAlign: centred ? TextAlign.center : TextAlign.start,
            style: (textStyle ?? Type.body).copyWith(
              fontWeight: inverted ? Type.medium : null,
              color: switch (tone) {
                ButtonTone.primary => primary.ink,
                ButtonTone.quiet => tokens.inkDim,
                ButtonTone.plain => tokens.ink,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Chrome: fully rounded, small, and inverted when focused.
class Pill extends StatelessWidget {
  const Pill({
    required this.label,
    required this.group,
    this.onSelect,
    this.leading,
    this.selected = false,
    this.priority = 0,
    super.key,
  });

  final String label;
  final String group;
  final VoidCallback? onSelect;

  /// The Back button's chevron. A literal `‹` rather than an icon, which is why
  /// the padding below is asymmetric — the glyph eats the space on its own left.
  final Widget? leading;

  /// A season pill for the season currently shown: outlined and lettered in
  /// `accentText`. This is one of the two places gold appears as *text*.
  final bool selected;

  final int priority;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Focusable(
      group: group,
      // Inverted rather than ring-only: a pill is small and set against the page
      // rather than filling a column, so it can afford the scale and needs the
      // extra separation from its neighbours.
      visual: FocusVisual.inverted,
      borderRadius: Radii.pill,
      onSelect: onSelect,
      priority: priority,
      enabled: onSelect != null,
      child: (context, focused) {
        final ink = focused ? tokens.ground : (selected ? tokens.accentText : tokens.ink);
        return Container(
          padding: EdgeInsets.fromLTRB(
            leading == null ? Metrics.rem(1.3) : Metrics.rem(0.95),
            Metrics.rem(0.5),
            Metrics.rem(1.3),
            Metrics.rem(0.5),
          ),
          decoration: BoxDecoration(
            borderRadius: Radii.pill,
            color: focused ? tokens.ink : tokens.raised,
            border: Border.all(
              color: focused
                  ? tokens.ink
                  : (selected ? tokens.accentText : tokens.edge),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                DefaultTextStyle(
                  style: Type.px(
                    // `1.25em` against the pill's own 0.95rem label.
                    Metrics.rem(0.95) * 1.25,
                    height: 1,
                  ).copyWith(color: ink),
                  child: leading!,
                ),
                SizedBox(width: Metrics.rem(0.4)),
              ],
              Text(label, style: Type.label.copyWith(color: ink)),
            ],
          ),
        );
      },
    );
  }
}
