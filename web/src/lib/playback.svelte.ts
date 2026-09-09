/**
 * Playback: ask the server what to send, hand the URL to mpv, report back.
 *
 * Track switching is the subtle part. When the server direct-plays, every track
 * is inside the container and mpv can switch instantly. When it transcodes, it
 * transcodes *one* audio track and may burn subtitles into the picture — so
 * changing either means asking the server again with a different index and
 * reloading at the current position. Clients that only ever call
 * `setAudioStream` appear to do nothing on transcoded content.
 */

import { getHost, type NativePlayer } from './host';
import {
  chooseAudioStream,
  chooseSubtitleStream,
  msToTicks,
  relativeStreamIndex,
  ticksToMs,
  type Item,
  type Jellyfin,
  type MediaSegment,
  type MediaSource,
  type MediaStream,
  type SegmentKind
} from './jellyfin';
import { preferences } from './settings.svelte';

/** How often to tell the server where we are. Jellyfin's own clients use ten seconds. */
const PROGRESS_INTERVAL_MS = 10_000;

/** Below this, treat a resume point as "start from the beginning". */
const RESUME_FLOOR_MS = 10_000;

/** How long the transport stays up after the last button press. */
const CHROME_TIMEOUT_MS = 4000;

interface Active {
  item: Item;
  client: Jellyfin;
  source: MediaSource;
  streams: MediaStream[];
  playSessionId: string;
  player: NativePlayer;
  segments: MediaSegment[];
  handled: Set<number>;
  detach: () => void;
  timer: ReturnType<typeof setInterval>;
}

let active: Active | null = null;

export interface SkipOffer {
  kind: SegmentKind;
  label: string;
  endMs: number;
}

export const playback = $state({
  item: null as Item | null,
  positionMs: 0,
  durationMs: 0,
  paused: false,
  loading: false,
  error: null as string | null,
  /** Set while an intro or outro is on screen and the mode is 'prompt'. */
  skip: null as SkipOffer | null,
  /** Whether the transport overlay is showing. */
  chrome: true,

  // Tracks, by absolute MediaStream index. null subtitle means "off".
  audioTracks: [] as MediaStream[],
  subtitleTracks: [] as MediaStream[],
  audioIndex: null as number | null,
  subtitleIndex: null as number | null,
  /** True while a track change is reloading the stream from the server. */
  switching: false
});

export const isPlaying = (): boolean => active !== null;

let chromeTimer: ReturnType<typeof setTimeout> | undefined;

/**
 * Show the transport, and start it fading again. Called on every input during
 * playback: the overlay is how you know the app is alive, so it must appear
 * whenever anyone touches anything.
 */
export function nudgeChrome(): void {
  playback.chrome = true;
  clearTimeout(chromeTimer);
  chromeTimer = setTimeout(() => {
    if (!playback.paused && active) playback.chrome = false;
  }, CHROME_TIMEOUT_MS);
}

// ---- Segments -------------------------------------------------------------

function modeFor(kind: SegmentKind) {
  if (kind === 'Intro') return preferences.value.introSkip;
  if (kind === 'Outro') return preferences.value.outroSkip;
  return 'off';
}

/**
 * Called on every position update. Offers or takes a skip once per segment —
 * `handled` keeps a dismissed intro from reappearing a second later.
 */
function considerSegments(positionMs: number) {
  if (!active) return;

  const inside = active.segments.find(
    (segment) =>
      positionMs >= ticksToMs(segment.StartTicks) && positionMs < ticksToMs(segment.EndTicks)
  );

  if (!inside) {
    playback.skip = null;
    return;
  }
  if (active.handled.has(inside.StartTicks)) return;

  const mode = modeFor(inside.Type);
  if (mode === 'off') return;

  const offer: SkipOffer = {
    kind: inside.Type,
    label: inside.Type === 'Outro' ? 'Skip credits' : 'Skip intro',
    endMs: ticksToMs(inside.EndTicks)
  };

  if (mode === 'auto') {
    active.handled.add(inside.StartTicks);
    void seekTo(offer.endMs);
    return;
  }
  playback.skip = offer;
}

/** Take the offered skip. Bound to the on-screen button and to `select`. */
export function takeSkip(): void {
  const offer = playback.skip;
  if (!offer || !active) return;
  const segment = active.segments.find((s) => ticksToMs(s.EndTicks) === offer.endMs);
  if (segment) active.handled.add(segment.StartTicks);
  playback.skip = null;
  void seekTo(offer.endMs);
}

// ---- Loading --------------------------------------------------------------

/**
 * 'auto' means "decide from preferences once the stream list is known", which
 * is not the same as null ("none"). It matters: resolving preferences needs the
 * server's stream list, but applying them to a *transcode* has to happen before
 * the first load, or the film starts and then visibly restarts.
 */
type TrackChoice = number | null | 'auto';

interface LoadOptions {
  startMs: number;
  audioIndex: TrackChoice;
  subtitleIndex: TrackChoice;
  /** False while reloading for a track change: the session never really stopped. */
  report: boolean;
}

