/// A visible way out, plus the name of where you are.
///
/// Back and Escape both work without this, but **a control you can see is the
/// difference between knowing you can leave and hoping you can** — and on a
/// screen whose on-screen keyboard is holding focus, hoping is not enough.
///
/// See `docs/ui-spec.md` §4.3.
library;

import 'package:flutter/widgets.dart';

import '../design/metrics.dart';
import '../design/theme.dart';
import 'buttons.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({required this.title, required this.onBack, super.key});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(1.6)),
      child: Row(
        children: [
          Pill(
            label: 'Back',
            // Shared with Home's Search and Settings pills: they are all the
            // same band of chrome, and moving between them should not require
            // leaving a group.
            group: 'chrome',
            // A literal character rather than an icon, so it takes the font's
            // own weight and sits on the same baseline as the word.
            leading: const Text('‹'),
            onSelect: onBack,
          ),
          SizedBox(width: Metrics.rem(1.2)),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.rem(
                1.35,
                weight: Type.medium,
                em: Type.headingEm,
              ).copyWith(color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}
