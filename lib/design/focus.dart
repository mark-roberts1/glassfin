import 'package:flutter/widgets.dart';

import '../nav/registry.dart';
import 'theme.dart';
import 'tokens.dart';

/// The focus treatments from `docs/ui-spec.md` §1.8.
///
/// **Scale is the primary signal**, not the ring. It survives photography off a
/// screen, colour-blindness, and the aggressive contrast processing a television
/// applies to everything by default. The 3px ring is support.
enum FocusVisual {
  /// Card artwork: `scale(1.06)`, ring, and the focus shadow.
  artwork,

  /// Home pills and the ScreenHeader's Back button: the same scale and ring,
  /// but the surface inverts to solid ink with the content flipping to ground.
  inverted,

  /// Keyboard keys: `scale(1.1)` — keys are small, so they scale *more* — plus
  /// the ring and the lift shadow.
  key,

  /// Settings rows, the Library "show more" button, Detail's actions, Login's
  /// buttons: **ring only, no scale.** At those sizes the content is mostly
  /// text, and scaling text resamples it into a blur.
  ringOnly,

  /// The playback menu's track rows: ring only, drawn in `overInk` rather than
  /// the page's ink, because the menu floats over the film.
  ringOnlyOverVideo,
}

/// Anything the viewer can reach.
///
/// Registers with the navigation layer and draws the focus treatment. **If it
/// can be focused, it is a [Focusable]** — an element reachable by eye but not
/// by the traversal policy is a dead end, and dead ends are the specific failure
/// the couch bar exists to prevent.
///
/// Key handling is deliberately absent: input enters the application at exactly
/// one place, and that router invokes [onSelect] on whatever currently has
/// focus.
class Focusable extends StatefulWidget {
  const Focusable({
    required this.child,
    this.visual = FocusVisual.artwork,
    this.group,
    this.enter = GroupEntry.nearest,
    this.onSelect,
    this.onFocus,
    this.priority = 0,
    this.enabled = true,
    this.borderRadius = Radii.br,
    this.revealKey,
    this.focusNode,
    super.key,
  });

  /// Receives whether this element currently has focus, for the treatments that
  /// change their own content — [FocusVisual.inverted] flips its text and icons
  /// to the ground colour.
  final Widget Function(BuildContext context, bool focused) child;

  final FocusVisual visual;

  /// The row or grid this belongs to. See [GroupEntry].
  final String? group;
  final GroupEntry enter;

  final VoidCallback? onSelect;
  final VoidCallback? onFocus;

  /// Weight for "focus something sensible" when focus has to be recovered.
  final int priority;

  /// A disabled focusable stays registered but is skipped, so re-enabling it
  /// does not renumber the registration order around it.
  final bool enabled;

  final BorderRadius borderRadius;

  /// The larger box to scroll into view, when the focusable is smaller than the
  /// thing the viewer is actually choosing — a card's artwork is focusable, but
  /// its title and runtime are siblings, and revealing only the artwork leaves
  /// the metadata under the fold.
  final GlobalKey? revealKey;

  final FocusNode? focusNode;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  late final int _sequence = NavRegistry.instance.nextSequence();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _applyEnabled();
    _register();
  }

  @override
  void didUpdateWidget(Focusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyEnabled();
    // The callbacks close over widget state that changes between builds, so the
    // registration has to be refreshed rather than captured once.
    _register();
  }

  void _register() {
    NavRegistry.instance.register(
      _node,
      FocusableInfo(
        sequence: _sequence,
        group: widget.group,
        enter: widget.enter,
        onSelect: widget.onSelect,
        onFocus: widget.onFocus,
        priority: widget.priority,
        revealContext: widget.revealKey == null
            ? null
            : () => widget.revealKey!.currentContext ?? context,
      ),
    );
  }

  void _applyEnabled() {
    _node.canRequestFocus = widget.enabled;
    _node.skipTraversal = !widget.enabled;
  }

  @override
  void dispose() {
    NavRegistry.instance.unregister(_node);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      NavRegistry.instance.remember(_node);
      widget.onFocus?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final on = _focused && widget.enabled;

    final scale = switch (widget.visual) {
      FocusVisual.artwork || FocusVisual.inverted => 1.06,
      FocusVisual.key => 1.1,
      FocusVisual.ringOnly || FocusVisual.ringOnlyOverVideo => 1.0,
    };

    final ringColour = widget.visual == FocusVisual.ringOnlyOverVideo
        ? GlassfinTokens.overInk
        : tokens.ink;

    final shadows = <BoxShadow>[
      // A spread-only shadow *is* the CSS `0 0 0 3px` ring: it draws outside the
      // box, so it never eats into the artwork it surrounds.
      if (on) BoxShadow(color: ringColour, spreadRadius: 3, blurRadius: 0),
      if (on)
        ...switch (widget.visual) {
          FocusVisual.artwork || FocusVisual.inverted => tokens.shadowFocus,
          FocusVisual.key => tokens.shadowLift,
          FocusVisual.ringOnly || FocusVisual.ringOnlyOverVideo => const [],
        },
    ];

    Widget content = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.ease,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: widget.visual == FocusVisual.inverted && on
            ? tokens.ink
            : null,
        boxShadow: shadows,
      ),
      child: widget.child(context, on),
    );

    if (scale != 1.0) {
      content = AnimatedScale(
        // Reduced motion is honoured for the ambient fade, scrolling, the
        // transport and the caret — but *not* here. The focus scale is not
        // decoration; it is how the viewer knows where they are.
        scale: on ? scale : 1.0,
        duration: Motion.fast,
        curve: Motion.ease,
        child: content,
      );
    }

    return Focus(
      focusNode: _node,
      onFocusChange: _onFocusChange,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      child: content,
    );
  }
}
