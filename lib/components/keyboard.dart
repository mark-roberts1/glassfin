/// The on-screen keyboard: **a grid, not an alphabet strip.**
///
/// A strip is a long horizontal travel — twenty-five presses to reach Z — which
/// is tolerable with a touch remote and miserable with a D-pad. Six columns
/// keeps the worst case to about seven presses in each direction.
///
/// **Shift is sticky, not momentary.** A D-pad has no second hand to hold a
/// modifier with, so it toggles case instead of applying to the next key alone,
/// and every key face shows the character it will actually type.
///
/// See `docs/ui-spec.md` §4.5.
library;

import 'package:flutter/widgets.dart';

import '../design/focus.dart' show Focusable, FocusVisual, ringWidth;
import '../design/metrics.dart';
import '../design/primary_style.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../input/text_entry.dart';
import '../nav/registry.dart';

const List<List<String>> _letters = [
  ['A', 'B', 'C', 'D', 'E', 'F'],
  ['G', 'H', 'I', 'J', 'K', 'L'],
  ['M', 'N', 'O', 'P', 'Q', 'R'],
  ['S', 'T', 'U', 'V', 'W', 'X'],
  ['Y', 'Z'],
];

/// Digits and symbols behind their own key: a password field needs more than the
/// half-dozen that would fit alongside the letters.
const List<List<String>> _symbols = [
  ['0', '1', '2', '3', '4', '5'],
  ['6', '7', '8', '9', '!', '@'],
  ['#', r'$', '%', '^', '&', '*'],
  ['(', ')', '-', '_', '=', '+'],
  ['[', ']', '{', '}', ';', ':'],
  ["'", '"', ',', '.', '<', '>'],
  ['/', '?', '~', '`', r'\', '|'],
];

/// How long a caret spends on each half of its cycle. A hard step, never a fade.
const Duration caretBlink = Duration(milliseconds: 550);

/// So a test can assert the caret sits *before* a placeholder and *after* typed
/// text, which is the one thing about it that is easy to get backwards.
const Key caretKey = ValueKey('glassfin.caret');

class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({
    required this.session,
    required this.onDone,
    super.key,
  });

  final TextEntrySession session;

  /// What Done means, which is not the same in both places this is used: the
  /// modal sheet closes and hands the value back, while Search's inline field
  /// stays open and moves focus to the results.
  final VoidCallback onDone;

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  bool _symbolPage = false;
  bool _shift = false;

  @override
  void initState() {
    super.initState();
    // Focus starts on the keys, not on Done, so the first press types. Named
    // explicitly: a generic "focus the first thing" would reach straight past
    // this sheet to the screen underneath it.
    NavRegistry.instance.resetGroup('osk');
    NavRegistry.instance.resetGroup('osk-controls');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavRegistry.instance.focusGroup('osk');
    });
  }

  /// What a key actually types — lowercase unless shift is on. Symbols are
  /// unaffected by it.
  String _typed(String key) =>
      _symbolPage || _shift ? key : key.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final rows = _symbolPage ? _symbols : _letters;

    // The focus ring is drawn 3px outside its element, and a scrolling
    // ancestor clips it — which is why the ring on a full-width control showed
    // only its top and bottom edges. Reserve the space here so it never does.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ringWidth + 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _EntryField(session: widget.session),
          SizedBox(height: Metrics.rem(1.4)),
          _Keys(
            rows: rows,
            typed: _typed,
            onKey: widget.session.insert,
            symbolPage: _symbolPage,
            shift: _shift,
            onShift: () => setState(() => _shift = !_shift),
            onPage: () => setState(() => _symbolPage = !_symbolPage),
          ),
          SizedBox(height: Metrics.rem(1.4)),
          _Controls(session: widget.session, onDone: widget.onDone),
          SizedBox(height: Metrics.rem(1.4)),
          Text(
            'A keyboard works here too — type straight into the field.',
            textAlign: TextAlign.center,
            style: Type.rem(0.85).copyWith(color: tokens.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// The value being typed, with the caret and the placeholder.
class _EntryField extends StatelessWidget {
  const _EntryField({required this.session});

  final TextEntrySession session;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ConstrainedBox(
      // Full width of whatever hosts this — the centred sheet everywhere else,
      // but Search embeds the keyboard in a pane far narrower than 640px, and a
      // fixed width there overflows it.
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.label,
            style: Type.rem(0.85).copyWith(color: tokens.inkDim),
          ),
          SizedBox(height: Metrics.rem(0.4)),
          Container(
            constraints: BoxConstraints(minHeight: Metrics.rem(3)),
            padding: EdgeInsets.symmetric(
              horizontal: Metrics.rem(0.9),
              vertical: Metrics.rem(0.7),
            ),
            decoration: BoxDecoration(
              color: tokens.raised,
              border: Border.all(color: tokens.edge),
              borderRadius: Radii.br,
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: session.controller,
              builder: (context, value, _) {
                final shown = session.obscure
                    ? '•' * value.text.length
                    : value.text;
                final style = Type.rem(1.4);

                // The caret goes *before* the placeholder and *after* typed
                // text. With the caret trailing, "nas.local:8096" reads as
                // something already typed that the next key will extend — when
                // in fact the next key replaces it. In front, with the text
                // greyed, it reads as what it is: an empty field showing an
                // example.
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: shown.isNotEmpty
                      ? [
                          Text(
                            shown,
                            style: style.copyWith(color: tokens.ink),
                          ),
                          const _Caret(key: caretKey),
                        ]
                      : [
                          const _Caret(key: caretKey),
                          Text(
                            session.placeholder ?? '',
                            style: style.copyWith(color: tokens.inkFaint),
                          ),
                        ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 2px wide, `1.15em` tall, in `accentText`, blinking on a hard step.
///
/// A fade would read as a rendering artefact at three metres; a caret should
/// either be there or not.
class _Caret extends StatefulWidget {
  const _Caret({super.key});

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: caretBlink,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final height = Type.rem(1.4).fontSize! * 1.15;

    // Reduced motion is honoured for the caret, unlike the focus scale: a
    // blinking bar is decoration, and a steady one still marks the position.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _bar(tokens.accentText, height, 1);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _bar(
        tokens.accentText,
        height,
        // steps(1): on for half the cycle, off for the other half.
        _controller.value < 0.5 ? 1 : 0,
      ),
    );
  }

  Widget _bar(Color colour, double height, double opacity) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: SizedBox(
      width: 2,
      height: height,
      child: ColoredBox(color: colour.withValues(alpha: opacity)),
    ),
  );
}

class _Keys extends StatelessWidget {
  const _Keys({
    required this.rows,
    required this.typed,
    required this.onKey,
    required this.symbolPage,
    required this.shift,
    required this.onShift,
    required this.onPage,
  });

  final List<List<String>> rows;
  final String Function(String) typed;
  final void Function(String) onKey;
  final bool symbolPage;
  final bool shift;
  final VoidCallback onShift;
  final VoidCallback onPage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = Metrics.rem(0.55);

      // **Six columns is the invariant; the key size is what flexes.**
      //
      // A fixed key width overflows Search's pane, and an overflowing Wrap does
      // not clip — it reflows, into five columns or four. That silently
      // destroys the one property this layout exists for: the alphabet laid out
      // six across, so Z is about seven presses away rather than twenty-five.
      // The letters would still all be present, which is why it reads as the
      // dimensions merely being "off" rather than as a broken control.
      final preferred = Metrics.rem(3.6);
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : preferred * 6 + gap * 5;
      final keyWidth = ((available - gap * 5) / 6).clamp(
        // A floor as well: below this the faces stop being legible from a sofa,
        // and a horizontal scroll is the better failure.
        Metrics.rem(2.2),
        preferred,
      );
      final wideWidth = keyWidth * 2 + gap;

      return SizedBox(
        width: keyWidth * 6 + gap * 5,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final row in rows)
              for (final key in row)
                _Key(
                  width: keyWidth,
                  label: typed(key),
                  onSelect: () => onKey(typed(key)),
                ),
            if (!symbolPage) ...[
              _Key(
                width: wideWidth,
                label: 'Shift',
                small: true,
                active: shift,
                onSelect: onShift,
              ),
              _Key(
                width: wideWidth,
                label: '123',
                small: true,
                onSelect: onPage,
              ),
            ] else
              _Key(
                width: wideWidth,
                label: 'ABC',
                small: true,
                onSelect: onPage,
              ),
          ],
        ),
      );
    },
  );
}

