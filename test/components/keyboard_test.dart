/// Widget tests for the on-screen keyboard.
///
/// Worth having as widget tests rather than by eye: the sticky shift and the
/// caret's position are both things that look fine in a screenshot and are wrong
/// the moment someone uses them.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/components/keyboard.dart';
import 'package:glassfin/design/theme.dart';
import 'package:glassfin/design/tokens.dart';
import 'package:glassfin/input/text_entry.dart';
import 'package:glassfin/nav/registry.dart';

Widget _host(Widget child) => GlassfinTheme(
  tokens: GlassfinTokens.dark,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topCenter, child: child),
  ),
);

void main() {
  setUp(NavRegistry.instance.clear);

  setUp(() {
    // The keyboard is designed for a television, and the test harness defaults
    // to an 800x600 window. Sized generously so an overflow here would be the
    // widget's fault rather than the harness's.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1920, 2400);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('letters type lowercase until Shift is pressed', (tester) async {
    final controller = TextEditingController();
    final session = TextEntrySession(label: 'Search', controller: controller);

    await tester.pumpWidget(
      _host(OnScreenKeyboard(session: session, onDone: () {})),
    );

    // Key faces show the character they will actually type.
    expect(find.text('a'), findsOneWidget);
    expect(find.text('A'), findsNothing);

    // Shift is sticky, not momentary: a D-pad has no second hand.
    NavRegistry.instance.infoFor(_nodeFor(tester, 'Shift'))!.onSelect!();
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('a'), findsNothing);

    NavRegistry.instance.infoFor(_nodeFor(tester, 'A'))!.onSelect!();
    expect(controller.text, 'A');

    // And it stays on until pressed again — the next key is also upper case.
    NavRegistry.instance.infoFor(_nodeFor(tester, 'B'))!.onSelect!();
    expect(controller.text, 'AB');
  });

  testWidgets('the symbol page leaves its keys alone', (tester) async {
    final controller = TextEditingController();
    final session = TextEntrySession(label: 'Search', controller: controller);

    await tester.pumpWidget(
      _host(OnScreenKeyboard(session: session, onDone: () {})),
    );

    NavRegistry.instance.infoFor(_nodeFor(tester, '123'))!.onSelect!();
    await tester.pump();

    expect(find.text('ABC'), findsOneWidget);
    expect(find.text('Shift'), findsNothing);
    NavRegistry.instance.infoFor(_nodeFor(tester, '@'))!.onSelect!();
    expect(controller.text, '@');
  });

  testWidgets('the caret goes before a placeholder and after typed text', (
    tester,
  ) async {
    // With the caret trailing, "nas.local:8096" reads as text the next key will
    // extend — when in fact the next key replaces it.
    final controller = TextEditingController();
    final session = TextEntrySession(
      label: 'Server address',
      controller: controller,
      placeholder: 'nas.local:8096',
    );

    await tester.pumpWidget(
      _host(OnScreenKeyboard(session: session, onDone: () {})),
    );

    expect(
      tester.getTopLeft(find.byKey(caretKey)).dx,
      lessThan(tester.getTopLeft(find.text('nas.local:8096')).dx),
    );

    controller.text = 'nas';
    await tester.pump();

    expect(find.text('nas.local:8096'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(caretKey)).dx,
      greaterThan(tester.getTopLeft(find.text('nas')).dx),
    );
  });

  testWidgets('an obscured field never shows what was typed', (tester) async {
    final controller = TextEditingController(text: 'hunter2');
    final session = TextEntrySession(
      label: 'Password',
      controller: controller,
      obscure: true,
    );

    await tester.pumpWidget(
      _host(OnScreenKeyboard(session: session, onDone: () {})),
    );

    expect(find.text('hunter2'), findsNothing);
    expect(find.text('•••••••'), findsOneWidget);
  });

  testWidgets('Done reports to its host rather than deciding itself', (
    tester,
  ) async {
    // The two hosts mean different things by it: the modal sheet closes, while
    // Search's persistent field moves focus to the results.
    var done = 0;
    final session = TextEntrySession(
      label: 'Search',
      controller: TextEditingController(),
    );

    await tester.pumpWidget(
      _host(OnScreenKeyboard(session: session, onDone: () => done++)),
    );

    NavRegistry.instance.infoFor(_nodeFor(tester, 'Done'))!.onSelect!();
    expect(done, 1);
  });

  testWidgets('every key is registered for traversal', (tester) async {
    // Rule two: if it can be focused it is registered. A key reachable by eye
    // and not by the policy is a dead end.
    await tester.pumpWidget(
      _host(
        OnScreenKeyboard(
          session: TextEntrySession(
            label: 'Search',
            controller: TextEditingController(),
          ),
          onDone: () {},
        ),
      ),
    );

    // 26 letters plus Shift and 123.
    expect(NavRegistry.instance.nodesIn('osk'), hasLength(28));
    // Space, Delete, Clear, Done — a separate group, so the keyboard's focus
    // memory does not put the viewer back on Done when they meant to keep typing.
    expect(NavRegistry.instance.nodesIn('osk-controls'), hasLength(4));
  });
}

/// The focus node behind the key whose face reads [label].
FocusNode _nodeFor(WidgetTester tester, String label) {
  final focus = find.ancestor(
    of: find.text(label),
    matching: find.byType(Focus),
  );
  return tester.widget<Focus>(focus.first).focusNode!;
}
