/// One library, a page at a time.
///
/// **A page, not the whole thing.** Asking for every item in a large collection
/// costs a slow first paint and a great many image requests, and nobody scrolls
/// two thousand posters with a D-pad. See `docs/ui-spec.md` §3.4.
library;

import 'package:flutter/widgets.dart';

import '../components/buttons.dart';
import '../components/card.dart';
import '../components/screen_header.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';

const int pageSize = 60;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.client,
    required this.library,
    required this.onOpen,
    required this.onBack,
    this.onAmbient,
    super.key,
  });

  final Jellyfin client;
  final Item library;
  final void Function(Item item) onOpen;
  final VoidCallback onBack;
  final void Function(Item item)? onAmbient;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Item> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String get _kind =>
      widget.library.collectionType == 'tvshows' ? 'Series' : 'Movie';

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<List<Item>> _page(int startIndex) async {
    final page = await widget.client.items({
      'parentId': widget.library.id,
      'includeItemTypes': _kind,
      'sortBy': 'SortName',
      'sortOrder': 'Ascending',
      'startIndex': startIndex,
      'limit': pageSize,
    });
    _total = page.totalRecordCount;
    return page.items;
  }

  Future<void> _loadFirstPage() async {
    try {
      final items = await _page(0);
      if (mounted) setState(() => _items = items);
    } catch (cause) {
      if (mounted) {
        setState(
          () => _error = cause is JellyfinException
              ? cause.message
              : 'Could not load this library.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NavRegistry.instance.focusGroup('library');
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _page(_items.length);
      if (mounted) setState(() => _items = [..._items, ...more]);
    } catch (_) {
      // Keep what is already on screen, so the button stays for another try.
      // Replacing a working grid with an error message because the *second*
      // page failed would be a worse outcome than the failure itself.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.safeX,
        vertical: metrics.safeY,
      ),
      children: [
        ScreenHeader(title: widget.library.name, onBack: widget.onBack),
        if (_loading)
          Text('Loading…', style: Type.body.copyWith(color: tokens.inkDim))
        else if (_error != null)
          Text(_error!, style: Type.body.copyWith(color: tokens.danger))
        else if (_items.isEmpty)
          Text(
            'This library is empty.',
            style: Type.body.copyWith(color: tokens.inkDim),
          )
        else ...[
          Padding(
            padding: EdgeInsets.only(bottom: Metrics.rem(1.2)),
            child: Text(
              '$_total ${_kind == 'Series' ? 'series' : 'films'}',
              style: Type.rem(0.9).copyWith(color: tokens.inkDim),
            ),
          ),
          Wrap(
            spacing: Metrics.rem(1.4),
            runSpacing: Metrics.rem(2),
            children: [
              for (final item in _items)
                MediaCard(
                  item: item,
                  client: widget.client,
                  // A grid is aligned to the page, so it keeps the column you
                  // came from rather than jumping to its first tile.
                  group: 'library',
                  enter: GroupEntry.nearest,
                  onSelect: () => widget.onOpen(item),
                  onFocus: widget.onAmbient == null
                      ? null
                      : () => widget.onAmbient!(item),
                ),
            ],
          ),
          if (_hasMore)
            Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                Metrics.rem(1.5),
                0,
                Metrics.rem(2.5),
              ),
              child: Center(
                child: GlassButton(
                  label: _loadingMore
                      ? 'Loading…'
                      : 'Show more (${_items.length} of $_total)',
                  // Its own group: it is one button on a line of its own, and
                  // grouping it with the grid would make Down from the last row
                  // ambiguous.
                  group: 'library-more',
                  centred: true,
                  padding: EdgeInsets.symmetric(
                    horizontal: Metrics.rem(1.6),
                    vertical: Metrics.rem(0.8),
                  ),
                  onSelect: _loadMore,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
