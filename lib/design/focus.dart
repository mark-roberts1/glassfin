import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../nav/pointer.dart';
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

  /// The transport's icon controls: **scale alone, and no ring.**
  ///
  /// Over the film the ring is wrong twice over. A rectangle around a glyph is
  /// a page idiom, and drawn on a photograph it reads as a box that has always
  /// been there rather than as a highlight. Scale is what this document already
  /// calls the primary signal, and it is the one the reference client uses —
  /// its controls grow under the pointer and light a circle behind themselves,
  /// which is what [GlassfinTokens.overHighlight] is for. The component paints
  /// that circle from the `focused` flag; the focus layer supplies the growth.
  overVideoControl,

  /// The scrub bar, the track and settings menu rows, the skip prompt:
  /// **no ring and no scale.**
  ///
  /// The same reasoning, minus the growth: these are full-width, and a row that
  /// grows pushes its neighbours around. They light their own surface instead —
  /// again from the `focused` flag.
  overVideoSurface,
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
      FocusVisual.overVideoControl => 1.1,
      FocusVisual.ringOnly || FocusVisual.overVideoSurface => 1.0,
    };

    // Anything over the film draws its own focused surface; see
    // [FocusVisual.overVideoControl].
    final ringed =
        widget.visual != FocusVisual.overVideoControl &&
        widget.visual != FocusVisual.overVideoSurface;

    // Depth only. **The ring is not a shadow** — see [_Ring].
    final shadows = <BoxShadow>[
      if (on)
        ...switch (widget.visual) {
          FocusVisual.artwork || FocusVisual.inverted => tokens.shadowFocus,
          FocusVisual.key => tokens.shadowLift,
          FocusVisual.ringOnly ||
          FocusVisual.overVideoControl ||
          FocusVisual.overVideoSurface => const [],
        },
    ];

    Widget content = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.ease,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: widget.visual == FocusVisual.inverted && on ? tokens.ink : null,
        boxShadow: shadows,
      ),
      child: widget.child(context, on),
    );

    if (ringed) {
      content = Stack(
        // The ring is drawn outside the box, so the stack must not clip it.
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            left: -ringWidth,
            top: -ringWidth,
            right: -ringWidth,
            bottom: -ringWidth,
            child: _Ring(
              on: on,
              colour: tokens.focusRing,
              radius: _grown(widget.borderRadius, ringWidth),
            ),
          ),
        ],
      );
    }

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
      child: MouseRegion(
        // Hidden until a real mouse moves: a television with no mouse must
        // never show a cursor parked in the middle of a film.
        cursor: PointerMode.instance.active.value
            ? SystemMouseCursors.click
            : SystemMouseCursors.none,
        onHover: _onHover,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: content,
        ),
      ),
    );
  }

  /// Hover focuses, but only once the mouse has actually been moved — see
  /// [PointerMode].
  void _onHover(PointerHoverEvent event) {
    if (!PointerMode.instance.noteMove(event.position)) return;
    if (!widget.enabled || _node.hasFocus) return;
    _node.requestFocus();
    NavRegistry.instance.remember(_node);
    widget.onFocus?.call();
    // **No reveal.** A trackpad already scrolls at the viewer's own pace, and
    // auto-centring under a moving cursor reads as the row dodging away from
    // it. Reveal is for pad moves, which step one card at a time.
  }

  void _onTap() {
    if (!widget.enabled) return;
    _node.requestFocus();
    NavRegistry.instance.remember(_node);
    widget.onSelect?.call();
  }
}

/// The 3px focus ring, from `docs/ui-spec.md` §1.8.
///
/// **An outline, not a shadow, and the distinction is load-bearing.** The CSS
/// this ports from was `box-shadow: 0 0 0 3px <ink>`, and the obvious Flutter
/// translation — a [BoxShadow] with `spreadRadius: 3` and no blur — is wrong in
/// one specific case that looks fine everywhere else.
///
/// A box shadow is a *filled* rounded rect painted behind the child. When the
/// child is opaque you only ever see the 3px rim, so cards, pills and settings
/// rows all looked correct. When the child is deliberately transparent — a quiet
/// button, which is the "Back" and "Cancel" treatment — the fill shows straight
/// through the whole element, turning it into a solid slab of ink with its own
/// dimmed label now invisible on top of it.
///
/// Drawn as a border on a box inset by −3 instead, so it occupies the same
/// pixels as the CSS did and never paints over anything.
class _Ring extends StatelessWidget {
  const _Ring({required this.on, required this.colour, required this.radius});

  final bool on;
  final Color colour;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: on ? 1 : 0,
      duration: Motion.fast,
      curve: Motion.ease,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: colour, width: ringWidth),
        ),
      ),
    ),
  );
}

/// The ring's thickness. Three pixels at 1080p, which is what reads from a sofa
/// without becoming a frame in its own right.
const double ringWidth = 3;

/// The ring sits [by] pixels outside the element, so its corners have to be that
/// much rounder or they cut across the child's own.
BorderRadius _grown(BorderRadius radius, double by) => BorderRadius.only(
  topLeft: Radius.circular(radius.topLeft.x + by),
  topRight: Radius.circular(radius.topRight.x + by),
  bottomLeft: Radius.circular(radius.bottomLeft.x + by),
  bottomRight: Radius.circular(radius.bottomRight.x + by),
);
