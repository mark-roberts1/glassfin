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

  /// Land on the group's highest-[FocusableInfo.priority] element.
  ///
  /// For a row entered from something that **has no column to keep** — the
  /// transport's scrub bar spans the whole width, so "the nearest column" is the
  /// middle of the screen, which in a row that is split left and right by a
  /// `Spacer` is a gap. Pressing Down off the scrubber landed on whichever side's
  /// innermost button happened to be closer to the centre, which was the captions
  /// button: geometrically correct and obviously wrong.
  ///
  /// Distinct from [first], which would mean "Previous episode" here. A transport
  /// has an obvious destination and it is play/pause.
  primary,
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

  /// The last node that actually took focus.
  ///
  /// Tracked here rather than read off [FocusManager] because the two questions
  /// differ at exactly the moment that matters: see [unregister].
  FocusNode? _focused;

  bool _recoveryScheduled = false;

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
    // couch bar exists to prevent.
    //
    // **Keyed on [_focused] rather than on `node.hasFocus`, which is already
    // false here.** Flutter tears a Focus widget down from the inside out: the
    // child `Focus` element unmounts before its parent [Focusable] does, and
    // detaching its attachment hands focus to the enclosing scope and clears the
    // node's manager. So the `hasFocus` test this used to make could never be
    // true, and the guarantee it documents was never actually in force. Measured,
    // not reasoned about — see `test/nav/focus_recovery_test.dart`.
    if (_focused == node) {
      _focused = null;
      _scheduleRecovery();
    }
  }

  /// Records that [node] has taken focus.
  ///
  /// Only ever called with the node that *gained* focus, never to clear one that
  /// lost it, so that a handover — B gains before A reports losing, in either
  /// order — cannot leave this pointing at nothing.
  void noteFocused(FocusNode node) {
    _focused = node;
    remember(node);
  }

  /// Whether [node] is one of the interface's own focusables.
  ///
  /// **This is the question every focus check should be asking, and three
  /// separate places in this application were asking a different one.** When the
  /// focused element goes away Flutter does not leave focus empty: it hands it to
  /// the enclosing [FocusScopeNode], which is a real node, with a real context,
  /// reporting a real — screen-sized — rectangle. So `primaryFocus == null` was
  /// never true, `primaryFocus.context == null` was never true, and the scoring
  /// rejected every candidate as lying behind a full-screen origin. The interface
  /// looked focusable and answered nothing.
  ///
  /// A scope is not somewhere the viewer can be.
  bool isOurs(FocusNode? node) => node != null && _entries.containsKey(node);

  /// Whether the viewer has focus on something they can see and press.
  bool get hasRealFocus => isOurs(FocusManager.instance.primaryFocus);

  /// Puts focus back on [node], or reports that it cannot.
  ///
  /// Records the intent synchronously, so that a recovery scheduled later in the
  /// same frame — by the teardown that prompted this in the first place — does
  /// not second-guess a destination the application chose deliberately.
  bool restoreFocusTo(FocusNode? node) {
    if (node == null || !_isUsable(node)) return false;
    noteFocused(node);
    node.requestFocus();
    return true;
  }

  void _scheduleRecovery() {
    // A screen swap unregisters every node it had, and one recovery is enough.
    if (_recoveryScheduled) return;
    _recoveryScheduled = true;
    // Deferred because the tree is still being finalised at this point, and
    // because whatever replaces this screen may be about to claim focus itself.
    scheduleMicrotask(() {
      _recoveryScheduled = false;
      // Either something already holds focus, or a destination has been claimed
      // and is one microtask away from taking it — [restoreFocusTo] records that
      // intent for exactly this reason, because [FocusManager] does not apply a
      // focus request until a microtask of its own and this one gets there first.
      // Recovery is a net, not a policy: it must never overrule a deliberate
      // choice.
      if (hasRealFocus || isOurs(_focused)) return;
      focusSomethingSensible();
    });
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

  /// The highest-priority usable element of [group], for [GroupEntry.primary].
  ///
  /// Ties break on registration order, so a group where nobody claims priority
  /// behaves as [GroupEntry.first] rather than arbitrarily.
  FocusNode? primaryIn(String group) {
    FocusNode? best;
    FocusableInfo? bestInfo;
    for (final node in nodesIn(group)) {
      final info = infoFor(node);
      if (info == null) continue;
      if (bestInfo == null || info.priority > bestInfo.priority) {
        best = node;
        bestInfo = info;
      }
    }
    return best;
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
  ///
  /// **The context alone proves nothing**: [FocusNode.dispose] never clears the
  /// context it was attached to, so a node whose widget is long gone still
  /// reports one. What distinguishes a node still in the focus tree is its
  /// parent, which detaching does clear.
  ///
  /// [FocusNode.canRequestFocus] walks the ancestors checking
  /// `descendantsAreFocusable`, so this also answers false for anything inside an
  /// `ExcludeFocus` — which is how the screen behind a film reports itself while
  /// the film is up.
  bool _isUsable(FocusNode node) {
    final context = node.context;
    return context != null &&
        context.mounted &&
        node.parent != null &&
        node.canRequestFocus &&
        !node.skipTraversal;
  }

  /// Drops every registration and all group memory.
  ///
  /// Used on sign-out — a deep route stack full of another account's items
  /// should not be waiting after the next sign-in — and by tests between cases.
  void clear() {
    _entries.clear();
    _groupMemory.clear();
    _focused = null;
    _sequence = 0;
  }
}
