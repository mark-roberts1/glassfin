import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/nav/pointer.dart';

void main() {
  final pointer = PointerMode.instance;

  setUp(pointer.reset);

  test('starts in pad mode', () {
    // A television with no mouse must never show a cursor, so pad is the
    // default rather than something the app switches into.
    expect(pointer.active.value, isFalse);
  });

  test('the first hover is not movement', () {
    // It fires as soon as a window opens under wherever the pointer happens to
    // be resting, which is not the viewer reaching for the mouse.
    expect(pointer.noteMove(const Offset(100, 100)), isFalse);
    expect(pointer.active.value, isFalse);
  });

  test('a genuinely changed position enters pointer mode', () {
    pointer.noteMove(const Offset(100, 100));
    expect(pointer.noteMove(const Offset(140, 100)), isTrue);
    expect(pointer.active.value, isTrue);
  });

  test('a stationary cursor over scrolling content is not movement', () {
    // **The rule this class exists for.** Spatial navigation scrolls content
    // constantly, and every scroll delivers a hover to whatever slides under the
    // cursor. Treating those as movement would knock a controller session into
    // pointer mode every time the viewer pressed Down.
    pointer.noteMove(const Offset(100, 100));
    expect(pointer.noteMove(const Offset(100, 100)), isFalse);
    expect(pointer.noteMove(const Offset(100, 100)), isFalse);
    expect(pointer.active.value, isFalse);
  });

  test('any action returns to pad mode', () {
    pointer.noteMove(const Offset(100, 100));
    pointer.noteMove(const Offset(140, 100));
    expect(pointer.active.value, isTrue);

    pointer.noteAction();
    expect(pointer.active.value, isFalse);
  });

  test('after an action, the next hover at the same place is not movement', () {
    // Otherwise pressing a D-pad button under a resting cursor would flip
    // straight back to pointer mode on the very next repaint.
    pointer.noteMove(const Offset(100, 100));
    pointer.noteMove(const Offset(140, 100));
    pointer.noteAction();

    expect(pointer.noteMove(const Offset(140, 100)), isFalse);
    expect(pointer.active.value, isFalse);

    // Real movement still wakes it up again.
    expect(pointer.noteMove(const Offset(180, 100)), isTrue);
    expect(pointer.active.value, isTrue);
  });

  test('notifies listeners only when the mode actually changes', () {
    var notifications = 0;
    void listener() => notifications++;
    pointer.active.addListener(listener);
    addTearDown(() => pointer.active.removeListener(listener));

    pointer.noteMove(const Offset(100, 100));
    expect(notifications, 0);

    pointer.noteMove(const Offset(140, 100));
    expect(notifications, 1);

    // Still moving, still in pointer mode: a ValueNotifier does not re-notify
    // for the same value, which is what keeps this from rebuilding the tree on
    // every mouse event.
    pointer.noteMove(const Offset(180, 100));
    expect(notifications, 1);
  });
}
