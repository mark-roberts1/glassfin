// These fields are private and mutable on purpose: they are replaced through
// updateSettings(), which also reapplies them to mpv. Making them public — which
// is what an initializing formal would require, since a named parameter cannot
// start with an underscore — would let a caller change a setting without mpv
// ever hearing about it.
// ignore_for_file: prefer_initializing_formals

/// Playback: ask the server what to send, hand the URL to mpv, report back.
///
/// Ported from `glassfin_old/web/src/lib/playback.svelte.ts`, which was the
/// subtlest file in that project and is the subtlest file in this one.
///
/// **Track switching is the difficult part.** When the server direct-plays,
/// every track is inside the container and mpv switches instantly. When it
/// transcodes, it transcodes *one* audio track and may burn subtitles into the
/// picture — so changing either means asking the server again with a different
/// index and reloading at the current position. A client that only ever calls
/// the player's own track setter appears to do nothing at all on transcoded
/// content: the menu closes and the film carries on in the wrong language.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../jellyfin/client.dart';
import '../jellyfin/models.dart';
import '../jellyfin/track_choice.dart';
import '../settings/audio_settings.dart';
import '../settings/preferences.dart';
import '../settings/subtitle_appearance.dart';
import '../settings/video_settings.dart';
import 'mpv_config.dart';

/// How often to tell the server where we are. Jellyfin's own clients use ten
/// seconds, and matching them keeps a shared resume point consistent.
const Duration progressInterval = Duration(seconds: 10);

/// Below this, treat a resume point as "start from the beginning" — nobody wants
/// to resume four seconds in.
const Duration resumeFloor = Duration(seconds: 10);

/// How long the transport stays up after the last button press.
const Duration chromeTimeout = Duration(seconds: 4);

/// How long a survivable mpv complaint stays on screen.
///
/// Long enough to read from a sofa, short enough that it does not become part
/// of the picture.
const Duration noticeTimeout = Duration(seconds: 6);

/// How far the arrow keys and the seek buttons move.
const Duration seekStep = Duration(seconds: 30);

/// How far one press of a remote's volume key moves it, out of 100.
///
/// Small enough that a held key ramps smoothly rather than in jumps — the input
/// pipeline repeats a held key every 60ms, so this is a rate as much as a step.
const double volumeStep = 2;

/// Which track to use, where **`auto` is not the same as null**.
///
/// `null` means "none" — subtitles off. `auto` means "decide from preferences
/// once the stream list is known", which cannot be resolved until the server has
/// answered. Collapsing the two is what makes a film start and then visibly
/// restart a second later.
sealed class TrackChoice {
  const TrackChoice();

  /// Resolve from preferences against the real stream list.
  static const TrackChoice auto = _AutoTrack();

  /// No track.
  static const TrackChoice none = _NoTrack();

  /// This specific absolute `MediaStream` index.
  const factory TrackChoice.index(int value) = _IndexedTrack;
}

final class _AutoTrack extends TrackChoice {
  const _AutoTrack();
}

final class _NoTrack extends TrackChoice {
  const _NoTrack();
}

final class _IndexedTrack extends TrackChoice {
  const _IndexedTrack(this.value);
  final int value;
}

/// An intro or credits skip being offered.
@immutable
class SkipOffer {
  const SkipOffer({
    required this.intent,
    required this.label,
    required this.end,
  });

  final SegmentIntent intent;
  final String label;
  final Duration end;
}

