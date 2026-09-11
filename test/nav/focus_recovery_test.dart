/// What happens to focus when the thing holding it is torn down.
///
/// The symptom: **after a film ends, the controller does nothing.** No direction
/// moves focus and the only way back into the interface is a mouse click. From
/// three metres that is indistinguishable from the application having frozen,
/// which is the exact failure the couch bar exists to prevent.
///
/// Four mechanisms had to line up to produce it, and the first three are each
/// things that looked handled in the code and were not:
///
///  1. a [Visibility] coming back into view trips a framework assertion that
///     aborts the frame before `finalizeTree()`, so nothing unmounts at all;
///  2. the focused node has already lost focus by the time it unregisters, so the
///     registry's "focus is never lost" net could never fire;
///  3. focus falls back to the enclosing *scope*, which is not null and whose
///     context is not null — so both guards written against those were inert;
///  4. a scope reports the whole screen as its rectangle, so the scoring rejects
///     every candidate as lying behind the origin, and no direction recovers.
///
/// Each is pinned separately here, so that fixing one does not quietly hide the
/// others.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/design/focus.dart';
import 'package:glassfin/design/theme.dart';
import 'package:glassfin/design/tokens.dart';
import 'package:glassfin/input/actions.dart';
import 'package:glassfin/input/router.dart';
import 'package:glassfin/nav/policy.dart';
import 'package:glassfin/nav/registry.dart';

/// Somewhere to call [moveFocus] from: the application builds its router beneath
/// the traversal group, and a context above it would find Flutter's default
/// policy rather than Glassfin's.
BuildContext? _below;

/// The application's own layering, reduced to what matters here: a screen kept
/// alive but hidden behind a player that comes and goes.
/// The application's root [Focus] — screen-sized, and not a [Focusable].
///
/// Present because it is the node focus actually lands on when the focused
/// element goes away, and because its rectangle is the whole screen, which is
/// what breaks the scoring.
final FocusNode _root = FocusNode(debugLabel: 'root');

