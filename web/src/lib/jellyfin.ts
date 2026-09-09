/**
 * Jellyfin server API, scoped to movies and series.
 *
 * Hand-rolled rather than @jellyfin/sdk: the surface Glassfin needs is small
 * and fixed, and the SDK brings a generated client and axios into a bundle that
 * competes with software video decode on the target hardware. If the scope ever
 * widens past movies and shows, revisit that trade.
 *
 * Playback decisions are not made here. We send the shell's DeviceProfile to
 * /Items/{id}/PlaybackInfo and the server decides direct play, direct stream,
 * or transcode.
 */

const CLIENT_NAME = 'Glassfin';
const CLIENT_VERSION = '0.1.0';

export type ItemKind = 'Movie' | 'Series' | 'Season' | 'Episode';

export interface MediaStream {
  Index: number;
  Type: 'Video' | 'Audio' | 'Subtitle' | 'EmbeddedImage' | 'Data';
  Codec?: string;
  Language?: string;
  DisplayTitle?: string;
  IsDefault?: boolean;
  IsForced?: boolean;
  DeliveryMethod?: 'External' | 'Embed' | 'Encode' | 'Hls';
  DeliveryUrl?: string;

  // Video
  Width?: number;
  Height?: number;
  VideoRangeType?: string;
  // Audio
  Channels?: number;
  ChannelLayout?: string;
}

export interface MediaSource {
  Id: string;
  Name?: string;
  Container?: string;
  Protocol?: string;
  SupportsDirectPlay?: boolean;
  SupportsDirectStream?: boolean;
  SupportsTranscoding?: boolean;
  TranscodingUrl?: string;
  RunTimeTicks?: number;
  MediaStreams?: MediaStream[];
}

export interface UserData {
  PlaybackPositionTicks?: number;
  PlayCount?: number;
  Played?: boolean;
  IsFavorite?: boolean;
  UnplayedItemCount?: number;
  PlayedPercentage?: number;
}

export type PersonKind = 'Actor' | 'Director' | 'Writer' | 'Producer' | 'GuestStar' | 'Composer';

export interface Person {
  Id: string;
  Name: string;
  Type: PersonKind | string;
  Role?: string;
  /** People carry a single tag rather than the ImageTags map items use. */
  PrimaryImageTag?: string;
}

export interface Item {
  Id: string;
  Name: string;
  Type: ItemKind;
  CollectionType?: string;
  Overview?: string;
  ProductionYear?: number;
  OfficialRating?: string;
  CommunityRating?: number;
  RunTimeTicks?: number;
  Genres?: string[];
  Taglines?: string[];
  Studios?: Array<{ Id: string; Name: string }>;
  People?: Person[];
  CriticRating?: number;
  PremiereDate?: string;
  EndDate?: string;
  Status?: string;
  ImageTags?: Record<string, string>;
  BackdropImageTags?: string[];
  UserData?: UserData;
  MediaSources?: MediaSource[];

  // Series / season / episode relationships
  SeriesId?: string;
  SeriesName?: string;
  SeriesPrimaryImageTag?: string;
  SeasonId?: string;
  SeasonName?: string;
  IndexNumber?: number;
  ParentIndexNumber?: number;
  /*
   * Deliberately no ChildCount. The server sets it to whatever the endpoint
   * happens to be counting — seasons from /Items, recently added episodes from
   * /Items/Latest — so any single reading of it is wrong somewhere. Ask
   * /Shows/{id}/Seasons when a real season count is needed.
   */
}

interface ItemsResponse {
  Items: Item[];
  TotalRecordCount: number;
}

export interface PlaybackInfo {
  MediaSources: MediaSource[];
  PlaySessionId: string;
}

export interface Credentials {
  address: string;
  accessToken: string;
  userId: string;
  userName: string;
}

const STORAGE_KEY = 'glassfin.credentials';
const DEVICE_KEY = 'glassfin.deviceId';

/** Ticks are 100-nanosecond units throughout the Jellyfin API. */
export const TICKS_PER_MS = 10_000;
export const ticksToMs = (ticks: number): number => Math.floor(ticks / TICKS_PER_MS);
export const msToTicks = (ms: number): number => Math.floor(ms * TICKS_PER_MS);