/// Everything on screen during playback.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required Jellyfin client,
    required Preferences preferences,
    required VideoSettings video,
    required AudioSettings audio,
    required SubtitleAppearance subtitles,
    Player? player,
  }) : _client = client,
       _preferences = preferences,
       _video = video,
       _audio = audio,
       _subtitles = subtitles,
       _player = player ?? Player();

  Jellyfin _client;
  Preferences _preferences;
  VideoSettings _video;
  AudioSettings _audio;
  SubtitleAppearance _subtitles;
  final Player _player;

  Player get player => _player;

  // ---- Observable state -----------------------------------------------------

  Item? _item;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _paused = false;
  bool _loading = false;
  bool _switching = false;
  bool _chromeVisible = true;
  String? _error;
  SkipOffer? _skip;

  List<MediaStream> _audioTracks = const [];
  List<MediaStream> _subtitleTracks = const [];
  int? _audioIndex;
  int? _subtitleIndex;

  double _volume = 100;

  /// Where the volume was before it was muted, so unmuting puts it back rather
  /// than guessing at 100. Null when not muted.
  double? _volumeBeforeMute;

  double _rate = 1;
  bool _looping = false;
  AspectMode _aspect = AspectMode.auto;

  /// The other episodes of this season, so Previous and Next have somewhere to
  /// go. Empty for a film, which is why both buttons disable rather than vanish
  /// — a control that moves position between items would be worse.
  List<Item> _siblings = const [];
  int _siblingIndex = -1;

  Item? get item => _item;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get paused => _paused;
  bool get loading => _loading;

  /// True while a track change is reloading the stream from the server. The
  /// interface shows this, because a transcode switch takes a visible moment and
  /// silence would read as a crash.
  bool get switching => _switching;

  bool get chromeVisible => _chromeVisible;
  String? get error => _error;
  SkipOffer? get skip => _skip;

  List<MediaStream> get audioTracks => _audioTracks;
  List<MediaStream> get subtitleTracks => _subtitleTracks;
  int? get audioIndex => _audioIndex;
  int? get subtitleIndex => _subtitleIndex;

  bool get isPlaying => _session != null;

  /// 0–100, matching mpv's own scale.
  double get volume => _volume;
  double get rate => _rate;
  bool get looping => _looping;
  AspectMode get aspect => _aspect;

  Duration get remaining {
    final left = _duration - _position;
    return left.isNegative ? Duration.zero : left;
  }

  /// Direct play, direct stream, or transcode — in the terms the server used.
  ///
  /// The one line worth reading when a film stutters or the colours look wrong,
  /// which is exactly why the reference client puts it in Playback Info.
  String get deliveryDescription {
    final source = _session?.source;
    if (source == null) return 'Not playing';
    if (source.isTranscoding) return 'Transcoding (server is re-encoding)';
    if (source.supportsDirectPlay) return 'Direct play';
    return 'Direct stream (remuxed, not re-encoded)';
  }

  bool get hasPrevious => _siblingIndex > 0;
  bool get hasNext =>
      _siblingIndex >= 0 && _siblingIndex < _siblings.length - 1;

  // ---- Internals ------------------------------------------------------------

  _Session? _session;
  Timer? _progressTimer;
  Timer? _chromeTimer;

  /// Clears a non-fatal mpv message again. See the error listener.
  Timer? _noticeTimer;
  final List<StreamSubscription<Object?>> _playerSubscriptions = [];
  bool _ac3FilterApplied = false;
  bool _mpvConfigured = false;

  NativePlayer? get _native {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// Applies every mpv property from the settings.
  ///
  /// Safe to call again when settings change; the AC3 filter is the only part
  /// that is not idempotent, which is why its previous state is tracked.
  Future<void> configureMpv({double? displayFps}) async {
    final native = _native;
    if (native == null) return;

    final properties = <String, String>{
      if (!_mpvConfigured) ...initProperties(),
      ...audioProperties(_audio),
      ...videoProperties(_video, displayFps: displayFps),
      ...subtitleProperties(_subtitles),
    };
    _mpvConfigured = true;

    for (final entry in properties.entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } catch (error) {
        // An unknown property on an older libmpv should not take the
        // application down with it — the rest are still worth applying.
        debugPrint('glassfin: could not set ${entry.key}: $error');
      }
    }

    final wanted = shouldTranscodeToAc3(_audio);
    final change = ac3FilterChange(wanted: wanted, current: _ac3FilterApplied);
    if (change != null) {
      await native.command(change);
      _ac3FilterApplied = wanted;
    }
  }

  void updateSettings({
    Jellyfin? client,
    Preferences? preferences,
    VideoSettings? video,
    AudioSettings? audio,
    SubtitleAppearance? subtitles,
  }) {
    _client = client ?? _client;
    _preferences = preferences ?? _preferences;
    _video = video ?? _video;
    _audio = audio ?? _audio;
    _subtitles = subtitles ?? _subtitles;
    unawaited(configureMpv());
  }

  // ---- Transport chrome -----------------------------------------------------

  /// Show the transport, and start it fading again.
  ///
  /// Called on **every** input during playback: the overlay is how the viewer
  /// knows the application is alive, so it has to appear whenever anyone touches
  /// anything, whatever that button actually did.
  void nudgeChrome() {
    _chromeVisible = true;
    _chromeTimer?.cancel();
    _chromeTimer = Timer(chromeTimeout, () {
      if (!_paused && _session != null) {
        _chromeVisible = false;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  // ---- Segments -------------------------------------------------------------

  /// Called on every position update. Offers or takes a skip once per segment.
  void _considerSegments(Duration position) {
    final session = _session;
    if (session == null) return;

    MediaSegment? inside;
    for (final segment in session.segments) {
      if (position >= segment.start && position < segment.end) {
        inside = segment;
        break;
      }
    }

    if (inside == null) {
      if (_skip != null) {
        _skip = null;
        notifyListeners();
      }
      return;
    }

    // Keyed on StartTicks rather than on the offer, so a dismissed intro does
    // not reappear a second later when the next position update arrives inside
    // the same segment.
    if (session.handled.contains(inside.startTicks)) return;

    final intent = switch (inside.type) {
      SegmentKind.intro => SegmentIntent.intro,
      SegmentKind.outro => SegmentIntent.outro,
      _ => null,
    };
    if (intent == null) return;

    final mode = _preferences.skipModeFor(intent);
    if (mode == SkipMode.off) return;

    final offer = SkipOffer(
      intent: intent,
      label: intent == SegmentIntent.outro ? 'Skip credits' : 'Skip intro',
      end: inside.end,
    );

    if (mode == SkipMode.auto) {
      session.handled.add(inside.startTicks);
      unawaited(seekTo(offer.end));
      return;
    }

    _skip = offer;
    notifyListeners();
  }

  /// Take the offered skip. Bound to the on-screen button and to `select`.
  Future<void> takeSkip() async {
    final offer = _skip;
    final session = _session;
    if (offer == null || session == null) return;

    for (final segment in session.segments) {
      if (segment.end == offer.end) {
        session.handled.add(segment.startTicks);
        break;
      }
    }
    _skip = null;
    notifyListeners();
    await seekTo(offer.end);
  }

  // ---- Starting and stopping ------------------------------------------------

  Future<void> start(Item item) async {
    await stop();

    _loading = true;
    _error = null;
    _item = item;
    notifyListeners();

    try {
      final resume = ticksToDuration(item.userData?.playbackPositionTicks ?? 0);
      // Below the floor, "resume" means restarting a film four seconds in.
      final start = resume > resumeFloor ? resume : Duration.zero;

      await _load(
        item,
        start: start,
        audio: TrackChoice.auto,
        subtitle: TrackChoice.auto,
        report: true,
      );
    } catch (cause) {
      // Logged as well as shown: the message the viewer reads is deliberately
      // short, and the cause is what actually says what went wrong.
      if (kDebugMode) debugPrint('playback start failed: $cause');
      _error = cause is JellyfinException
          ? cause.message
          : 'Playback failed: $cause';
      _item = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _teardown(report: true);

    _item = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _paused = false;
    _skip = null;
    _chromeVisible = true;
    _audioTracks = const [];
    _subtitleTracks = const [];
    _audioIndex = null;
    _subtitleIndex = null;
    _siblings = const [];
    _siblingIndex = -1;
    _switching = false;
    _chromeTimer?.cancel();
    _noticeTimer?.cancel();
    // Without this the scan timer outlives the film and goes on seeking a player
    // with nothing loaded.
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanRate = 0;
    notifyListeners();
  }

  /// Tear down the current mpv session.
  ///
  /// [report] is false while reloading for a track change: the session never
  /// really stopped, and a stop report mid-switch would write a resume point for
  /// a film that is still playing.
  Future<void> _teardown({required bool report}) async {
    final session = _session;
    _session = null;
    if (session == null) return;

    _progressTimer?.cancel();
    for (final subscription in _playerSubscriptions) {
      await subscription.cancel();
    }
    _playerSubscriptions.clear();
    await _player.stop();

    if (report) {
      try {
        await _client.reportStopped(
          session.item.id,
          session.playSessionId,
          durationToTicks(_position),
        );
      } catch (_) {
        // A failed stop report costs a resume point, not the session.
      }
    }
  }

  // ---- Loading --------------------------------------------------------------

  Future<void> _load(
    Item item, {
    required Duration start,
    required TrackChoice audio,
    required TrackChoice subtitle,
    required bool report,
  }) async {
    final ticks = durationToTicks(start);
    final resolving = audio is _AutoTrack || subtitle is _AutoTrack;

    var info = await _client.playbackInfo(
      item.id,
      startTicks: ticks,
      audioStreamIndex: resolving ? null : _indexOf(audio),
      subtitleStreamIndex: resolving ? null : _indexOf(subtitle),
    );
    final segments = await _client.mediaSegments(item.id);

    if (info.mediaSources.isEmpty) {
      throw const JellyfinException(
        'The server returned no playable source for this item.',
      );
    }
    var source = info.mediaSources.first;
    var streams = source.mediaStreams;

    var audioIndex = audio is _AutoTrack
        ? chooseAudioStream(streams, _preferences.audioLanguage)?.index
        : _indexOf(audio);
    var subtitleIndex = subtitle is _AutoTrack
        ? chooseSubtitleStream(
            streams,
            _preferences.subtitleMode,
            _preferences.subtitleLanguage,
          )?.index
        : _indexOf(subtitle);

    // A transcode is built around the tracks it was asked for. Having resolved
    // preferences against the real stream list, ask again **before** loading
    // rather than starting the film and restarting it a second later.
    if (resolving &&
        source.isTranscoding &&
        (audioIndex != null || subtitleIndex != null)) {
      info = await _client.playbackInfo(
        item.id,
        startTicks: ticks,
        audioStreamIndex: audioIndex,
        subtitleStreamIndex: subtitleIndex,
      );
      if (info.mediaSources.isNotEmpty) {
        source = info.mediaSources.first;
        if (source.mediaStreams.isNotEmpty) streams = source.mediaStreams;
      }
    }

    _audioTracks = streams
        .where((s) => s.type == StreamType.audio)
        .toList(growable: false);
    _subtitleTracks = streams
        .where((s) => s.type == StreamType.subtitle)
        .toList(growable: false);
    _audioIndex = audioIndex;
    _subtitleIndex = subtitleIndex;
    _position = start;
    _duration = ticksToDuration(source.runTimeTicks ?? item.runTimeTicks ?? 0);
    _paused = false;
    _skip = null;

    _session = _Session(
      item: item,
      source: source,
      streams: streams,
      playSessionId: info.playSessionId,
      segments: segments,
    );

    _attachPlayerStreams();
    unawaited(_loadSiblings(item));

    await configureMpv();
    await _player.open(
      Media(
        _client.streamUrl(source, info.playSessionId),
        start: start == Duration.zero ? null : start,
      ),
    );

    await _applyTracksToPlayer(
      streams,
      audioIndex,
      subtitleIndex,
      transcoding: source.isTranscoding,
    );

    _progressTimer = Timer.periodic(progressInterval, (_) {
      unawaited(_reportProgress());
    });

    if (report) {
      try {
        await _client.reportStart(item.id, info.playSessionId, ticks);
      } catch (_) {
        // Failing to announce the start costs the server's "now playing" row,
        // not the film.
      }
    }
    nudgeChrome();
  }

  int? _indexOf(TrackChoice choice) =>
      choice is _IndexedTrack ? choice.value : null;

  void _attachPlayerStreams() {
    _playerSubscriptions.addAll([
      _player.stream.position.listen((position) {
        _position = position;
        _considerSegments(position);
        notifyListeners();
      }),
      _player.stream.duration.listen((duration) {
        // A transcode reports its duration only once it has started, so this
        // arrives after the first frame rather than with the PlaybackInfo.
        if (duration > Duration.zero) {
          _duration = duration;
          notifyListeners();
        }
      }),
      _player.stream.playing.listen((playing) {
        _paused = !playing;
        if (playing) {
          nudgeChrome();
        } else {
          // A paused film keeps its transport up indefinitely: the viewer has
          // walked away, and coming back to a black screen with no controls is
          // indistinguishable from a crash.
          _chromeVisible = true;
          _chromeTimer?.cancel();
          notifyListeners();
        }
      }),
      _player.stream.volume.listen((volume) {
        _volume = volume;
        notifyListeners();
      }),
      _player.stream.rate.listen((rate) {
        _rate = rate;
        notifyListeners();
      }),
      _player.stream.completed.listen((completed) {
        // Roll into the next episode rather than dropping back to the
        // interface, which is what anyone watching a series expects.
        if (!completed) return;
        if (hasNext && !_looping) {
          unawaited(playNext());
        } else {
          unawaited(stop());
        }
      }),
      _player.stream.error.listen((message) {
        // **mpv's error stream is not a stream of fatal errors.** It carries any
        // libmpv log line at error level — a sideloaded subtitle that would not
        // fetch, a filter that would not initialise, a codec probe that failed
        // and was retried. Calling stop() on all of them meant that turning on
        // a subtitle could end the film, which reads exactly like a crash.
        //
        // So: only give up when there is nothing playing to protect. If a
        // session is up and the film is past loading, whatever mpv complained
        // about was survivable — say so and carry on.
        if (kDebugMode) debugPrint('mpv error: $message');
        _error = message;

        if (_session == null || _loading) {
          unawaited(stop());
          return;
        }

        // Shown, then cleared: a permanent red line over a film that is playing
        // perfectly well is its own bug.
        notifyListeners();
        _noticeTimer?.cancel();
        _noticeTimer = Timer(noticeTimeout, () {
          _error = null;
          notifyListeners();
        });
      }),
    ]);
  }

  Future<void> _reportProgress() async {
    final session = _session;
    if (session == null) return;
    try {
      await _client.reportProgress(
        session.item.id,
        session.playSessionId,
        durationToTicks(_position),
        isPaused: _paused,
      );
    } catch (_) {
      // A dropped progress ping is not worth interrupting playback for.
    }
  }

  /// Report where we are right now, outside the timer's schedule.
  ///
  /// **New in this rewrite:** the Qt build only ever reported on its ten-second
  /// timer, so killing the application mid-film threw away up to ten seconds of
  /// resume point. Call this on `AppLifecycleState.detached`.
  Future<void> reportProgressNow() => _reportProgress();

  // ---- Track selection ------------------------------------------------------

  /// A track already inside the container, addressed by its mpv ordinal.
  ///
  /// **Not `AudioTrack.uri`** — that constructor means "an external audio file",
  /// and media_kit turns it into an `audio-add` command, so passing an ordinal
  /// to it makes mpv try to open a file called "2". The plain constructor is
  /// what sets `aid` / `sid`.
  static AudioTrack _embeddedAudio(int ordinal) =>
      AudioTrack('$ordinal', null, null);

  static SubtitleTrack _embeddedSubtitle(int ordinal) =>
      SubtitleTrack('$ordinal', null, null);

  /// Applies the chosen tracks to mpv after a load.
  ///
  /// [transcoding] is not a detail: see [audioOrdinalForPlayer]. Selecting an
  /// audio ordinal on a transcoded stream is how a track change turns into
  /// silence.
  Future<void> _applyTracksToPlayer(
    List<MediaStream> streams,
    int? audioIndex,
    int? subtitleIndex, {
    required bool transcoding,
  }) async {
    final ordinal = audioOrdinalForPlayer(
      streams,
      audioIndex,
      transcoding: transcoding,
    );
    if (ordinal != null) await _player.setAudioTrack(_embeddedAudio(ordinal));
    await _setSubtitleOnPlayer(streams, subtitleIndex);
  }

  /// The three subtitle delivery methods need three different things.
  Future<void> _setSubtitleOnPlayer(
    List<MediaStream> streams,
    int? absoluteIndex,
  ) async {
    if (absoluteIndex == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }

    MediaStream? stream;
    for (final candidate in streams) {
      if (candidate.index == absoluteIndex) {
        stream = candidate;
        break;
      }
    }
    if (stream == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }

    final deliveryUrl = stream.deliveryUrl;
    if (stream.deliveryMethod == DeliveryMethod.external$ &&
        deliveryUrl != null) {
      // Sideloaded from a URL. The server returns it server-relative and mpv is
      // not a browser — it has no page to resolve it against.
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(_client.absoluteUrl(deliveryUrl)),
      );
      return;
    }

    // Embedded: already inside the container mpv has open, addressed by its
    // ordinal among subtitle tracks rather than by Jellyfin's absolute index.
    //
    // **Unverified against a transcode.** This ordinal is counted in the
    // *source's* stream list, which is the mistake that made audio silent — see
    // [audioOrdinalForPlayer]. It is left alone here because a transcode should
    // not reach this branch: the server reports text subtitles as `External`
    // (it extracts them) and bitmap ones as `Encode` (it burns them in), both
    // handled above. If `Embed` ever does arrive alongside a transcode, this
    // ordinal will be counted against a list mpv cannot see and the wrong
    // subtitle — or none — will appear.
    final ordinal = relativeStreamIndex(
      streams,
      absoluteIndex,
      StreamType.subtitle,
    );
    await _player.setSubtitleTrack(
      ordinal > 0 ? _embeddedSubtitle(ordinal) : SubtitleTrack.no(),
    );
  }

  Future<void> setAudioTrack(int absoluteIndex) async {
    final session = _session;
    if (session == null || absoluteIndex == _audioIndex) return;

    // A transcode carries exactly one audio track. Switching means asking the
    // server again — mpv has nothing else to switch *to*.
    if (session.source.isTranscoding) {
      await _reload(audio: absoluteIndex, subtitle: _subtitleIndex);
      return;
    }

    final ordinal = relativeStreamIndex(
      session.streams,
      absoluteIndex,
      StreamType.audio,
    );
    if (ordinal > 0) await _player.setAudioTrack(_embeddedAudio(ordinal));
    _audioIndex = absoluteIndex;
    nudgeChrome();
  }

  Future<void> setSubtitleTrack(int? absoluteIndex) async {
    final session = _session;
    if (session == null) return;

    MediaStream? stream;
    if (absoluteIndex != null) {
      for (final candidate in session.streams) {
        if (candidate.index == absoluteIndex) {
          stream = candidate;
          break;
        }
      }
    }

    // Burned into the picture by the transcoder. Only the server can change it,
    // which means a new PlaybackInfo and a reload — note this is keyed on the
    // *stream's* delivery method, where audio is keyed on the *source's*
    // transcoding URL. The asymmetry is real: a direct-played file can still
    // have a burned-in subtitle requested of it.
    if (stream?.deliveryMethod == DeliveryMethod.encode) {
      await _reload(audio: _audioIndex, subtitle: absoluteIndex);
      return;
    }

    await _setSubtitleOnPlayer(session.streams, absoluteIndex);
    _subtitleIndex = absoluteIndex;
    nudgeChrome();
  }

  /// Reload the same item at the same position with different tracks.
  Future<void> _reload({required int? audio, required int? subtitle}) async {
    final session = _session;
    if (session == null) return;
    final item = session.item;
    final at = _position;

    _switching = true;
    notifyListeners();
    try {
      // report: false — the session never really stopped, and a stop report here
      // would write a resume point for a film that is about to carry on.
      await _teardown(report: false);
      await _load(
        item,
        start: at,
        audio: audio == null ? TrackChoice.none : TrackChoice.index(audio),
        subtitle: subtitle == null
            ? TrackChoice.none
            : TrackChoice.index(subtitle),
        report: false,
      );
    } catch (cause) {
      if (kDebugMode) debugPrint('track change reload failed: $cause');
      _error = cause is JellyfinException
          ? cause.message
          : 'Could not change track: $cause';
      await stop();
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Off, then each subtitle track in turn. Bound to the remote's subtitle key.
  Future<void> cycleSubtitles() async {
    if (_subtitleTracks.isEmpty) return;
    final order = <int?>[
      null,
      for (final track in _subtitleTracks) track.index,
    ];
    final at = order.indexOf(_subtitleIndex);
    await setSubtitleTrack(order[(at + 1) % order.length]);
  }

  Future<void> toggleSubtitles() async {
    if (_subtitleIndex != null) {
      await setSubtitleTrack(null);
      return;
    }
    if (_subtitleTracks.isNotEmpty) {
      await setSubtitleTrack(_subtitleTracks.first.index);
    }
  }

  Future<void> cycleAudio() async {
    if (_audioTracks.length < 2) return;
    final at = _audioTracks.indexWhere((track) => track.index == _audioIndex);
    await setAudioTrack(_audioTracks[(at + 1) % _audioTracks.length].index);
  }

  // ---- Transport ------------------------------------------------------------

  Future<void> togglePause() async {
    if (_session == null) return;
    await _player.playOrPause();
  }

  Future<void> seekTo(Duration target) async {
    if (_session == null) return;
    final clamped = target < Duration.zero ? Duration.zero : target;
    _position = clamped;
    notifyListeners();
    await _player.seek(clamped);
  }

  Future<void> seekBy(Duration delta) => seekTo(_position + delta);

  // ---- Scanning -------------------------------------------------------------

  /// The slowest rate worth having.
  ///
  /// Nothing below 2× is distinguishable from ordinary playback in the forward
  /// direction, and 2× backward is about right for catching a line of dialogue
  /// that was missed — one second of holding moves two seconds of film.
  static const int scanInitialRate = 2;

  /// 32× crosses a feature film in about four minutes, which is as coarse as a
  /// scan can be and still land somewhere on purpose.
  static const int scanMaxRate = 32;

  /// How often the scan moves. Short enough to read as motion rather than as a
  /// series of jumps, long enough that mpv is not asked to seek continuously.
  static const Duration scanTick = Duration(milliseconds: 250);

  /// Scanning forward stops here rather than at the very end, which would
  /// trigger the end-of-file handling and start the next episode.
  static const Duration scanEndGuard = Duration(seconds: 5);

  int _scanRate = 0;
  Timer? _scanTimer;
  bool _pausedBeforeScan = false;

  /// Where the scan has travelled to.
  ///
  /// Tracked here rather than read back from [position] on each tick: mpv's
  /// reported position arrives on a stream and lags a seek slightly, so
  /// accumulating from it makes the rate sag — and sag unevenly, which reads as
  /// the pad being unreliable rather than as the scan being slow.
  Duration _scanTarget = Duration.zero;

  /// Signed: negative is backward, and the magnitude is the multiplier. Zero when
  /// not scanning.
  int get scanRate => _scanRate;
  bool get scanning => _scanRate != 0;

  /// Start scanning, or go twice as fast.
  ///
  /// [direction] is -1 for backward and 1 for forward. Pressing the opposite
  /// direction does not halve the rate — it turns around at the slowest rate,
  /// because the reason anyone presses the other way is that they have overshot
  /// and want to creep back, not that they want to keep going fast the other way.
  Future<void> scan(int direction) async {
    if (_session == null) return;

    final forward = direction > 0;
    final sameWay = _scanRate != 0 && (_scanRate > 0) == forward;
    final magnitude = sameWay
        ? (_scanRate.abs() * 2).clamp(scanInitialRate, scanMaxRate)
        : scanInitialRate;

    if (_scanRate == 0) {
      // **Paused for the duration.** Audio at 8× is noise, and mpv would go on
      // decoding it between seeks.
      _pausedBeforeScan = _paused;
      _scanTarget = _position;
      await _player.pause();
      _scanTimer = Timer.periodic(scanTick, (_) => _advanceScan());
    }

    _scanRate = forward ? magnitude : -magnitude;
    nudgeChrome();
  }

  void _advanceScan() {
    if (_scanRate == 0) return;

    final travelled = scanTick * _scanRate.abs();
    final next = _scanRate > 0
        ? _scanTarget + travelled
        : _scanTarget - travelled;

    if (next <= Duration.zero) {
      _scanTarget = Duration.zero;
      unawaited(seekTo(Duration.zero));
      unawaited(endScan());
      return;
    }

    final ceiling = _duration - scanEndGuard;
    if (_duration > scanEndGuard && next >= ceiling) {
      _scanTarget = ceiling;
      unawaited(seekTo(ceiling));
      unawaited(endScan());
      return;
    }

    _scanTarget = next;
    unawaited(seekTo(next));
    // Holds the transport and the rate indicator up for as long as the scan
    // runs, rather than letting them fade out from under it.
    nudgeChrome();
  }

  /// Stop scanning and carry on from here.
  ///
  /// [resume] false leaves the player paused regardless — for a teardown, where
  /// starting playback on the way out would be absurd.
  Future<void> endScan({bool resume = true}) async {
    if (_scanRate == 0) return;

    _scanTimer?.cancel();
    _scanTimer = null;
    _scanRate = 0;
    notifyListeners();

    // Back to whatever it was doing before. Someone who paused the film and then
    // scanned through it wanted to look, not to watch.
    if (resume && !_pausedBeforeScan) await _player.play();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 100);
    // Moving the volume by any other means is an implicit unmute: coming back
    // from a mute to a *remembered* level would then fight what was just asked
    // for.
    if (_volume > 0) _volumeBeforeMute = null;
    notifyListeners();
    await _player.setVolume(_volume);
  }

  bool get muted => _volume <= 0;

  /// Silence, and back to where it was.
  ///
  /// Not the same as turning the volume down to zero and up again: the level it
  /// returns to is the one it left, so muting to answer the door does not also
  /// lose the level that took a minute to get right. A mute with nothing
  /// remembered — set to zero by hand, then muted — comes back at a level that is
  /// at least audible, since returning to silence would look like a dead button.
  Future<void> toggleMute() async {
    if (muted) {
      final restored = _volumeBeforeMute ?? 50;
      _volumeBeforeMute = null;
      await setVolume(restored);
      return;
    }

    _volumeBeforeMute = _volume;
    _volume = 0;
    notifyListeners();
    await _player.setVolume(0);
  }

  Future<void> setRate(double value) async {
    _rate = value;
    notifyListeners();
    await _player.setRate(value);
  }

  /// Repeat this item. mpv's own `loop-file`, so it costs no bookkeeping here
  /// and survives a seek past the end.
  Future<void> setLooping(bool value) async {
    _looping = value;
    notifyListeners();
    await _native?.setProperty('loop-file', value ? 'inf' : 'no');
  }

  Future<void> setAspect(AspectMode mode) async {
    _aspect = mode;
    notifyListeners();
    final native = _native;
    if (native == null) return;
    for (final entry in mode.properties.entries) {
      try {
        await native.setProperty(entry.key, entry.value);
      } catch (error) {
        debugPrint('glassfin: could not set ${entry.key}: $error');
      }
    }
  }

  /// The next or previous episode of the season.
  ///
  /// Reports progress for the outgoing item first — [start] tears the session
  /// down with `report: true`, so the resume point of the episode being left
  /// behind is written before the new one begins.
  Future<void> playNext() async {
    if (!hasNext) return;
    await start(_siblings[_siblingIndex + 1]);
  }

  Future<void> playPrevious() async {
    if (!hasPrevious) return;
    await start(_siblings[_siblingIndex - 1]);
  }

  /// Which episodes sit either side of this one.
  ///
  /// Failure is silent and simply leaves both buttons disabled: not knowing the
  /// neighbours is a smaller problem than refusing to play the film.
  Future<void> _loadSiblings(Item item) async {
    _siblings = const [];
    _siblingIndex = -1;
    final seriesId = item.seriesId;
    if (item.type != ItemKind.episode || seriesId == null) return;
    try {
      final episodes = await _client.episodes(
        seriesId,
        seasonId: item.seasonId,
      );
      final index = episodes.indexWhere((candidate) => candidate.id == item.id);
      if (index < 0) return;
      _siblings = episodes;
      _siblingIndex = index;
    } catch (_) {
      // Left empty on purpose.
    }
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _noticeTimer?.cancel();
    _progressTimer?.cancel();
    _scanTimer?.cancel();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}

/// The state of one playing item, as opposed to the state shown on screen.
class _Session {
  _Session({
    required this.item,
    required this.source,
    required this.streams,
    required this.playSessionId,
    required this.segments,
  });

  final Item item;
  final MediaSource source;
  final List<MediaStream> streams;
  final String playSessionId;
  final List<MediaSegment> segments;

  /// Segments already taken or dismissed, keyed by start tick.
  final Set<int> handled = {};
}