Widget _host({required bool overlay, bool maintainSemantics = true}) =>
    GlassfinTheme(
      tokens: GlassfinTokens.dark,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FocusTraversalGroup(
          policy: GlassfinTraversalPolicy(),
          child: Focus(
            focusNode: _root,
            child: Builder(
              builder: (context) {
                _below = context;
                return Stack(
                  children: [
                    Visibility(
                      visible: !overlay,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      maintainInteractivity: true,
                      maintainSemantics: maintainSemantics,
                      child: Column(
                        children: [_spot('screen-a'), _spot('screen-b')],
                      ),
                    ),
                    if (overlay)
                      Positioned(bottom: 0, child: _spot('overlay')),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

Widget _spot(String name) => Focusable(
  key: ValueKey(name),
  group: name,
  visual: FocusVisual.ringOnly,
  onSelect: () {},
  child: (context, focused) =>
      SizedBox(width: 100, height: 40, child: Text(name)),
);

FocusNode _nodeOf(WidgetTester tester, String name) =>
    Focus.of(tester.element(find.text(name)));

/// Put the overlay up with focus on it, the state a film is watched in.
Future<FocusNode> _startPlaying(WidgetTester tester) async {
  await tester.pumpWidget(_host(overlay: true));
  final node = _nodeOf(tester, 'overlay');
  node.requestFocus();
  await tester.pump();
  expect(node.hasPrimaryFocus, isTrue);
  return node;
}

void main() {
  setUp(NavRegistry.instance.clear);

  group('the framework assertion', () {
    testWidgets('a Visibility coming back into view aborts the frame unless '
        'semantics are maintained', (tester) async {
      // Why `maintainSemantics: true` is in `app.dart`, and what happens without
      // it. The assertion is `!semantics.parentDataDirty`, thrown from
      // `RenderObject.debugCheckForParentData` during `flushSemantics` — which
      // runs *before* `BuildOwner.finalizeTree()`, so the deactivated subtree is
      // never unmounted and its focus nodes are never disposed.
      //
      // Note the direction: going hidden is fine, coming back is not.
      await tester.pumpWidget(_host(overlay: true, maintainSemantics: false));
      await tester.pumpWidget(_host(overlay: false, maintainSemantics: false));

      expect(
        tester.takeException(),
        isAssertionError,
        reason: 'if this stops throwing, the Flutter bug has been fixed '
            'upstream and the maintainSemantics workaround can go',
      );
    });

    testWidgets('with semantics maintained, the torn-down player actually '
        'unmounts', (tester) async {
      // The consequence that matters: `finalizeTree()` runs, so the overlay's
      // focusables dispose and unregister. Everything below depends on this, and
      // none of it could work while the frame was being aborted.
      await _startPlaying(tester);
      await tester.pumpWidget(_host(overlay: false));

      expect(tester.takeException(), isNull);
      expect(NavRegistry.instance.nodesIn('overlay'), isEmpty);
    });
  });

  group('what is actually true at teardown', () {
    testWidgets('the focused node no longer reports holding focus', (
      tester,
    ) async {
      // Flutter tears a Focus widget down from the inside out: the child `Focus`
      // element unmounts before the parent `Focusable` does, and detaching its
      // attachment clears the node's manager. So `unregister`'s old
      // `if (node.hasFocus)` test could never be true — which is why the
      // registry now tracks the focused node itself.
      final node = await _startPlaying(tester);
      await tester.pumpWidget(_host(overlay: false));

      expect(node.hasFocus, isFalse);
    });

    testWidgets('focus falls back to an ancestor, which is neither null nor '
        'context-less', (tester) async {
      // The two inert guards. `moveFocus` tested `primary == null`; the
      // application's `_restoreFocus` tested `primaryFocus?.context == null`.
      // Neither was ever satisfied.
      //
      // Which ancestor it is depends on the tree — the nearest enclosing `Focus`
      // if there is one, the view's scope otherwise — and that is precisely why
      // the test is "is it one of ours" rather than "is it of type X".
      //
      // Watched through a listener rather than read afterwards, because recovery
      // now moves focus off it within the same pump. The point is that this state
      // is passed *through*, not that it persists.
      await _startPlaying(tester);

      final seen = <FocusNode?>[];
      void watch() => seen.add(FocusManager.instance.primaryFocus);
      FocusManager.instance.addListener(watch);
      addTearDown(() => FocusManager.instance.removeListener(watch));

      await tester.pumpWidget(_host(overlay: false));

      final fallback = seen.firstWhere(
        (node) => node != null && !NavRegistry.instance.isOurs(node),
        orElse: () => null,
      );
      expect(
        fallback,
        isNotNull,
        reason: 'focus should have passed through a node that is not a '
            'Focusable — if it went straight to null, the two old guards were '
            'not inert after all',
      );
      expect(fallback!.context, isNotNull);
    });

    testWidgets('a disposed node still reports the context it had', (
      tester,
    ) async {
      // Why usability cannot be judged on the context: `FocusNode.dispose` does
      // not clear it. A node whose widget is gone looked perfectly restorable.
      await tester.pumpWidget(_host(overlay: true));
      final gone = _nodeOf(tester, 'overlay');
      await tester.pumpWidget(_host(overlay: false));

      expect(gone.context, isNotNull);
      expect(gone.parent, isNull);
    });
  });

  group('recovery', () {
    testWidgets('the registry recovers focus by itself', (tester) async {
      // The "focus is never lost" guarantee, now that it is keyed on something
      // that is true. No input required: the microtask scheduled by `unregister`
      // does it.
      await _startPlaying(tester);
      await tester.pumpWidget(_host(overlay: false));
      await tester.pump();

      expect(NavRegistry.instance.hasRealFocus, isTrue);
    });

    testWidgets('a direction recovers focus even when nothing has', (
      tester,
    ) async {
      // The self-healing half, and the one that actually answers the symptom:
      // however focus came to be parked on something that is not a focusable,
      // the next press on the pad gets out of it. Parked deliberately on the root
      // [Focus] here, so the test does not depend on the recovery above having
      // run — and because that node's rectangle is the whole screen, which is the
      // thing that made every direction score as impossible.
      await tester.pumpWidget(_host(overlay: false));
      _root.requestFocus();
      await tester.pump();
      expect(NavRegistry.instance.hasRealFocus, isFalse);

      expect(moveFocus(_below!, InputAction.down), isTrue);
      await tester.pump();

      expect(NavRegistry.instance.hasRealFocus, isTrue);
    });

    testWidgets('the viewer goes back to the card the film started from', (
      tester,
    ) async {
      // The whole round trip, and the reason this is worth more than a generic
      // recovery: `screen-b` is not what "sensible" would pick — `screen-a` is,
      // being first — so only a deliberate restoration puts the viewer back where
      // they actually were.
      await tester.pumpWidget(_host(overlay: false));
      final card = _nodeOf(tester, 'screen-b');
      card.requestFocus();
      await tester.pump();

      await tester.pumpWidget(_host(overlay: true));
      await tester.pump();

      // Hidden, the card cannot take focus at all, which is why the application
      // restores after the frame rather than during it.
      expect(NavRegistry.instance.restoreFocusTo(card), isFalse);

      await tester.pumpWidget(_host(overlay: false));
      expect(NavRegistry.instance.restoreFocusTo(card), isTrue);
      await tester.pump();

      expect(card.hasPrimaryFocus, isTrue);
    });

    testWidgets('a deliberate restoration is not overruled by the net', (
      tester,
    ) async {
      // Both fire on the same teardown, and the net resolves first — it is a
      // microtask scheduled during the frame, while the application restores from
      // a post-frame callback whose focus request needs a microtask of its own to
      // land. Without [NavRegistry.restoreFocusTo] recording intent synchronously,
      // the net would see no focus yet and send the viewer to `screen-a`.
      await tester.pumpWidget(_host(overlay: false));
      final card = _nodeOf(tester, 'screen-b');
      card.requestFocus();
      await tester.pump();

      await _startPlaying(tester);

      await tester.pumpWidget(_host(overlay: false));
      NavRegistry.instance.restoreFocusTo(card);
      await tester.pump();

      expect(card.hasPrimaryFocus, isTrue);
    });

    testWidgets('restoreFocusTo reports a node that is gone', (tester) async {
      await tester.pumpWidget(_host(overlay: true));
      final gone = _nodeOf(tester, 'overlay');
      await tester.pumpWidget(_host(overlay: false));

      expect(NavRegistry.instance.restoreFocusTo(gone), isFalse);
      expect(NavRegistry.instance.restoreFocusTo(null), isFalse);
    });
  });
}
