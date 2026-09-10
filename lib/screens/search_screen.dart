/// Search: **the one two-pane screen.**
///
/// The keyboard is inline here rather than a modal sheet, and the field is
/// persistent — Done means "I have finished typing, move to the results", not
/// "close the keyboard". Without the rule between the panes, the keyboard and
/// the results read as one thing. See `docs/ui-spec.md` §3.2.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../components/card.dart';
import '../components/keyboard.dart';
import '../components/screen_header.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../input/text_entry.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';

/// Long enough that a D-pad user is not firing a request per letter.
const Duration searchDebounce = Duration(milliseconds: 350);

/// One letter matches most of a library and is never what anyone meant.
const int minimumTerm = 2;

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.client,
    required this.session,
    required this.onOpen,
    required this.onBack,
    this.onAmbient,
    super.key,
  });

  final Jellyfin client;

  /// Owned by the application root, for two reasons: the term survives leaving
  /// this screen for a detail page and coming back, and physical keystrokes are
  /// routed from up there — a session created here would be invisible to the
  /// key handler.
  final TextEntrySession session;

  final void Function(Item item) onOpen;
  final VoidCallback onBack;
  final void Function(Item item)? onAmbient;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<Item> _results = const [];
  bool _searching = false;
  String _term = '';
  Timer? _debounce;

  /// Discards responses that arrive after a newer query has been sent. Without
  /// it, a slow request for "ali" can land after a fast one for "alien" and
  /// replace the right answer with a stale one.
  int _generation = 0;

  TextEditingController get _controller => widget.session.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _term = _controller.text;
    // The term survives leaving this screen, so coming back has to show what it
    // found last time rather than an empty grid under a full field.
    if (_term.trim().length >= minimumTerm) _run(_term);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final value = _controller.text;
    if (value == _term) return;
    setState(() => _term = value);
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => _run(value));
  }

  Future<void> _run(String value) async {
    final mine = ++_generation;
    if (value.trim().length < minimumTerm) {
      if (mounted) {
        setState(() {
          _results = const [];
          _searching = false;
        });
      }
      return;
    }

    setState(() => _searching = true);
    try {
      final found = await widget.client.search(value.trim());
      if (mine == _generation && mounted) setState(() => _results = found);
    } catch (_) {
      if (mine == _generation && mounted) setState(() => _results = const []);
    } finally {
      if (mine == _generation && mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;
    final width = MediaQuery.sizeOf(context).width;
    // `minmax(340px, 32%)`: a proportion, floored so the keyboard's six columns
    // always fit.
    final paneWidth = (width * 0.32).clamp(340.0, width / 2);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.safeX,
        vertical: metrics.safeY,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(title: 'Search', onBack: widget.onBack),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: paneWidth,
                  child: Container(
                    padding: EdgeInsets.only(right: Metrics.rem(3.5)),
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: tokens.edge)),
                    ),
                    child: SingleChildScrollView(
                      child: OnScreenKeyboard(
                        session: widget.session,
                        // Persistent field: Done moves to the results rather
                        // than closing anything.
                        onDone: () => widget.session.onCommit?.call(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: Metrics.rem(3.5)),
                Expanded(
                  child: _Results(
                    results: _results,
                    searching: _searching,
                    term: _term,
                    client: widget.client,
                    onOpen: widget.onOpen,
                    onAmbient: widget.onAmbient,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.searching,
    required this.term,
    required this.client,
    required this.onOpen,
    required this.onAmbient,
  });

  final List<Item> results;
  final bool searching;
  final String term;
  final Jellyfin client;
  final void Function(Item item) onOpen;
  final void Function(Item item)? onAmbient;

  @override
  Widget build(BuildContext context) {
    if (searching) return _state(context, 'Searching…');
    if (term.trim().length < minimumTerm) {
      return _state(context, 'Type to search your films and series.');
    }
    if (results.isEmpty) {
      // Curly quotes: this is a sentence, not a code listing.
      return _state(context, 'Nothing matched “$term”.');
    }

    return SingleChildScrollView(
      // Focused cards scale to 1.06, so the track needs room or they clip
      // against the divider and the window edge.
      padding: EdgeInsets.fromLTRB(
        Metrics.rem(0.5),
        Metrics.rem(0.75),
        Metrics.rem(1),
        Metrics.rem(2),
      ),
      child: Wrap(
        spacing: Metrics.rem(1.4),
        runSpacing: Metrics.rem(1.8),
        children: [
          for (final item in results)
            MediaCard(
              item: item,
              client: client,
              group: 'search-results',
              onSelect: () => onOpen(item),
              onFocus: onAmbient == null ? null : () => onAmbient!(item),
            ),
        ],
      ),
    );
  }

  Widget _state(BuildContext context, String message) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: Metrics.rem(0.5),
      vertical: Metrics.rem(1.25),
    ),
    child: Text(
      message,
      style: Type.body.copyWith(color: context.tokens.inkDim),
    ),
  );
}
