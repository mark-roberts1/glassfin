/// The gear menu: aspect ratio, speed, repeat, and what is actually playing.
///
/// Modelled on the reference client's settings popover — a short list of rows,
/// each showing its current value on the right, anchored above the gear that
/// opened it. Rows **cycle** on select rather than opening a submenu, which is
/// the same decision Settings makes and for the same reason: left and right are
/// spoken for, and these lists are three or four items long.
///
/// "Quality" is deliberately absent. In the reference it caps the streaming
/// bitrate, which means a new `PlaybackInfo` and a reload — real work that
/// belongs with the device profile rather than bolted onto a menu.
library;

import 'package:flutter/widgets.dart';

import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../format.dart';
import '../jellyfin/media_badges.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';
import '../playback/controller.dart';
import 'playback_menu.dart' show trackLabel;
import '../settings/video_settings.dart';

const String playerSettingsGroup = 'player-settings';

/// The speeds worth having. Beyond 2x dialogue stops being intelligible, and
/// below 0.75x it is a scrubbing tool rather than a playback speed.
const List<double> playbackRates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

class PlayerSettingsMenu extends StatefulWidget {
  const PlayerSettingsMenu({
    required this.playback,
    required this.onClose,
    super.key,
  });

  final PlaybackController playback;
  final VoidCallback onClose;

  @override
  State<PlayerSettingsMenu> createState() => _PlayerSettingsMenuState();
}

class _PlayerSettingsMenuState extends State<PlayerSettingsMenu> {
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    // Focused by name: a generic "focus something sensible" would reach past
    // this popover to the transport underneath it.
    NavRegistry.instance.resetGroup(playerSettingsGroup);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavRegistry.instance.focusGroup(playerSettingsGroup);
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final playback = widget.playback;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Dimmed, as the reference dims the picture behind its popover.
        const ColoredBox(color: GlassfinTokens.overScrim),
        Positioned(
          right: metrics.safeX,
          bottom: metrics.safeY + Metrics.rem(4),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: metrics.menuMaxHeight,
              maxWidth: Metrics.rem(26),
            ),
            child: SingleChildScrollView(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: GlassfinTokens.overPanel,
                  borderRadius: Radii.br,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _showInfo
                      ? [
                          _Row(
                            name: '‹ Back',
                            value: '',
                            onSelect: () => setState(() => _showInfo = false),
                          ),
                          _PlaybackInfo(playback: playback),
                        ]
                      : [
                          _Row(
                            name: 'Aspect Ratio',
                            value: playback.aspect.label,
                            onSelect: () => _cycleAspect(playback),
                          ),
                          _Row(
                            name: 'Playback Speed',
                            value: _rateLabel(playback.rate),
                            onSelect: () => _cycleRate(playback),
                          ),
                          _Row(
                            name: 'Repeat Mode',
                            value: playback.looping ? 'Repeat one' : 'None',
                            onSelect: () =>
                                playback.setLooping(!playback.looping),
                          ),
                          _Row(
                            name: 'Playback Info',
                            value: '',
                            onSelect: () => setState(() => _showInfo = true),
                          ),
                        ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _cycleAspect(PlaybackController playback) {
    const modes = AspectMode.values;
    playback.setAspect(modes[(playback.aspect.index + 1) % modes.length]);
  }

  void _cycleRate(PlaybackController playback) {
    final index = playbackRates.indexWhere(
      (rate) => (rate - playback.rate).abs() < 0.01,
    );
    playback.setRate(playbackRates[(index + 1) % playbackRates.length]);
  }

  /// `1x` rather than `1.0x`, matching the reference.
  static String _rateLabel(double rate) {
    final text = rate.toStringAsFixed(2);
    return '${text.replaceFirst(RegExp(r'\.?0+$'), '')}x';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.value, required this.onSelect});

  final String name;
  final String value;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Focusable(
    group: playerSettingsGroup,
    visual: FocusVisual.overVideoSurface,
    onSelect: onSelect,
    child: (context, focused) => AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.ease,
      padding: EdgeInsets.symmetric(
        horizontal: Metrics.rem(1.1),
        vertical: Metrics.rem(0.8),
      ),
      // The reference lights the row under the cursor; here it is the focused
      // row, which is the same idea reached by a different input.
      color: focused ? GlassfinTokens.overHighlight : const Color(0x00000000),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: Type.body.copyWith(color: GlassfinTokens.overInk),
            ),
          ),
          if (value.isNotEmpty) ...[
            SizedBox(width: Metrics.rem(1.5)),
            Text(
              value,
              style: Type.body.copyWith(color: GlassfinTokens.overInkDim),
            ),
          ],
        ],
      ),
    ),
  );
}

/// What the machine is actually doing — the question "Playback Info" exists to
/// answer, and the one worth asking when something stutters.
class _PlaybackInfo extends StatelessWidget {
  const _PlaybackInfo({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final item = playback.item;
    final badges = item == null ? null : mediaBadges(item);
    final audio = _streamFor(playback.audioTracks, playback.audioIndex);
    final subtitle = _streamFor(
      playback.subtitleTracks,
      playback.subtitleIndex,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Metrics.rem(1.1),
        vertical: Metrics.rem(0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The single most useful line here: whether the server is re-encoding
          // this, which is what a stutter or a wrong-looking picture usually
          // comes down to.
          _fact('Delivery', playback.deliveryDescription),
          if (badges != null && badges.video.isNotEmpty)
            _fact('Video', badges.video.join(' · ')),
          _fact('Audio', audio == null ? 'None' : _describe(audio)),
          _fact('Subtitles', subtitle == null ? 'Off' : _describe(subtitle)),
          _fact('Speed', '${playback.rate}x'),
          _fact('Position', clock(playback.position)),
          _fact('Duration', clock(playback.duration)),
        ],
      ),
    );
  }

  static MediaStream? _streamFor(List<MediaStream> streams, int? index) {
    if (index == null) return null;
    for (final stream in streams) {
      if (stream.index == index) return stream;
    }
    return null;
  }

  /// The same label the track menu uses, rather than a second implementation of
  /// it — the two had drifted, and this one still showed "English - ASS".
  static String _describe(MediaStream stream) => trackLabel(stream);

  Widget _fact(String name, String value) => Padding(
    padding: EdgeInsets.only(bottom: Metrics.rem(0.3)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: Metrics.rem(6),
          child: Text(
            name,
            style: Type.rem(0.85).copyWith(color: GlassfinTokens.overInkFaint),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Type.rem(0.85).copyWith(color: GlassfinTokens.overInk),
          ),
        ),
      ],
    ),
  );
}
