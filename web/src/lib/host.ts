/**
 * The native shell, and a stand-in for it.
 *
 * Inside Jellyfin Media Player the C++ shell publishes a set of QObjects over
 * QWebChannel; `nativeshell.js` resolves them as `window.api`. Everything the
 * front end can do that a web page cannot — mpv playback, gamepad and CEC
 * input, persisted settings — arrives through that object.
 *
 * ## Keyboards do not work the way you expect
 *
 * `EventFilter::eventFilter` returns true for every key press: "in konvergo we
 * intercept all keyboard events and translate them into web client actions".
 * A physical keyboard therefore produces **no DOM key events in the shell** —
 * no keydown, no input, nothing an <input> element could bind to. Letters
 * arrive through `hostInput` as single-character actions instead, mapped by
 * resources/inputmaps/keyboard.json.
 *
 * Two consequences worth knowing before writing any text field:
 *
 * 1. Case is lost. `"(?:Shift\+)?([A-Z])": "%1"` maps both `a` and `A` to the
 *    action `"A"`. Search is case-insensitive and hostnames are too, so this
 *    costs little, but it cannot be worked around from here.
 * 2. One key can produce several actions. InputMapping appends every pattern
 *    that matches, so `P` emits both `"P"` and `"play_pause"`. Anything
 *    consuming text must prefer the character and discard the rest.
 *
 * The mock reproduces both quirks deliberately. A text field that works in the
 * browser but not in the shell is the exact bug this is guarding against.
 */

export type Signal<T extends unknown[] = []> = {
  connect(handler: (...args: T) => void): void;
  disconnect(handler: (...args: T) => void): void;
};

/** Semantic actions from src/input — gamepad, HDMI-CEC, keyboard and IR all normalise to these. */
export type KnownAction =
  | 'up' | 'down' | 'left' | 'right'
  | 'select' | 'enter' | 'back' | 'home' | 'menu' | 'exit'
  | 'play' | 'pause' | 'play_pause' | 'stop'
  | 'seek_forward' | 'seek_backward'
  | 'step_forward' | 'step_backward'
  | 'increase_volume' | 'decrease_volume'
  | 'cycle_audio' | 'cycle_subtitles' | 'toggle_subtitles'
  | 'toggle_watched' | 'search'
  | 'space';

/** Single characters arrive as actions too, so the type stays open. */
export type HostAction = KnownAction | (string & {});

/**
 * The character an action types, or null if it types nothing.
 * Actions are single characters, plus the named 'space'.
 */
export function characterFor(action: HostAction): string | null {
  if (action === 'space') return ' ';
  if (action.length === 1) return action;
  return null;
}

/** The first typed character in a batch. One key can emit several actions. */
export function firstCharacter(actions: HostAction[]): string | null {
  for (const action of actions) {
    const character = characterFor(action);
    if (character !== null) return character;
  }
  return null;
}

export interface LoadOptions {
  startMilliseconds: number;
  autoplay: boolean;
}

/** Metadata mpv attaches to the stream. `media` is required but may be empty. */
export interface StreamData {
  type: 'video';
  headers: Record<string, string>;
  metadata: unknown;
  media: Record<string, unknown>;
  frameRate?: number;
}

export interface NativePlayer {
  /** Subtitle argument is a relative track index, -1 for none, or '#,<url>' for an external file. */
  load(
    url: string,
    options: LoadOptions,
    streamData: StreamData,
    audioIndex: number,
    subtitle: number | string,
    done: () => void
  ): void;
  stop(): void;
  play(): void;
  pause(): void;
  seekTo(ms: number): void;
  getPosition(done: (ms: number) => void): void;
  setAudioStream(relativeIndex: number): void;
  setSubtitleStream(subtitle: number | string): void;
  setSubtitleDelay(ms: number): void;
  /** (-1, 0, 0, 0) fills the window; (0, 0, 0, 0) hides the video layer entirely. */
  setVideoRectangle(x: number, y: number, width: number, height: number): void;
  setVolume(volume: number): void;
  setMuted(muted: boolean): void;
  setPlaybackRate(rateTimesThousand: number): void;

  playing: Signal;
  paused: Signal;
  finished: Signal;
  error: Signal<[string]>;
  positionUpdate: Signal<[number]>;
  updateDuration: Signal<[number]>;
  bufferedRangesUpdated: Signal<[unknown]>;
}

export interface NativeInput {
  hostInput: Signal<[HostAction[]]>;
}

/**
 * The shell's own settings, from resources/settings/settings_description.json.
 *
 * The `subtitles` section is mpv's rendering: size, font, colour, border,
 * placement, ASS style override. Those belong to the shell and are written
 * here rather than reimplemented — a web layer cannot restyle what mpv draws.
 *
 * WebChannel has no return values, so getters take a callback.
 */
export interface NativeSettings {
  setValue(section: string, key: string, value: unknown): void;
  allValues(section: string, done: (values: Record<string, unknown>) => void): void;
  sectionValueUpdate: Signal<[string, Record<string, unknown>]>;
}

export interface Host {
  player: NativePlayer;
  input: NativeInput;
  settings: NativeSettings;
  /** True inside the shell. False in a browser, where playback is simulated. */
  readonly native: boolean;
}

declare global {
  interface Window {
    api?: { player: NativePlayer; input: NativeInput; settings: NativeSettings };
    apiPromise?: Promise<{ player: NativePlayer; input: NativeInput; settings: NativeSettings }>;
    qt?: { webChannelTransport: unknown };
  }
}

