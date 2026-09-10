import 'dart:async';

import 'package:flutter/widgets.dart';

/// Where focus lands when it arrives in a group from a different one.
enum GroupEntry {
  /// Keep the column: the geometric winner wins.
  nearest,

  /// Land on the group's first registered element.
  ///
  /// Set on **horizontally scrolling rows and nowhere else.** A carousel is
  /// scrolled to a position the viewer did not choose, so the column they came
  /// from points at nothing they can see. Grids and static button rows are
  /// aligned to the page and must keep the column — the on-screen keyboard is
  /// the clearest case, where `first` would mean landing on `A` every time you
  /// pressed Up from Done.
  first,
}

/// What the navigation layer knows about one focusable.
@immutable
class FocusableInfo {
  const FocusableInfo({
    required this.sequence,
    this.group,
    this.enter = GroupEntry.nearest,
    this.onSelect,
    this.onFocus,
    this.priority = 0,
    this.revealContext,
  });

  /// Registration order. Decides "first in the group", and breaks scoring ties
  /// so that two equally good destinations resolve by layout order rather than
  /// by hash order.
  final int sequence;

  /// Elements sharing a group are a row or a grid, and the group remembers
  /// where focus last was inside it.
  final String? group;

  final GroupEntry enter;

  /// Invoked by the input router when this node is focused and select is
  /// pressed. Widgets do not listen for keys themselves — input enters the app
  /// at exactly one place.
  final VoidCallback? onSelect;

  /// Invoked when this node takes focus. Drives the ambient backdrop.
  final VoidCallback? onFocus;

  /// Weight for "focus something sensible". Detail's Play button sets 2 so that
  /// opening a film lands on Play rather than on the season pills.
  final int priority;

  /// The box to scroll into view, when it is larger than the focusable itself.
  final BuildContext Function()? revealContext;
}

/// The registry of everything focusable, and the group focus memory.
///
/// Kept as a plain object rather than an inherited widget: focus traversal runs
/// from a policy that has a [FocusNode] but no build context of its own, and
/// threading one through buys nothing here.
class NavRegistry {
  NavRegistry._();

  static final NavRegistry instance = NavRegistry._();

  final Map<FocusNode, FocusableInfo> _entries = {};
  final Map<String, FocusNode> _groupMemory = {};
  int _sequence = 0;

  /// Assigns the next registration sequence number.
  int nextSequence() => _sequence++;

  void register(FocusNode node, FocusableInfo info) {
    _entries[node] = info;
  }

  void unregister(FocusNode node) {
    final info = _entries.remove(node);
    final group = info?.group;
    if (group != null && _groupMemory[group] == node) {
      _groupMemory.remove(group);
    }

    // Focus is never lost. A destroyed focused element leaves the interface with
    // nothing highlighted, which from three metres is indistinguishable from the
    // app having frozen — and it is a dead end, which is the specific failure the
    // couch bar exists to prevent. Deferred by a microtask because the tree is
    // usually still being rebuilt at this point.
    if (node.hasFocus) {
      scheduleMicrotask(focusSomethingSensible);
    }
  }

  FocusableInfo? infoFor(FocusNode node) => _entries[node];

  /// Records that [node] was the last thing focused inside its group.
  void remember(FocusNode node) {
    final group = _entries[node]?.group;
    if (group != null) _groupMemory[group] = node;
  }

  FocusNode? lastFocusedIn(String group) {
    final node = _groupMemory[group];
    if (node == null) return null;
    return _isUsable(node) ? node : null;
  }

  /// Forgets a group's focus memory. Groups whose contents are replaced wholesale
  /// must do this — Detail on a season change, the keyboard and the playback menu
  /// on mount — or focus is restored to a node describing different content.
  void resetGroup(String group) => _groupMemory.remove(group);

  /// The nodes of [group], in registration order.
  List<FocusNode> nodesIn(String group) {
    final nodes =
        _entries.entries
            .where((e) => e.value.group == group && _isUsable(e.key))
            .toList()
          ..sort((a, b) => a.value.sequence.compareTo(b.value.sequence));
    return [for (final e in nodes) e.key];
  }

  /// Focuses a group by name, preferring where focus last was inside it.
  ///
  /// **Anything that opens or reveals a region should focus that region by
  /// name.** A generic "focus the first thing" reaches straight past a modal to
  /// the screen behind it.
  bool focusGroup(String group) {
    final remembered = lastFocusedIn(group);
    if (remembered != null) {
      remembered.requestFocus();
      return true;
    }
    final nodes = nodesIn(group);
    if (nodes.isEmpty) return false;
    nodes.first.requestFocus();
    return true;
  }

  /// Highest priority wins, ties broken by registration order.
  bool focusSomethingSensible() {
    FocusNode? best;
    FocusableInfo? bestInfo;
    for (final entry in _entries.entries) {
      if (!_isUsable(entry.key)) continue;
      if (bestInfo == null ||
          entry.value.priority > bestInfo.priority ||
          (entry.value.priority == bestInfo.priority &&
              entry.value.sequence < bestInfo.sequence)) {
        best = entry.key;
        bestInfo = entry.value;
      }
    }
    if (best == null) return false;
    best.requestFocus();
    return true;
  }

  /// A node still in the tree and able to take focus. A disabled focusable stays
  /// registered but is skipped, so that re-enabling it does not renumber
  /// everything after it.
  bool _isUsable(FocusNode node) =>
      node.context != null && node.canRequestFocus && !node.skipTraversal;

  /// Test seam: drops all registrations and memory.
  @visibleForTesting
  void reset() {
    _entries.clear();
    _groupMemory.clear();
    _sequence = 0;
  }
}