declare global {
  interface Window {
    NativeShell?: {
      AppHost?: {
        getDeviceProfile?(): unknown;
        deviceName?(): string;
        appVersion?(): string;
        exit?(): void;
      };
    };
  }
}

function deviceId(): string {
  let id = localStorage.getItem(DEVICE_KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(DEVICE_KEY, id);
  }
  return id;
}

function deviceName(): string {
  return window.NativeShell?.AppHost?.deviceName?.() ?? 'Glassfin';
}

/**
 * The shell's profile describes what mpv can play, and is the whole reason a
 * new front end does not have to reimplement transcode negotiation. The
 * fallback exists only for browser development; it is deliberately
 * conservative, because an over-generous profile means silent playback
 * failures rather than a transcode.
 */
export function deviceProfile(): unknown {
  const fromShell = window.NativeShell?.AppHost?.getDeviceProfile?.();
  if (fromShell) {
    // The profile still calls itself Jellyfin Desktop, because nativeshell.js is
    // kept byte-identical to upstream so it can be merged (see CLAUDE.md). It is
    // the one string in there that reaches a server, so it is corrected here
    // rather than by editing that file.
    return { ...(fromShell as Record<string, unknown>), Name: 'Glassfin' };
  }

  return {
    Name: 'Glassfin (browser development)',
    MaxStaticBitrate: 100_000_000,
    TranscodingProfiles: [
      { Type: 'Video', Container: 'ts', Protocol: 'hls', VideoCodec: 'h264', AudioCodec: 'aac' }
    ],
    DirectPlayProfiles: [
      { Type: 'Video', Container: 'mp4,webm', VideoCodec: 'h264', AudioCodec: 'aac' }
    ],
    CodecProfiles: [],
    ContainerProfiles: [],
    ResponseProfiles: [],
    SubtitleProfiles: [
      { Format: 'vtt', Method: 'External' },
      { Format: 'srt', Method: 'External' }
    ]
  };
}

/** Jellyfin 10.10+ exposes intro/outro markers natively via /MediaSegments. */
export type SegmentKind = 'Intro' | 'Outro' | 'Recap' | 'Preview' | 'Commercial' | 'Unknown';

export interface MediaSegment {
  Type: SegmentKind;
  StartTicks: number;
  EndTicks: number;
}

/**
 * mpv addresses tracks by their position among tracks of the same type, not by
 * the absolute MediaStream index Jellyfin reports. One-based, matching the
 * shell's own default of 1 for "the first audio track".
 */
export function relativeStreamIndex(
  streams: MediaStream[],
  absoluteIndex: number,
  type: MediaStream['Type']
): number {
  let position = 0;
  for (const stream of streams) {
    if (stream.Type !== type) continue;
    position += 1;
    if (stream.Index === absoluteIndex) return position;
  }
  return -1;
}

const sameLanguage = (stream: MediaStream, code: string): boolean =>
  !!stream.Language && stream.Language.toLowerCase() === code.toLowerCase();

/** Preferred language if present, otherwise the server's default, otherwise the first. */
export function chooseAudioStream(
  streams: MediaStream[],
  preferred: string
): MediaStream | null {
  const audio = streams.filter((stream) => stream.Type === 'Audio');
  if (audio.length === 0) return null;
  if (preferred) {
    const match = audio.find((stream) => sameLanguage(stream, preferred));
    if (match) return match;
  }
  return audio.find((stream) => stream.IsDefault) ?? audio[0];
}

/**
 * Subtitle choice follows the mode rather than guessing:
 * 'off' picks nothing, 'forced' only picks a forced track, and 'preferred'
 * picks the chosen language and otherwise leaves subtitles off rather than
 * turning on a language nobody asked for.
 */
export function chooseSubtitleStream(
  streams: MediaStream[],
  mode: 'off' | 'forced' | 'preferred',
  preferred: string
): MediaStream | null {
  if (mode === 'off') return null;
  const subtitles = streams.filter((stream) => stream.Type === 'Subtitle');
  if (subtitles.length === 0) return null;

  const inLanguage = preferred
    ? subtitles.filter((stream) => sameLanguage(stream, preferred))
    : subtitles;

  if (mode === 'forced') {
    return inLanguage.find((stream) => stream.IsForced) ?? null;
  }
  return (
    inLanguage.find((stream) => stream.IsForced) ??
    inLanguage.find((stream) => stream.IsDefault) ??
    inLanguage[0] ??
    null
  );
}