/** Tear down the current mpv session. Reporting is what writes the resume point. */
async function teardown(report: boolean): Promise<void> {
  const session = active;
  active = null;
  if (!session) return;

  clearInterval(session.timer);
  session.detach();
  session.player.stop();

  if (report) {
    session.player.setVideoRectangle(0, 0, 0, 0);
    await session.client
      .reportStopped(session.item.Id, session.playSessionId, msToTicks(playback.positionMs))
      .catch(() => {});
  }
}

function subtitleArgument(
  client: Jellyfin,
  streams: MediaStream[],
  index: number | null
): number | string {
  if (index === null) return -1;
  const stream = streams.find((candidate) => candidate.Index === index);
  if (!stream) return -1;
  if (stream.DeliveryMethod === 'External' && stream.DeliveryUrl) {
    return `#,${client.absoluteUrl(stream.DeliveryUrl)}`;
  }
  return relativeStreamIndex(streams, index, 'Subtitle');
}

async function load(client: Jellyfin, item: Item, options: LoadOptions): Promise<void> {
  const ticks = msToTicks(options.startMs);
  const auto = options.audioIndex === 'auto' || options.subtitleIndex === 'auto';

  let [info, segments] = await Promise.all([
    client.playbackInfo(
      item.Id,
      ticks,
      auto
        ? {}
        : {
            audioStreamIndex: options.audioIndex as number | null,
            subtitleStreamIndex: options.subtitleIndex as number | null
          }
    ),
    client.mediaSegments(item.Id)
  ]);

  let source = info.MediaSources?.[0];
  if (!source) throw new Error('The server returned no playable source for this item.');
  let streams = source.MediaStreams ?? [];

  const prefs = preferences.value;
  let audioIndex =
    options.audioIndex === 'auto'
      ? (chooseAudioStream(streams, prefs.audioLanguage)?.Index ?? null)
      : options.audioIndex;
  let subtitleIndex =
    options.subtitleIndex === 'auto'
      ? prefs.subtitleMode === 'off'
        ? null
        : (chooseSubtitleStream(streams, prefs.subtitleMode, prefs.subtitleLanguage)?.Index ?? null)
      : options.subtitleIndex;

  // A transcode is built around the tracks it was asked for. Having resolved
  // preferences against the real stream list, ask again *before* loading rather
  // than starting the film and restarting it a second later.
  if (auto && source.TranscodingUrl && (audioIndex !== null || subtitleIndex !== null)) {
    info = await client.playbackInfo(item.Id, ticks, {
      audioStreamIndex: audioIndex,
      subtitleStreamIndex: subtitleIndex
    });
    const reselected = info.MediaSources?.[0];
    if (reselected) {
      source = reselected;
      streams = reselected.MediaStreams ?? streams;
    }
  }

  const url = client.streamUrl(source, info.PlaySessionId);
  const host = await getHost();
  const player = host.player;

  const audioRelative = audioIndex != null ? relativeStreamIndex(streams, audioIndex, 'Audio') : 1;

  playback.audioTracks = streams.filter((stream) => stream.Type === 'Audio');
  playback.subtitleTracks = streams.filter((stream) => stream.Type === 'Subtitle');
  playback.audioIndex = audioIndex;
  playback.subtitleIndex = subtitleIndex;
  playback.positionMs = options.startMs;
  playback.durationMs = ticksToMs(source.RunTimeTicks ?? item.RunTimeTicks ?? 0);
  playback.paused = false;
  playback.skip = null;

  const onPosition = (ms: number) => {
    playback.positionMs = ms;
    considerSegments(ms);
  };
  const onDuration = (ms: number) => (playback.durationMs = ms);
  const onPlaying = () => {
    playback.paused = false;
    nudgeChrome();
  };
  const onPaused = () => {
    playback.paused = true;
    playback.chrome = true;
    clearTimeout(chromeTimer);
  };
  const onFinished = () => void stop();
  const onError = (message: string) => {
    playback.error = message;
    void stop();
  };

  player.positionUpdate.connect(onPosition);
  player.updateDuration.connect(onDuration);
  player.playing.connect(onPlaying);
  player.paused.connect(onPaused);
  player.finished.connect(onFinished);
  player.error.connect(onError);

  const detach = () => {
    player.positionUpdate.disconnect(onPosition);
    player.updateDuration.disconnect(onDuration);
    player.playing.disconnect(onPlaying);
    player.paused.disconnect(onPaused);
    player.finished.disconnect(onFinished);
    player.error.disconnect(onError);
  };

  await new Promise<void>((resolve) => {
    player.load(
      url,
      { startMilliseconds: options.startMs, autoplay: true },
      { type: 'video', headers: {}, metadata: item, media: {} },
      audioRelative,
      subtitleArgument(client, streams, subtitleIndex),
      resolve
    );
  });

  // Fill the window. (0, 0, 0, 0) would hide the video layer entirely.
  player.setVideoRectangle(-1, 0, 0, 0);

  const timer = setInterval(() => {
    if (!active) return;
    void client
      .reportProgress(item.Id, info.PlaySessionId, msToTicks(playback.positionMs), playback.paused)
      .catch(() => {
        /* A dropped progress ping is not worth interrupting playback for. */
      });
  }, PROGRESS_INTERVAL_MS);

  active = {
    item,
    client,
    source,
    streams,
    playSessionId: info.PlaySessionId,
    player,
    segments,
    handled: new Set<number>(),
    detach,
    timer
  };

  if (options.report) {
    await client.reportStart(item.Id, info.PlaySessionId, msToTicks(options.startMs));
  }
  nudgeChrome();
}