/** Minimal Qt-style signal, so mock and native objects are interchangeable. */
function signal<T extends unknown[]>(): Signal<T> & { emit(...args: T): void } {
  const handlers = new Set<(...args: T) => void>();
  return {
    connect: (h) => void handlers.add(h),
    disconnect: (h) => void handlers.delete(h),
    emit: (...args: T) => handlers.forEach((h) => h(...args))
  };
}

/**
 * Browser keys to host actions, following resources/inputmaps/keyboard.json.
 * Where the shell emits several actions for one key, so does this.
 */
function actionsForKey(event: KeyboardEvent): HostAction[] {
  const key = event.key;

  const named: Record<string, HostAction[]> = {
    ArrowUp: ['up'],
    ArrowDown: ['down'],
    ArrowLeft: ['left'],
    ArrowRight: ['right'],
    Enter: ['enter'],
    Escape: ['back'],
    Backspace: ['back'],
    Home: ['home'],
    ' ': ['space', 'play_pause'],
    PageUp: ['seek_backward'],
    PageDown: ['seek_forward']
  };
  if (named[key]) return named[key];

  // Letters lose their case in the shell, and carry a second action with them.
  if (/^[a-zA-Z]$/.test(key)) {
    const upper = key.toUpperCase();
    const alsoBound: Record<string, HostAction> = {
      P: 'play_pause', X: 'stop', B: 'back', H: 'home',
      A: 'cycle_audio', L: 'cycle_subtitles', S: 'toggle_subtitles', W: 'toggle_watched'
    };
    return alsoBound[upper] ? [upper, alsoBound[upper]] : [upper];
  }

  if (/^[0-9]$/.test(key)) return [key];
  if (/^[.:_@/-]$/.test(key)) return [key];

  return [];
}

function mockHost(): Host {
  const playing = signal();
  const paused = signal();
  const finished = signal();
  const error = signal<[string]>();
  const positionUpdate = signal<[number]>();
  const updateDuration = signal<[number]>();
  const bufferedRangesUpdated = signal<[unknown]>();
  const hostInput = signal<[HostAction[]]>();

  window.addEventListener('keydown', (event) => {
    const actions = actionsForKey(event);
    if (actions.length === 0) return;
    // The shell swallows every key. Do the same here, so nothing can come to
    // depend on browser behaviour the shell will never provide.
    event.preventDefault();
    hostInput.emit(actions);
  });

  let position = 0;
  let ticker: ReturnType<typeof setInterval> | undefined;
  const stopTicker = () => {
    if (ticker) clearInterval(ticker);
    ticker = undefined;
  };
  const tick = () => {
    stopTicker();
    ticker = setInterval(() => {
      position += 1000;
      positionUpdate.emit(position);
    }, 1000);
  };

  const log = (method: string, ...args: unknown[]) =>
    console.info(`[mock player] ${method}`, ...args);

  const player: NativePlayer = {
    load(url, options, _streamData, _audio, _subtitle, done) {
      log('load', url, options);
      position = options.startMilliseconds;
      updateDuration.emit(90 * 60 * 1000);
      playing.emit();
      tick();
      done();
    },
    stop: () => { log('stop'); stopTicker(); finished.emit(); },
    play: () => { log('play'); playing.emit(); tick(); },
    pause: () => { log('pause'); stopTicker(); paused.emit(); },
    seekTo: (ms) => { log('seekTo', ms); position = ms; positionUpdate.emit(position); },
    getPosition: (done) => done(position),
    setAudioStream: (i) => log('setAudioStream', i),
    setSubtitleStream: (s) => log('setSubtitleStream', s),
    setSubtitleDelay: (ms) => log('setSubtitleDelay', ms),
    setVideoRectangle: (x, y, w, h) => log('setVideoRectangle', x, y, w, h),
    setVolume: (v) => log('setVolume', v),
    setMuted: (m) => log('setMuted', m),
    setPlaybackRate: (r) => log('setPlaybackRate', r),
    playing, paused, finished, error, positionUpdate, updateDuration, bufferedRangesUpdated
  };

  const MOCK_SETTINGS_KEY = 'glassfin.mockShellSettings';
  const sectionValueUpdate = signal<[string, Record<string, unknown>]>();
  const readAll = (): Record<string, Record<string, unknown>> => {
    try {
      return JSON.parse(localStorage.getItem(MOCK_SETTINGS_KEY) ?? '{}');
    } catch {
      return {};
    }
  };

  const settings: NativeSettings = {
    setValue(section, key, value) {
      const all = readAll();
      all[section] = { ...all[section], [key]: value };
      localStorage.setItem(MOCK_SETTINGS_KEY, JSON.stringify(all));
      sectionValueUpdate.emit(section, all[section]);
    },
    allValues(section, done) {
      done(readAll()[section] ?? {});
    },
    sectionValueUpdate
  };

  return { player, input: { hostInput }, settings, native: false };
}

let hostPromise: Promise<Host> | undefined;

export function getHost(): Promise<Host> {
  hostPromise ??= (async () => {
    if (!window.qt?.webChannelTransport && !window.apiPromise) {
      console.info('[glassfin] no native shell; using the mock host');
      return mockHost();
    }
    const api = await window.apiPromise!;
    return { player: api.player, input: api.input, settings: api.settings, native: true };
  })();
  return hostPromise;
}

/**
 * Subscribe to input. Handlers receive the whole batch, because deciding
 * between a character and the semantic action that shares its key requires
 * seeing both. Returns an unsubscribe function.
 */
export async function onHostActions(
  handler: (actions: HostAction[]) => void
): Promise<() => void> {
  const host = await getHost();
  host.input.hostInput.connect(handler);
  return () => host.input.hostInput.disconnect(handler);
}
