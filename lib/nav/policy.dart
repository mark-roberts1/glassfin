import 'package:flutter/widgets.dart';

import 'registry.dart';
import 'reveal.dart';
import 'scoring.dart';

/// Spatial focus traversal for a ten-foot interface.
///
/// Flutter's [DirectionalFocusTraversalPolicyMixin] is close but not right: it
/// walks off the end of a horizontal row into whatever is below, and it has no
/// notion of a group that wants to be entered at its start. Both matter enough
/// from a sofa to justify a custom policy. See `docs/ui-spec.md` §2.
class GlassfinTraversalPolicy extends FocusTraversalPolicy {
  GlassfinTraversalPolicy({NavRegistry? registry})
    : _registry = registry ?? NavRegistry.instance;

  final NavRegistry _registry;

  /// Registration order, which is layout order. Used for tab traversal and to
  /// break scoring ties deterministically.
  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final sorted = descendants.toList()
      ..sort((a, b) {
        final sa = _registry.infoFor(a)?.sequence;
        final sb = _registry.infoFor(b)?.sequence;
        // Unregistered nodes sort last: they are not part of the spatial
        // interface and should never be preferred over something that is.
        if (sa == null && sb == null) return 0;
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sa.compareTo(sb);
      });
    return sorted;
  }

  @override
  FocusNode? findFirstFocusInDirection(
    FocusNode currentNode,
    TraversalDirection direction,
  ) {
    final candidates = _candidates(currentNode);
    if (candidates.isEmpty) return null;
    // With nothing focused yet there is no origin to move away from, so
    // "sensible" is the right answer rather than a geometric one.
    return candidates.first;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final origin = _rectOf(currentNode);
    if (origin == null) {
      return _registry.focusSomethingSensible();
    }

    final candidates = _candidates(currentNode);
    final rects = <Rect>[];
    final usable = <FocusNode>[];
    for (final node in candidates) {
      final rect = _rectOf(node);
      if (rect == null) continue;
      usable.add(node);
      rects.add(rect);
    }

    final winner = bestCandidate(origin, rects, direction);
    if (winner == null) return false;

    final target = _applyGroupEntry(currentNode, usable[winner], direction);
    _focus(target);
    return true;
  }

  /// Group entry, from `docs/ui-spec.md` §2.3.
  ///
  /// A **vertical** move into a *different* group whose entry is
  /// [GroupEntry.first] lands on that group's first element rather than the
  /// geometric winner. Horizontal moves are excluded because they never leave
  /// their row in the first place, so "arriving in a group" does not apply.
  ///
  /// Group focus memory does not override this: a carousel that is scrolled
  /// somewhere the viewer did not choose should start at its beginning.
  FocusNode _applyGroupEntry(
    FocusNode from,
    FocusNode winner,
    TraversalDirection direction,
  ) {
    final vertical =
        direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    if (!vertical) return winner;

    final winnerInfo = _registry.infoFor(winner);
    final group = winnerInfo?.group;
    if (group == null || winnerInfo!.enter != GroupEntry.first) return winner;
    if (_registry.infoFor(from)?.group == group) return winner;

    final nodes = _registry.nodesIn(group);
    return nodes.isEmpty ? winner : nodes.first;
  }

  void _focus(FocusNode node) {
    node.requestFocus();
    _registry.remember(node);

    final info = _registry.infoFor(node);
    info?.onFocus?.call();

    // Reveal after the frame in which focus lands, so that any layout the focus
    // change itself causes — a row expanding, a season's episodes swapping in —
    // has already settled and the geometry we scroll against is the real one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = info?.revealContext?.call() ?? node.context;
      if (context != null && context.mounted) reveal(context);
    });
  }

  /// Everything focusable in the current scope except [currentNode], in
  /// registration order.
  List<FocusNode> _candidates(FocusNode currentNode) {
    final scope = currentNode.nearestScope;
    if (scope == null) return const [];
    return sortDescendants(scope.traversalDescendants, currentNode)
        .where((node) => node != currentNode)
        .toList();
  }

  /// A node's global rectangle, or `null` if it is not laid out.
  Rect? _rectOf(FocusNode node) {
    final renderObject = node.context?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}
