/// Home — walking-skeleton version.
///
/// Continue Watching and Next Up as one plain row each, enough to prove the
/// chain from the server to a playing file. Phase 5 replaces this with the real
/// Home from `docs/ui-spec.md` §3.1: the ambient backdrop, the chrome pills, the
/// library tiles and a Recently Added shelf per library.
library;

import 'package:flutter/material.dart';

import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';
import '../playback/controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.client,
    required this.playback,
    required this.onSignOut,
    super.key,
  });

  final Jellyfin client;
  final PlaybackController playback;
  final VoidCallback onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Item> _resume = const [];
  List<Item> _nextUp = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resume = await widget.client.resume();
      final nextUp = await widget.client.nextUp();
      if (!mounted) return;
      setState(() {
        _resume = resume;
        _nextUp = nextUp;
        _loading = false;
      });
      // Claim focus once, the first time content arrives. Doing it on every
      // change would drag focus back to the top as later shelves stream in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NavRegistry.instance.focusSomethingSensible();
      });
    } catch (cause) {
      if (mounted) {
        setState(() {
          _error = '$cause';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    if (_loading) {
      return ColoredBox(color: tokens.ground, child: const SizedBox.expand());
    }

    return ColoredBox(
      color: tokens.ground,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(vertical: metrics.safeY),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.safeX),
              child: Row(
                children: [
                  Text(
                    'Glassfin',
                    style: Type.title.copyWith(color: tokens.ink),
                  ),
                  const Spacer(),
                  Focusable(
                    group: 'chrome',
                    // Ring only, no scale: at this size the content is text, and
                    // scaling text resamples it into a blur.
                    visual: FocusVisual.ringOnly,
                    onSelect: widget.onSignOut,
                    borderRadius: BorderRadius.circular(999),
                    child: (context, focused) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.raised,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: tokens.edge),
                      ),
                      child: Text(
                        'Sign out',
                        style: Type.label.copyWith(color: tokens.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.all(metrics.safeX),
                child: Text(
                  _error!,
                  style: Type.body.copyWith(color: tokens.danger),
                ),
              ),
            if (_resume.isNotEmpty)
              _Shelf(
                title: 'Continue Watching',
                group: 'resume',
                items: _resume,
                client: widget.client,
                onSelect: _open,
              ),
            if (_nextUp.isNotEmpty)
              _Shelf(
                title: 'Next Up',
                group: 'next-up',
                items: _nextUp,
                client: widget.client,
                onSelect: _open,
              ),
          ],
        ),
      ),
    );
  }

  void _open(Item item) {
    // The skeleton plays whatever is selected. The real rule, restored in Phase
    // 5: episodes play, films and series open their detail screen first.
    widget.playback.start(item);
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.group,
    required this.items,
    required this.client,
    required this.onSelect,
  });

  final String title;
  final String group;
  final List<Item> items;
  final Jellyfin client;
  final void Function(Item item) onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(2.6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // The heading aligns with the first card while the track itself runs
            // full-bleed off the right edge.
            padding: EdgeInsets.only(left: metrics.safeX, bottom: 8),
            child: Text(
              title,
              style: Type.heading.copyWith(color: tokens.inkDim),
            ),
          ),
          SizedBox(
            height: metrics.stillHeight + metrics.focusRoom + 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // focusRoom as top padding: a scrolling box clips its own
              // overflow, and without it the top of the focus ring is sliced off.
              padding: EdgeInsets.only(
                left: metrics.safeX,
                right: metrics.safeX,
                top: metrics.focusRoom,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (context, index) => _Card(
                item: items[index],
                group: group,
                client: client,
                onSelect: onSelect,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.group,
    required this.client,
    required this.onSelect,
  });

  final Item item;
  final String group;
  final Jellyfin client;
  final void Function(Item item) onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;
    final image = client.imageUrl(item, type: 'Thumb', maxWidth: 640);
    final backdrop = client.imageUrl(item, type: 'Backdrop', maxWidth: 640);
    final url = image ?? backdrop;

    return SizedBox(
      width: metrics.stillWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focusable(
            group: group,
            // A carousel is scrolled to a position the viewer did not choose, so
            // arriving from another group lands on its first item rather than a
            // column pointing at nothing they can see.
            enter: GroupEntry.first,
            onSelect: () => onSelect(item),
            child: (context, focused) => Container(
              width: metrics.stillWidth,
              height: metrics.stillHeight,
              decoration: BoxDecoration(
                color: tokens.raised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.edge),
                image: url == null
                    ? null
                    : DecorationImage(
                        image: NetworkImage(url),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          SizedBox(height: metrics.focusRoom),
          Text(
            item.seriesName == null
                ? item.name
                : '${item.seriesName} — ${item.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Type.body.copyWith(color: tokens.ink),
          ),
        ],
      ),
    );
  }
}
