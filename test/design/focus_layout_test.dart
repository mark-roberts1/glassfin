/// How a focusable sizes itself, and where the ring lands.
///
/// The bug this pins down was visible in a screenshot and invisible in the code:
/// a [Stack] hands its children *loose* constraints by default, so a focusable
/// inside a stretched column shrink-wrapped to its text while the stack itself
/// stayed as wide as its parent demanded — and the ring, positioned against the
/// stack, stretched with it. Every field on the login screen was a full-width
/// blue ring around a button a third as wide.
///
/// Worth a test rather than another look at a screenshot, because it is a
/// constraint-propagation bug: it shows up only when the parent is tight, which
/// is most of the layouts in this application and none of the obvious ones to
/// check by hand.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/design/focus.dart';
import 'package:glassfin/design/theme.dart';
import 'package:glassfin/design/tokens.dart';
import 'package:glassfin/nav/registry.dart';

const _childKey = Key('focusable-child');
const double _panel = 600;

Widget _host(Widget child) => GlassfinTheme(
  tokens: GlassfinTokens.dark,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

/// **The child has to be one that shrink-wraps**, or the test proves nothing.
///
/// A `Container` with a colour and no child *expands* to fill whatever it is
/// given, so an earlier version of this file passed with the bug still present.
/// One with a child sizes to that child under loose constraints and fills under
/// tight ones, which is the distinction being tested.
Widget _focusable() => Focusable(
  group: 'test',
  visual: FocusVisual.ringOnly,
  onSelect: () {},
  child: (context, focused) => Container(
    key: _childKey,
    padding: const EdgeInsets.all(8),
    color: const Color(0xFF123456),
    child: const SizedBox(width: 80, height: 24),
  ),
);

/// What the child measures when nothing is forcing its width: 80 plus padding.
const double _natural = 96;

void main() {
  setUp(NavRegistry.instance.clear);

  testWidgets('fills a parent that gives it a tight width', (tester) async {
    // `CrossAxisAlignment.stretch` is the login screen's own layout, and it means
    // "every child is this wide". The focusable has to honour that.
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: _panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [_focusable()],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(_childKey)).width, _panel);
  });

  testWidgets('shrink-wraps when the parent leaves it free', (tester) async {
    // The other half, and the reason the fix is `passthrough` rather than
    // `expand`: a card in a row must still be its own size. The column is `start`
    // rather than `stretch`, so the width here is genuinely loose.
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: _panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [_focusable()],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(_childKey)).width, _natural);
  });

  testWidgets('the ring tracks the content rather than the parent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: _panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [_focusable()],
          ),
        ),
      ),
    );

    // The ring is drawn `ringWidth` outside the content on every side, so the
    // two are locked together — which is the whole point. Comparing the painted
    // boxes is what would have caught the original.
    final child = tester.getRect(find.byKey(_childKey));
    final stack = tester.getRect(
      find.ancestor(of: find.byKey(_childKey), matching: find.byType(Stack)),
    );

    expect(stack.width, child.width);
    expect(stack.height, child.height);
  });
}
