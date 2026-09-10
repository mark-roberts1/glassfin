/// Typing, which is now an ordinary thing and used not to be.
///
/// **This file is a fraction of what it replaces.** The Qt shell's `EventFilter`
/// returned true for every key press, so a physical keyboard produced no events
/// in the page at all; case was destroyed by the input mapping, and one key could
/// emit several actions. `textentry.svelte.ts` existed to reconstruct typing from
/// that wreckage. Flutter delivers real key events with real case, so all that is
/// left is the part that was always genuinely needed: **a D-pad has no letters on
/// it**, so there has to be an on-screen keyboard, and it has to write into the
/// same place a physical keyboard does.
///
/// That shared place is a [TextEditingController]. A session is open while the
/// keyboard is on screen; both input paths mutate the controller, so a viewer can
/// start a word on a gamepad's keypad and finish it on a keyboard.
library;

import 'package:flutter/widgets.dart';

@immutable
class TextEntrySession {
  const TextEntrySession({
    required this.label,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.persistent = false,
    this.onCommit,
    this.onCancel,
  });

  /// Shown above the field: "Server address", "Search".
  final String label;

  /// The value being edited. Owned by whoever opened the session.
  final TextEditingController controller;

  final String? placeholder;

  /// Shown as bullets. The value itself is never obscured in the controller —
  /// only in what is drawn.
  final bool obscure;

  /// Search's field stays open: Done there means "I have finished typing, move
  /// to the results", not "close the keyboard".
  final bool persistent;

  final VoidCallback? onCommit;
  final VoidCallback? onCancel;

  /// Insert at the caret, replacing any selection.
  ///
  /// Goes through [TextEditingValue] rather than assigning `.text`, so that the
  /// caret ends up after what was typed instead of jumping to the end of the
  /// field — which matters the moment someone corrects a character in the middle
  /// of a server address.
  void insert(String text) {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final replaced =
        selection.textBefore(value.text) +
        text +
        selection.textAfter(value.text);
    controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  /// Delete the selection, or the character before the caret.
  void backspace() {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);

    if (!selection.isCollapsed) {
      controller.value = TextEditingValue(
        text:
            selection.textBefore(value.text) + selection.textAfter(value.text),
        selection: TextSelection.collapsed(offset: selection.start),
      );
      return;
    }
    if (selection.start == 0) return;

    final before = selection.textBefore(value.text);
    controller.value = TextEditingValue(
      text:
          before.substring(0, before.length - 1) +
          selection.textAfter(value.text),
      selection: TextSelection.collapsed(offset: selection.start - 1),
    );
  }

  void clear() => controller.value = TextEditingValue.empty;
}