export interface QuickConnectState {
  code: string;
  secret: string;
}

/** Accepts "nas:8096" as readily as a full URL; trailing slashes are noise. */
export function normaliseAddress(address: string): string {
  const trimmed = address.trim().replace(/\/+$/, '');
  return /^https?:\/\//i.test(trimmed) ? trimmed : `http://${trimmed}`;
}

export class Jellyfin {
  constructor(readonly credentials: Credentials) {}

  static stored(): Jellyfin | null {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    try {
      return new Jellyfin(JSON.parse(raw) as Credentials);
    } catch {
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
  }

  static authHeader(token?: string): string {
    const parts = [
      `Client="${CLIENT_NAME}"`,
      `Device="${deviceName()}"`,
      `DeviceId="${deviceId()}"`,
      `Version="${CLIENT_VERSION}"`
    ];
    if (token) parts.push(`Token="${token}"`);
    return `MediaBrowser ${parts.join(', ')}`;
  }

  static async authenticate(
    address: string,
    username: string,
    password: string
  ): Promise<Jellyfin> {
    const base = normaliseAddress(address);
    const response = await fetch(`${base}/Users/AuthenticateByName`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: Jellyfin.authHeader()
      },
      body: JSON.stringify({ Username: username, Pw: password })
    });

    if (!response.ok) {
      throw new Error(
        response.status === 401
          ? 'That username or password was not accepted.'
          : `The server refused the sign-in (HTTP ${response.status}).`
      );
    }