class _Key extends StatelessWidget {
  const _Key({
    required this.width,
    required this.label,
    required this.onSelect,
    this.small = false,
    this.active = false,
  });

  final double width;
  final String label;
  final VoidCallback onSelect;

  /// Shift, 123 and ABC need room for a word rather than a glyph, so they span
  /// two columns and drop a size.
  final bool small;

  /// The active shift key. **This is the only place gold is used as a fill in
  /// the entire application** — everywhere else it is text or an over-video
  /// accent.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Focusable(
      group: 'osk',
      // Keys are small, so they scale *more* than artwork does.
      visual: FocusVisual.key,
      onSelect: onSelect,
      child: (context, focused) => Container(
        width: width,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(1),
          vertical: Metrics.rem(0.7),
        ),
        decoration: BoxDecoration(
          color: active ? tokens.accent : tokens.raised,
          border: Border.all(color: active ? tokens.accent : tokens.edge),
          borderRadius: Radii.br,
        ),
        child: Text(
          label,
          style: Type.rem(small ? 0.85 : 1.05).copyWith(
            color: active ? tokens.ground : tokens.ink,
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.session, required this.onDone});

  final TextEntrySession session;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: Metrics.rem(0.55),
    runSpacing: Metrics.rem(0.55),
    children: [
      _Control(
        label: 'Space',
        minWidth: Metrics.rem(9),
        onSelect: () => session.insert(' '),
      ),
      _Control(label: 'Delete', onSelect: session.backspace),
      _Control(label: 'Clear', onSelect: session.clear),
      _Control(label: 'Done', primary: true, onSelect: onDone),
    ],
  );
}

class _Control extends StatelessWidget {
  const _Control({
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.minWidth,
  });

  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = PrimaryStyle.resolve(tokens);

    return Focusable(
      // A separate group from the keys, so that the keyboard's own focus memory
      // does not put the viewer back on Done when they meant to keep typing.
      group: 'osk-controls',
      visual: FocusVisual.key,
      onSelect: onSelect,
      child: (context, focused) => Container(
        constraints: BoxConstraints(minWidth: minWidth ?? Metrics.rem(3.6)),
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(1),
          vertical: Metrics.rem(0.7),
        ),
        decoration: BoxDecoration(
          color: primary ? style.fill : tokens.raised,
          border: Border.all(color: primary ? style.border : tokens.edge),
          borderRadius: Radii.br,
        ),
        // Align rather than Container.alignment — see GlassButton. With the
        // latter these four controls each filled the pane and stacked, which
        // made the keyboard tall enough to overflow, which let reveal() scroll
        // the entry field off the top of the screen.
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            style: Type.rem(
              1.05,
              weight: primary ? Type.medium : Type.regular,
            ).copyWith(color: primary ? style.ink : tokens.ink),
          ),
        ),
      ),
    );
  }
}
