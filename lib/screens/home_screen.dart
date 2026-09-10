/// Home: what you were watching, what is next, and the way into everything else.
///
/// See `docs/ui-spec.md` §3.1.
library;

import 'package:flutter/widgets.dart';

import '../components/buttons.dart';
import '../components/card.dart';
import '../components/logo.dart';
import '../components/row.dart';
import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.client,
    required this.onOpen,
    required this.onLibrary,
    required this.onSearch,
    required this.onSettings,
    this.onAmbient,
    super.key,
  });

  final Jellyfin client;

  /// Selection rule, deliberate rather than incidental: **episodes play, films
  /// and series open their detail screen.** Applied by the caller, since only it
  /// knows how to do either.
  final void Function(Item item) onOpen;

  final void Function(Item library) onLibrary;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final void Function(Item item)? onAmbient;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Shelf {
  const _Shelf({
    required this.title,
    required this.items,
    required this.group,
    required this.shape,
  });

  final String title;
  final List<Item> items;
  final String group;
  final CardShape shape;
}

class _HomeScreenState extends State<HomeScreen> {
  List<_Shelf> _resumeShelves = const [];
  List<_Shelf> _latestShelves = const [];
  List<Item> _libraries = const [];
  String? _error;
  bool _loading = true;

  /// Focus is claimed **once**, the first time any content arrives. Doing it on
  /// every change would drag focus back to the top as the later shelves stream
  /// in behind the viewer.
  bool _claimed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.client.resume(),
        widget.client.nextUp(),
        widget.client.libraries(),
      ]);
      if (!mounted) return;

      final resume = results[0];
      final nextUp = results[1];
      final libraries = results[2];

      setState(() {
        _resumeShelves = [
          // Resume first, always. On a television the most likely intent is
          // "carry on with the thing I was already watching".
          if (resume.isNotEmpty)
            _Shelf(
              title: 'Continue Watching',
              items: resume,
              group: 'resume',
              shape: CardShape.still,
            ),
          if (nextUp.isNotEmpty)
            _Shelf(
              title: 'Next Up',
              items: nextUp,
              group: 'next-up',
              shape: CardShape.still,
            ),
        ];
        _libraries = libraries;
        _loading = false;
      });
      _claimFocus();

      // Fetched in parallel and dropped when empty: a library with nothing
      // recently added should not leave an empty heading on the page.
      final latest = await Future.wait([
        for (final library in libraries) widget.client.latest(library.id),
      ]);
      if (!mounted) return;
      setState(() {
        _latestShelves = [
          for (var i = 0; i < libraries.length; i++)
            if (latest[i].isNotEmpty)
              _Shelf(
                title: 'Recently Added in ${libraries[i].name}',
                items: latest[i],
                group: 'latest-${libraries[i].id}',
                shape: CardShape.poster,
              ),
        ];
      });
      _claimFocus();
    } catch (cause) {
      if (!mounted) return;
      setState(() {
        _error = cause is JellyfinException
            ? cause.message
            : 'Could not reach the server.';
        _loading = false;
      });
    }
  }

  void _claimFocus() {
    if (_claimed) return;
    if (_resumeShelves.isEmpty && _libraries.isEmpty) return;
    _claimed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavRegistry.instance.focusSomethingSensible();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return ListView(
      padding: EdgeInsets.symmetric(vertical: metrics.safeY),
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: metrics.safeX,
            right: metrics.safeX,
            bottom: Metrics.rem(2),
          ),
          child: Row(
            children: [
              const Logo(size: 34, wordmark: true),
              const Spacer(),
              Pill(label: 'Search', group: 'chrome', onSelect: widget.onSearch),
              SizedBox(width: Metrics.rem(0.6)),
              Pill(
                label: 'Settings',
                group: 'chrome',
                onSelect: widget.onSettings,
              ),
            ],
          ),
        ),

        if (_loading)
          _state(context, 'Loading your library…')
        else if (_error != null)
          _state(context, _error!, colour: tokens.danger)
        else ...[
          for (final shelf in _resumeShelves) _row(shelf),

          // The way into everything, rather than only what is recent or
          // unfinished.
          if (_libraries.isNotEmpty)
            _Libraries(
              libraries: _libraries,
              client: widget.client,
              onSelect: widget.onLibrary,
            ),

          for (final shelf in _latestShelves) _row(shelf),

          if (_resumeShelves.isEmpty && _libraries.isEmpty)
            _state(
              context,
              'Nothing here yet. Add some films or shows to your Jellyfin '
              'libraries.',
            ),
        ],
      ],
    );
  }

  Widget _row(_Shelf shelf) => MediaRow(
    title: shelf.title,
    items: shelf.items,
    client: widget.client,
    group: shelf.group,
    shape: shelf.shape,
    onSelect: widget.onOpen,
    onFocusItem: widget.onAmbient,
  );

  Widget _state(BuildContext context, String message, {Color? colour}) =>
      Padding(
        padding: EdgeInsets.symmetric(horizontal: context.metrics.safeX),
        child: Text(
          message,
          style: Type.body.copyWith(color: colour ?? context.tokens.inkDim),
        ),
      );
}

/// Library tiles: **wider *and* shorter than a poster**, on purpose, because a
/// library is a place rather than a title and should not be mistaken for one at
/// a glance.
class _Libraries extends StatelessWidget {
  const _Libraries({
    required this.libraries,
    required this.client,
    required this.onSelect,
  });

  final List<Item> libraries;
  final Jellyfin client;
  final void Function(Item library) onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(2.6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: metrics.safeX,
              bottom: Metrics.rem(0.9),
            ),
            child: Text(
              'Libraries',
              style: Type.heading.copyWith(color: tokens.inkDim),
            ),
          ),
          SizedBox(
            height:
                metrics.libraryTileHeight +
                metrics.focusRoom * 2 +
                Metrics.rem(0.75),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(
                left: metrics.safeX,
                right: metrics.safeX,
                top: metrics.focusRoom,
                bottom: Metrics.rem(0.75),
              ),
              itemCount: libraries.length,
              separatorBuilder: (_, _) => SizedBox(width: Metrics.rem(1.1)),
              itemBuilder: (context, index) => _LibraryTile(
                library: libraries[index],
                client: client,
                onSelect: () => onSelect(libraries[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.library,
    required this.client,
    required this.onSelect,
  });

  final Item library;
  final Jellyfin client;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;
    final image =
        client.imageUrl(library, maxWidth: 640) ??
        client.imageUrl(library, type: 'Backdrop', maxWidth: 640);

    return Focusable(
      group: 'libraries',
      enter: GroupEntry.first,
      onSelect: onSelect,
      child: (context, focused) => Container(
        width: metrics.libraryTileWidth,
        height: metrics.libraryTileHeight,
        decoration: BoxDecoration(
          color: tokens.raised,
          border: Border.all(color: tokens.edge),
          borderRadius: Radii.br,
        ),
        child: ClipRRect(
          borderRadius: Radii.br,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.expand(),
                ),

              // Fixed dark in both themes: the wash and the name sit on library
              // artwork, and artwork has no light mode.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: GlassfinTokens.overTileVeil,
                ),
              ),
              Positioned(
                left: Metrics.rem(1),
                bottom: Metrics.rem(0.85),
                child: Text(
                  library.name,
                  style: Type.heading.copyWith(color: GlassfinTokens.overInk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