    const body = await response.json();
    const client = new Jellyfin({
      address: base,
      accessToken: body.AccessToken,
      userId: body.User.Id,
      userName: body.User.Name
    });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(client.credentials));
    return client;
  }

  // ---- Quick Connect ----------------------------------------------------
  //
  // The television answer to signing in: the server shows a code, you approve
  // it from a phone or the web dashboard, and no password is ever typed on a
  // D-pad. The server address still has to be entered once, which is what the
  // on-screen keyboard is for.

  static async quickConnectEnabled(address: string): Promise<boolean> {
    try {
      const response = await fetch(`${normaliseAddress(address)}/QuickConnect/Enabled`, {
        headers: { Authorization: Jellyfin.authHeader() }
      });
      if (!response.ok) return false;
      return (await response.json()) === true;
    } catch {
      return false;
    }
  }

  /**
   * Initiate moved from GET to POST across Jellyfin versions, so try the
   * current shape and fall back rather than pinning users to one server release.
   */
  static async quickConnectInitiate(address: string): Promise<QuickConnectState> {
    const base = normaliseAddress(address);
    const headers = { Authorization: Jellyfin.authHeader() };

    let response = await fetch(`${base}/QuickConnect/Initiate`, { method: 'POST', headers });
    if (response.status === 404 || response.status === 405) {
      response = await fetch(`${base}/QuickConnect/Initiate`, { headers });
    }
    if (!response.ok) {
      throw new Error('This server would not start a Quick Connect request.');
    }

    const body = await response.json();
    return { code: body.Code, secret: body.Secret };
  }

  /** True once someone has approved the code. */
  static async quickConnectApproved(address: string, secret: string): Promise<boolean> {
    const response = await fetch(
      `${normaliseAddress(address)}/QuickConnect/Connect?secret=${encodeURIComponent(secret)}`,
      { headers: { Authorization: Jellyfin.authHeader() } }
    );
    if (!response.ok) throw new Error('The Quick Connect request expired. Start a new one.');
    const body = await response.json();
    return body.Authenticated === true;
  }

  static async authenticateWithQuickConnect(address: string, secret: string): Promise<Jellyfin> {
    const base = normaliseAddress(address);
    const response = await fetch(`${base}/Users/AuthenticateWithQuickConnect`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: Jellyfin.authHeader()
      },
      body: JSON.stringify({ Secret: secret })
    });
    if (!response.ok) {
      throw new Error(`The server refused the sign-in (HTTP ${response.status}).`);
    }

    const body = await response.json();
    const client = new Jellyfin({
      address: base,
      accessToken: body.AccessToken,
      userId: body.User.Id,
      userName: body.User.Name
    });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(client.credentials));
    return client;
  }

  signOut(): void {
    localStorage.removeItem(STORAGE_KEY);
  }

  private url(
    path: string,
    params: Record<string, string | number | boolean | undefined> = {}
  ): string {
    const url = new URL(this.credentials.address + path);
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined) url.searchParams.set(key, String(value));
    }
    return url.toString();
  }

  private async request<T>(
    path: string,
    init: RequestInit = {},
    params: Record<string, string | number | boolean | undefined> = {}
  ): Promise<T> {
    const response = await fetch(this.url(path, params), {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        Authorization: Jellyfin.authHeader(this.credentials.accessToken),
        ...init.headers
      }
    });
    if (!response.ok) {
      throw new Error(`${init.method ?? 'GET'} ${path} failed (HTTP ${response.status})`);
    }
    return response.status === 204 ? (undefined as T) : ((await response.json()) as T);
  }

  // ---- Library ----------------------------------------------------------

  /** Only the libraries Glassfin understands. Music and live TV are out of scope. */
  async libraries(): Promise<Item[]> {
    const body = await this.request<ItemsResponse>('/UserViews', {}, {
      userId: this.credentials.userId
    });
    return body.Items.filter((view) =>
      ['movies', 'tvshows'].includes(view.CollectionType ?? '')
    );
  }

  async resume(limit = 12): Promise<Item[]> {
    const body = await this.request<ItemsResponse>('/UserItems/Resume', {}, {
      userId: this.credentials.userId,
      limit,
      mediaTypes: 'Video',
      includeItemTypes: 'Movie,Episode',
      fields: 'PrimaryImageAspectRatio,Overview',
      enableImageTypes: 'Primary,Backdrop,Thumb'
    });
    return body.Items;
  }

  async nextUp(limit = 16): Promise<Item[]> {
    const body = await this.request<ItemsResponse>('/Shows/NextUp', {}, {
      userId: this.credentials.userId,
      limit,
      fields: 'PrimaryImageAspectRatio,Overview',
      enableImageTypes: 'Primary,Backdrop,Thumb'
    });
    return body.Items;
  }

  /** Note: /Items/Latest returns a bare array, not an ItemsResponse. */
  async latest(parentId: string, limit = 20): Promise<Item[]> {
    return this.request<Item[]>('/Items/Latest', {}, {
      userId: this.credentials.userId,
      parentId,
      limit,
      fields: 'PrimaryImageAspectRatio',
      enableImageTypes: 'Primary,Backdrop,Thumb'
    });
  }

  async items(
    query: Record<string, string | number | boolean | undefined>
  ): Promise<ItemsResponse> {
    return this.request<ItemsResponse>('/Items', {}, {
      userId: this.credentials.userId,
      recursive: true,
      fields: 'PrimaryImageAspectRatio,Overview,Genres',
      enableImageTypes: 'Primary,Backdrop,Thumb',
      ...query
    });
  }

  async item(id: string): Promise<Item> {
    return this.request<Item>(`/Items/${id}`, {}, {
      userId: this.credentials.userId,
      fields: 'People,Studios,Taglines,Overview,Genres,MediaSources,MediaStreams'
    });
  }

  async seasons(seriesId: string): Promise<Item[]> {
    const body = await this.request<ItemsResponse>(`/Shows/${seriesId}/Seasons`, {}, {
      userId: this.credentials.userId,
      fields: 'PrimaryImageAspectRatio'
    });
    return body.Items;
  }

  async episodes(seriesId: string, seasonId?: string): Promise<Item[]> {
    const body = await this.request<ItemsResponse>(`/Shows/${seriesId}/Episodes`, {}, {
      userId: this.credentials.userId,
      seasonId,
      fields: 'Overview,PrimaryImageAspectRatio'
    });
    return body.Items;
  }

  async search(term: string, limit = 40): Promise<Item[]> {
    const body = await this.items({
      searchTerm: term,
      includeItemTypes: 'Movie,Series',
      limit
    });
    return body.Items;
  }

  /**
   * Intro and outro markers. Absent on servers older than 10.10 or without the
   * Intro Skipper plugin, which is not an error — it just means no skipping.
   */
  async mediaSegments(itemId: string): Promise<MediaSegment[]> {
    try {
      const body = await this.request<{ Items?: MediaSegment[] }>(
        `/MediaSegments/${itemId}`,
        {},
        { includeSegmentTypes: 'Intro,Outro' }
      );
      return body?.Items ?? [];
    } catch {
      return [];
    }
  }

  // ---- Images -----------------------------------------------------------

  imageUrl(
    item: Item,
    type: 'Primary' | 'Backdrop' | 'Thumb' = 'Primary',
    options: { maxWidth?: number; maxHeight?: number } = {}
  ): string | null {
    let id = item.Id;
    let tag: string | undefined = item.ImageTags?.[type];

    // Episodes usually have no poster of their own; borrow the series'.
    if (type === 'Primary' && !tag && item.SeriesPrimaryImageTag && item.SeriesId) {
      id = item.SeriesId;
      tag = item.SeriesPrimaryImageTag;
    }
    if (type === 'Backdrop') {
      tag = item.BackdropImageTags?.[0];
    }
    if (!tag) return null;

    return this.url(`/Items/${id}/Images/${type}`, {
      tag,
      quality: 90,
      maxWidth: options.maxWidth,
      maxHeight: options.maxHeight
    });
  }

  /** People carry `PrimaryImageTag`, not the `ImageTags` map, so they need their own helper. */
  personImageUrl(person: Person, maxWidth = 300): string | null {
    if (!person.PrimaryImageTag) return null;
    return this.url(`/Items/${person.Id}/Images/Primary`, {
      tag: person.PrimaryImageTag,
      quality: 90,
      maxWidth
    });
  }

  // ---- Playback ---------------------------------------------------------

  /**
   * Track indices matter here, not just at load time. When the server decides
   * to transcode, it transcodes *one* audio track — so changing audio means
   * asking it again with a different `AudioStreamIndex`, not switching a track
   * inside mpv. Same for subtitles it has burned in.
   */
  async playbackInfo(
    itemId: string,
    startTicks = 0,
    tracks: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null } = {}
  ): Promise<PlaybackInfo> {
    return this.request<PlaybackInfo>(
      `/Items/${itemId}/PlaybackInfo`,
      {
        method: 'POST',
        body: JSON.stringify({
          UserId: this.credentials.userId,
          StartTimeTicks: startTicks,
          AutoOpenLiveStream: true,
          DeviceProfile: deviceProfile(),
          ...(tracks.audioStreamIndex != null ? { AudioStreamIndex: tracks.audioStreamIndex } : {}),
          ...(tracks.subtitleStreamIndex != null
            ? { SubtitleStreamIndex: tracks.subtitleStreamIndex }
            : {})
        })
      },
      { userId: this.credentials.userId }
    );
  }

  /** Subtitle delivery URLs are server-relative; mpv needs them absolute. */
  absoluteUrl(path: string): string {
    return /^https?:\/\//i.test(path) ? path : this.credentials.address + path;
  }

  /** The absolute URL mpv should open, honouring whatever the server decided. */
  streamUrl(source: MediaSource, playSessionId: string): string {
    if (source.TranscodingUrl) {
      return this.credentials.address + source.TranscodingUrl;
    }
    return this.url(`/Videos/${source.Id}/stream`, {
      static: true,
      mediaSourceId: source.Id,
      playSessionId,
      api_key: this.credentials.accessToken
    });
  }

  /**
   * Progress reporting. Getting this wrong is how resume points and watched
   * state rot, so it stays explicit rather than clever.
   */
  reportStart(itemId: string, playSessionId: string, positionTicks: number): Promise<void> {
    return this.request('/Sessions/Playing', {
      method: 'POST',
      body: JSON.stringify({
        ItemId: itemId,
        PlaySessionId: playSessionId,
        PositionTicks: positionTicks
      })
    });
  }

  reportProgress(
    itemId: string,
    playSessionId: string,
    positionTicks: number,
    isPaused: boolean
  ): Promise<void> {
    return this.request('/Sessions/Playing/Progress', {
      method: 'POST',
      body: JSON.stringify({
        ItemId: itemId,
        PlaySessionId: playSessionId,
        PositionTicks: positionTicks,
        IsPaused: isPaused
      })
    });
  }

  reportStopped(itemId: string, playSessionId: string, positionTicks: number): Promise<void> {
    return this.request('/Sessions/Playing/Stopped', {
      method: 'POST',
      body: JSON.stringify({
        ItemId: itemId,
        PlaySessionId: playSessionId,
        PositionTicks: positionTicks
      })
    });
  }
}
