/// Detail: everything worth knowing before pressing Play.
///
/// See `docs/ui-spec.md` §3.5. The hero here is a **different widget** from the
/// ambient backdrop every other screen uses — sharp, 62vh, and veiled by two
/// gradients tuned per theme.
library;

import 'package:flutter/widgets.dart';

import '../components/ambient.dart';
import '../components/buttons.dart';
import '../components/card.dart';
import '../components/screen_header.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../format.dart';
import '../jellyfin/client.dart';
import '../jellyfin/labels.dart';
import '../jellyfin/media_badges.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';
import '../playback/controller.dart';
import '../settings/languages.dart';

/// Enough to recognise the film by; a full cast list is a database, not a
/// screen.
const int castLimit = 12;

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    required this.client,
    required this.item,
    required this.onPlay,
    required this.onOpen,
    required this.onBack,
    super.key,
  });

  final Jellyfin client;
  final Item item;
  final void Function(Item item) onPlay;
  final void Function(Item item) onOpen;
  final VoidCallback onBack;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Item? _detail;
  List<Item> _seasons = const [];
  List<Item> _episodes = const [];
  String? _seasonId;
  Item? _nextEpisode;
  bool _loading = true;
  String? _error;

  /// The full item once it has been fetched, falling back to the summary the
  /// caller already had — so the title and poster are on screen immediately
  /// rather than after a round trip.
  Item get _full => _detail ?? widget.item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fetched = await widget.client.item(widget.item.id);
      if (!mounted) return;
      setState(() => _detail = fetched);

      if (fetched.type == ItemKind.series) {
        final seasons = await widget.client.seasons(fetched.id);
        // Next Up may legitimately have nothing for this series — a show that
        // has been fully watched, or never started.
        final upNext = await widget.client
            .nextUp(limit: 1)
            .catchError((_) => <Item>[]);
        if (!mounted) return;
        setState(() {
          _seasons = seasons;
          _nextEpisode = upNext
              .where((candidate) => candidate.seriesId == fetched.id)
              .firstOrNull;
        });
        if (seasons.isNotEmpty) await _loadSeason(fetched.id, seasons.first.id);
      }
    } catch (cause) {
      if (mounted) {
        setState(
          () => _error = cause is JellyfinException
              ? cause.message
              : 'Could not load this item.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NavRegistry.instance.focusGroup('detail-actions');
        });
      }
    }
  }

  Future<void> _loadSeason(String seriesId, String seasonId) async {
    setState(() => _seasonId = seasonId);
    // The group's contents are about to be replaced wholesale, so its focus
    // memory now points at an episode from a different season.
    NavRegistry.instance.resetGroup('episodes');
    final episodes = await widget.client.episodes(seriesId, seasonId: seasonId);
    if (mounted) setState(() => _episodes = episodes);
  }

  void _play() {
    if (_full.type == ItemKind.series) {
      final target = _nextEpisode ?? _episodes.firstOrNull;
      if (target != null) widget.onPlay(target);
      return;
    }
    widget.onPlay(_full);
  }

  Duration get _resume =>
      ticksToDuration(_full.userData?.playbackPositionTicks ?? 0);

  /// Matches playback's own floor: below this a resume point is not worth
  /// offering, because "resume" would mean restarting a film four seconds in.
  bool get _canResume => _resume > resumeFloor;

  String get _playLabel {
    if (_full.type == ItemKind.series) {
      final next = _nextEpisode;
      if (next == null) return 'Play';
      final code = episodeCode(next);
      return code.isEmpty ? 'Play' : 'Play $code';
    }
    return _canResume ? 'Resume from ${clock(_resume)}' : 'Play';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final item = _full;

    return Stack(
      fit: StackFit.expand,
      children: [
        DetailHero(
          imageUrl:
              widget.client.imageUrl(item, type: 'Backdrop', maxWidth: 1920) ??
              widget.client.imageUrl(item, maxWidth: 1280),
        ),
        ListView(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.safeX,
            vertical: metrics.safeY,
          ),
          children: [
            ScreenHeader(
              title: item.type == ItemKind.series ? 'Series' : 'Film',
              onBack: widget.onBack,
            ),
            _Masthead(
              item: item,
              client: widget.client,
              playLabel: _playLabel,
              canResume: _canResume,
              onPlay: _play,
              onRestart: () => widget.onPlay(_fromTheBeginning(item)),
            ),
            if (_error != null)
              Text(
                _error!,
                style: Type.body.copyWith(color: context.tokens.danger),
              )
            else if (_loading)
              Text(
                'Loading…',
                style: Type.body.copyWith(color: context.tokens.inkDim),
              )
            else ...[
              _Cast(item: item, client: widget.client),
              if (item.type == ItemKind.series) ...[
                if (_seasons.length > 1)
                  _Seasons(
                    seasons: _seasons,
                    currentId: _seasonId,
                    onSelect: (season) => _loadSeason(item.id, season.id),
                  ),
                _Episodes(
                  episodes: _episodes,
                  client: widget.client,
                  onOpen: widget.onOpen,
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }

  /// "Start from the beginning" zeroes the resume point in a **copy** of the
  /// item rather than passing a start position around. Playback's own rule is
  /// "resume from what the item says", and this keeps that the only rule.
  Item _fromTheBeginning(Item item) => Item(
    id: item.id,
    name: item.name,
    type: item.type,
    runTimeTicks: item.runTimeTicks,
    seriesId: item.seriesId,
    seriesName: item.seriesName,
    seriesPrimaryImageTag: item.seriesPrimaryImageTag,
    seasonId: item.seasonId,
    indexNumber: item.indexNumber,
    parentIndexNumber: item.parentIndexNumber,
    imageTags: item.imageTags,
    backdropImageTags: item.backdropImageTags,
    userData: const UserData(),
  );
}

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.item,
    required this.client,
    required this.playLabel,
    required this.canResume,
    required this.onPlay,
    required this.onRestart,
  });

  final Item item;
  final Jellyfin client;
  final String playLabel;
  final bool canResume;
  final VoidCallback onPlay;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final poster = client.imageUrl(item, maxWidth: 600);

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.sizeOf(context).height * 0.04,
        bottom: Metrics.rem(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (poster != null) ...[
            _Poster(url: poster, width: metrics.detailPosterWidth),
            SizedBox(width: Metrics.rem(2.4)),
          ],
          Expanded(child: _Facts(
            item: item,
            playLabel: playLabel,
            canResume: canResume,
            onPlay: onPlay,
            onRestart: onRestart,
          )),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.width});

  final String url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: Radii.brLarge,
        border: Border.all(color: tokens.edge),
        boxShadow: tokens.shadowPoster,
      ),
      child: ClipRRect(
        borderRadius: Radii.brLarge,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) =>
                ColoredBox(color: tokens.raised),
          ),
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({
    required this.item,
    required this.playLabel,
    required this.canResume,
    required this.onPlay,
    required this.onRestart,
  });

  final Item item;
  final String playLabel;
  final bool canResume;
  final VoidCallback onPlay;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;
    final badges = mediaBadges(item);
    final tagline = item.taglines.firstOrNull;
    final crew = _crew(item);

    return ConstrainedBox(
      // A measure, not a pixel width: long lines of body text are hard to track
      // back to the start of from a sofa.
      constraints: BoxConstraints(maxWidth: Type.body.fontSize! * 33),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.name,
            style: Type.px(
              metrics.detailTitleSize,
              weight: Type.medium,
              em: Type.headingEm,
              height: 1.1,
            ).copyWith(color: tokens.ink),
          ),
          SizedBox(height: Metrics.rem(0.35)),
          if (tagline != null && tagline.isNotEmpty) ...[
            Text(
              tagline,
              style: Type.body.copyWith(
                color: tokens.inkDim,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: Metrics.rem(0.7)),
          ],
          _Meta(item: item),
          // What you are about to ask the machine to decode. On a box without
          // hardware decode this is the difference between a smooth film and a
          // stuttering one, so it belongs above the fold rather than in a
          // submenu.
          if (!badges.isEmpty) ...[
            SizedBox(height: Metrics.rem(0.9)),
            _Badges(badges: badges),
          ],
          if (item.overview != null && item.overview!.isNotEmpty) ...[
            SizedBox(height: Metrics.rem(1.2)),
            Text(
              item.overview!,
              // Long synopses push the actions off screen; four lines is enough
              // to decide on, and the rest is rarely read from a sofa.
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Type.px(18, height: 1.55).copyWith(color: tokens.inkDim),
            ),
          ],
          if (crew.isNotEmpty) ...[
            SizedBox(height: Metrics.rem(1.2)),
            for (final entry in crew)
              Padding(
                padding: EdgeInsets.only(bottom: Metrics.rem(0.2)),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${entry.$1}  ',
                        style: Type.rem(
                          0.92,
                        ).copyWith(color: tokens.inkFaint),
                      ),
                      TextSpan(
                        text: entry.$2.take(3).join(', '),
                        style: Type.rem(0.92).copyWith(color: tokens.inkDim),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          SizedBox(height: Metrics.rem(1.4)),
          Wrap(
            spacing: Metrics.rem(0.7),
            runSpacing: Metrics.rem(0.7),
            children: [
              GlassButton(
                label: playLabel,
                group: 'detail-actions',
                tone: ButtonTone.primary,
                // So that arriving on this screen lands on Play rather than on
                // the season pills further down.
                priority: 2,
                padding: EdgeInsets.symmetric(
                  horizontal: Metrics.rem(1.5),
                  vertical: Metrics.rem(0.8),
                ),
                textStyle: Type.rem(1),
                onSelect: onPlay,
              ),
              if (canResume && item.type != ItemKind.series)
                GlassButton(
                  label: 'Start from the beginning',
                  group: 'detail-actions',
                  padding: EdgeInsets.symmetric(
                    horizontal: Metrics.rem(1.5),
                    vertical: Metrics.rem(0.8),
                  ),
                  textStyle: Type.rem(1),
                  onSelect: onRestart,
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<(String, List<String>)> _crew(Item item) {
    List<String> named(String kind) => [
      for (final person in item.people)
        if (person.type == kind) person.name,
    ];

    final directors = named('Director');
    final writers = named('Writer');
    return [
      if (directors.isNotEmpty)
        (directors.length > 1 ? 'Directors' : 'Director', directors),
      if (writers.isNotEmpty)
        (writers.length > 1 ? 'Writers' : 'Writer', writers),
    ];
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = Type.rem(0.95).copyWith(color: tokens.inkDim);
    final runtime = runtimeLabel(item.runtime);
    final rating = item.communityRating;

    return Wrap(
      spacing: Metrics.rem(0.9),
      runSpacing: Metrics.rem(0.4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.productionYear != null)
          Text('${item.productionYear}', style: style),
        if (runtime.isNotEmpty) Text(runtime, style: style),
        if (item.officialRating != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: Metrics.rem(0.4)),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.edge),
              borderRadius: Radii.chip,
            ),
            child: Text(item.officialRating!, style: style),
          ),
        if (rating != null) Text('★ ${rating.toStringAsFixed(1)}', style: style),
        if (item.genres.isNotEmpty)
          Text(item.genres.take(3).join(' · '), style: style),
        if (item.studios.isNotEmpty) Text(item.studios.first, style: style),
      ],
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.badges});

  final MediaBadges badges;

  @override
  Widget build(BuildContext context) {
    final languages = badges.subtitleLanguages;

    return Wrap(
      spacing: Metrics.rem(0.45),
      runSpacing: Metrics.rem(0.45),
      children: [
        // Video badges are solid: resolution and codec are the facts that decide
        // whether this will play well, so they get the loudest treatment on the
        // screen short of the Play button.
        for (final badge in badges.video) _Badge(badge),
        for (final badge in badges.audio) _Badge(badge, quiet: true),
        if (languages.isNotEmpty)
          _Badge(
            'Subtitles: ${languages.take(3).map(languageName).join(', ')}'
            '${languages.length > 3 ? ' …' : ''}',
            quiet: true,
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.quiet = false});

  final String text;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Metrics.rem(0.62),
        vertical: Metrics.rem(0.28),
      ),
      decoration: BoxDecoration(
        color: quiet ? null : tokens.ink,
        border: quiet ? Border.all(color: tokens.edge) : null,
        borderRadius: Radii.badge,
      ),
      child: Text(
        text,
        style: Type.rem(
          0.78,
          weight: Type.medium,
          // Positive tracking: these are set in caps and tight caps close up.
          em: 0.03,
        ).copyWith(color: quiet ? tokens.inkDim : tokens.ground),
      ),
    );
  }
}