export async function start(client: Jellyfin, item: Item): Promise<void> {
  await stop();

  playback.loading = true;
  playback.error = null;
  playback.item = item;

  try {
    const resumeTicks = item.UserData?.PlaybackPositionTicks ?? 0;
    const resumeMs = ticksToMs(resumeTicks);
    const startMs = resumeMs > RESUME_FLOOR_MS ? resumeMs : 0;

    await load(client, item, {
      startMs,
      audioIndex: 'auto',
      subtitleIndex: 'auto',
      report: true
    });
  } catch (cause) {
    playback.error = cause instanceof Error ? cause.message : 'Playback failed.';
    playback.item = null;
  } finally {
    playback.loading = false;
  }
}

export async function stop(): Promise<void> {
  await teardown(true);

  playback.item = null;
  playback.positionMs = 0;
  playback.durationMs = 0;
  playback.paused = false;
  playback.skip = null;
  playback.chrome = true;
  playback.audioTracks = [];
  playback.subtitleTracks = [];
  playback.audioIndex = null;
  playback.subtitleIndex = null;
  playback.switching = false;
  clearTimeout(chromeTimer);
}

/** Reload the same item at the same position with different tracks. */
async function reload(audioIndex: number | null, subtitleIndex: number | null): Promise<void> {
  if (!active) return;
  const { client, item } = active;
  const at = playback.positionMs;

  playback.switching = true;
  try {
    await teardown(false);
    await load(client, item, { startMs: at, audioIndex, subtitleIndex, report: false });
  } catch (cause) {
    playback.error = cause instanceof Error ? cause.message : 'Could not change track.';
    await stop();
  } finally {
    playback.switching = false;
  }
}

// ---- Track selection ------------------------------------------------------

export async function setAudioTrack(absoluteIndex: number): Promise<void> {
  if (!active || absoluteIndex === playback.audioIndex) return;

  // A transcode carries one audio track. Switching means asking again.
  if (active.source.TranscodingUrl) {
    await reload(absoluteIndex, playback.subtitleIndex);
    return;
  }

  active.player.setAudioStream(relativeStreamIndex(active.streams, absoluteIndex, 'Audio'));
  playback.audioIndex = absoluteIndex;
  nudgeChrome();
}

export async function setSubtitleTrack(absoluteIndex: number | null): Promise<void> {
  if (!active) return;

  const stream =
    absoluteIndex === null
      ? null
      : active.streams.find((candidate) => candidate.Index === absoluteIndex);

  // Burned-in subtitles are part of the picture; only the server can change them.
  if (stream?.DeliveryMethod === 'Encode') {
    await reload(playback.audioIndex, absoluteIndex);
    return;
  }

  active.player.setSubtitleStream(subtitleArgument(active.client, active.streams, absoluteIndex));
  playback.subtitleIndex = absoluteIndex;
  nudgeChrome();
}

/** Off, then each subtitle track in turn. Bound to the remote's subtitle key. */
export async function cycleSubtitles(): Promise<void> {
  const tracks = playback.subtitleTracks;
  if (tracks.length === 0) return;

  const order: Array<number | null> = [null, ...tracks.map((track) => track.Index)];
  const at = order.indexOf(playback.subtitleIndex);
  await setSubtitleTrack(order[(at + 1) % order.length]);
}

export async function toggleSubtitles(): Promise<void> {
  if (playback.subtitleIndex !== null) {
    await setSubtitleTrack(null);
    return;
  }
  const first = playback.subtitleTracks[0];
  if (first) await setSubtitleTrack(first.Index);
}

export async function cycleAudio(): Promise<void> {
  const tracks = playback.audioTracks;
  if (tracks.length < 2) return;
  const at = tracks.findIndex((track) => track.Index === playback.audioIndex);
  await setAudioTrack(tracks[(at + 1) % tracks.length].Index);
}

// ---- Transport ------------------------------------------------------------

export function togglePause(): void {
  if (!active) return;
  if (playback.paused) active.player.play();
  else active.player.pause();
}

export async function seekTo(targetMs: number): Promise<void> {
  if (!active) return;
  const target = Math.max(0, targetMs);
  playback.positionMs = target;
  active.player.seekTo(target);
}

export async function seekBy(deltaMs: number): Promise<void> {
  await seekTo(playback.positionMs + deltaMs);
}
