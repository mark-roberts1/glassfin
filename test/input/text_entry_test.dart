import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/input/text_entry.dart';

TextEntrySession _session(TextEditingController controller) =>
    TextEntrySession(label: 'Server address', controller: controller);

void main() {
  group('insert', () {
    test('appends to an empty field', () {
      final controller = TextEditingController();
      _session(controller).insert('n');
      expect(controller.text, 'n');
      expect(controller.selection.baseOffset, 1);
    });

    test('inserts at the caret rather than at the end', () {
      // The caret is the whole reason this goes through TextEditingValue: a
      // viewer correcting a character in the middle of a server address must not
      // have the caret thrown to the end after every key.
      // "nas.lo|al:8096" — the caret sits after the sixth character, which is
      // where the missing 'c' belongs.
      final controller = TextEditingController(text: 'nas.loal:8096');
      controller.selection = const TextSelection.collapsed(offset: 6);
      _session(controller).insert('c');
      expect(controller.text, 'nas.local:8096');
      expect(controller.selection.baseOffset, 7);
    });

    test('replaces a selection', () {
      final controller = TextEditingController(text: 'abcdef');
      controller.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
      _session(controller).insert('X');
      expect(controller.text, 'abXf');
      expect(controller.selection.baseOffset, 3);
    });

    test('treats an invalid selection as "at the end"', () {
      // A controller that has never been focused reports offset -1, which is
      // exactly the state the on-screen keyboard starts in.
      final controller = TextEditingController(text: 'nas');
      expect(controller.selection.isValid, isFalse);
      _session(controller).insert('.');
      expect(controller.text, 'nas.');
    });
  });

  group('backspace', () {
    test('deletes the character before the caret', () {
      final controller = TextEditingController(text: 'nasx.local');
      controller.selection = const TextSelection.collapsed(offset: 4);
      _session(controller).backspace();
      expect(controller.text, 'nas.local');
      expect(controller.selection.baseOffset, 3);
    });

    test('deletes a selection whole', () {
      final controller = TextEditingController(text: 'abcdef');
      controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      _session(controller).backspace();
      expect(controller.text, 'aef');
      expect(controller.selection.baseOffset, 1);
    });

    test('does nothing at the start of the field', () {
      final controller = TextEditingController(text: 'nas');
      controller.selection = const TextSelection.collapsed(offset: 0);
      _session(controller).backspace();
      expect(controller.text, 'nas');
    });

    test('does nothing on an empty field', () {
      final controller = TextEditingController();
      _session(controller).backspace();
      expect(controller.text, isEmpty);
    });
  });

  test('clear empties the field and the selection with it', () {
    final controller = TextEditingController(text: 'nas.local:8096');
    controller.selection = const TextSelection.collapsed(offset: 5);
    _session(controller).clear();
    expect(controller.text, isEmpty);
    expect(controller.selection, TextEditingValue.empty.selection);
  });
}