/// **Deliberately not focusable.** There is no person screen to open, so a
/// focusable face would be a dead end — and a wrapping grid rather than a
/// scroller, because a row nothing can focus could never be scrolled.
class _Cast extends StatelessWidget {
  const _Cast({required this.item, required this.client});

  final Item item;
  final Jellyfin client;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cast = [
      for (final person in item.people)
        if (person.type == 'Actor') person,
    ].take(castLimit).toList();

    if (cast.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(2.6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: Metrics.rem(1)),
            child: Text(
              'Cast',
              style: Type.heading.copyWith(color: tokens.inkDim),
            ),
          ),
          Wrap(
            spacing: Metrics.rem(1),
            runSpacing: Metrics.rem(1.4),
            children: [
              for (final person in cast)
                SizedBox(
                  width: 150,
                  child: _Person(person: person, client: client),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.person, required this.client});

  final Person person;
  final Jellyfin client;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final face = client.personImageUrl(person);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.raised,
            border: Border.all(color: tokens.edge),
          ),
          child: ClipOval(
            child: face == null
                ? Text(
                    person.name.isEmpty ? '?' : person.name.substring(0, 1),
                    style: Type.rem(1.6).copyWith(color: tokens.inkFaint),
                  )
                : Image.network(
                    face,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),
          ),
        ),
        SizedBox(height: Metrics.rem(0.55)),
        Text(
          person.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.rem(0.9, weight: Type.medium).copyWith(color: tokens.ink),
        ),
        if (person.role != null && person.role!.isNotEmpty)
          Text(
            person.role!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.rem(0.84).copyWith(color: tokens.inkFaint),
          ),
      ],
    );
  }
}

class _Seasons extends StatelessWidget {
  const _Seasons({
    required this.seasons,
    required this.currentId,
    required this.onSelect,
  });

  final List<Item> seasons;
  final String? currentId;
  final void Function(Item season) onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: Metrics.rem(1.5)),
    child: Wrap(
      spacing: Metrics.rem(0.55),
      runSpacing: Metrics.rem(0.55),
      children: [
        for (final season in seasons)
          Pill(
            label: season.name,
            group: 'seasons',
            selected: season.id == currentId,
            onSelect: () => onSelect(season),
          ),
      ],
    ),
  );
}

class _Episodes extends StatelessWidget {
  const _Episodes({
    required this.episodes,
    required this.client,
    required this.onOpen,
  });

  final List<Item> episodes;
  final Jellyfin client;
  final void Function(Item item) onOpen;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(2)),
      child: Wrap(
        spacing: Metrics.rem(1.4),
        runSpacing: Metrics.rem(1.8),
        children: [
          for (final episode in episodes)
            SizedBox(
              width: metrics.stillWidth,
              child: MediaCard(
                item: episode,
                client: client,
                group: 'episodes',
                shape: CardShape.still,
                onSelect: () => onOpen(episode),
              ),
            ),
        ],
      ),
    );
  }
}
