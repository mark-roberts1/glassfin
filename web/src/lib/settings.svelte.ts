/**
 * Preferences, in two halves.
 *
 * Glassfin owns *behaviour* — which audio track to pick, whether subtitles come
 * on by default, what to do when an intro starts. Those live here and persist
 * to localStorage.
 *
 * The shell owns *subtitle appearance* — size, font, colour, border, placement.
 * That is mpv drawing pixels, and no web layer can restyle it, so those are
 * written straight through to `api.settings` rather than duplicated. See the
 * `subtitles` section of resources/settings/settings_description.json.
 */

import { getHost } from './host';
import type { Theme } from './theme';

export type SkipMode = 'off' | 'prompt' | 'auto';
export type SubtitleMode = 'off' | 'forced' | 'preferred';

export interface Preferences {
  /** ISO 639-2 three-letter codes, matching MediaStream.Language. '' means "whatever the server ordered". */
  audioLanguage: string;
  subtitleLanguage: string;
  subtitleMode: SubtitleMode;
  introSkip: SkipMode;
  outroSkip: SkipMode;
  theme: Theme;
}

const DEFAULTS: Preferences = {
  audioLanguage: '',
  subtitleLanguage: '',
  subtitleMode: 'off',
  introSkip: 'prompt',
  outroSkip: 'off',
  /* Dark, not system. A television in a dark room is the case to be right
     about, and most shells have no palette preference to consult anyway. */
  theme: 'dark'
};

/**
 * Deliberately short. A list of every ISO 639-2 code is unusable on a D-pad,
 * and this covers what a home library actually holds.
 */
export const LANGUAGES: ReadonlyArray<{ code: string; name: string }> = [
  { code: '', name: 'Server default' },
  { code: 'eng', name: 'English' },
  { code: 'spa', name: 'Spanish' },
  { code: 'fra', name: 'French' },
  { code: 'deu', name: 'German' },
  { code: 'ita', name: 'Italian' },
  { code: 'por', name: 'Portuguese' },
  { code: 'nld', name: 'Dutch' },
  { code: 'swe', name: 'Swedish' },
  { code: 'pol', name: 'Polish' },
  { code: 'rus', name: 'Russian' },
  { code: 'jpn', name: 'Japanese' },
  { code: 'kor', name: 'Korean' },
  { code: 'zho', name: 'Chinese' }
];

const STORAGE_KEY = 'glassfin.preferences';

function load(): Preferences {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    // Spread over the defaults so a preference added in a later version does
    // not come back undefined for people who already have stored settings.
    return raw ? { ...DEFAULTS, ...(JSON.parse(raw) as Partial<Preferences>) } : { ...DEFAULTS };
  } catch {
    return { ...DEFAULTS };
  }
}

let current = $state<Preferences>(load());

export const preferences = {
  get value(): Preferences {
    return current;
  },

  set<K extends keyof Preferences>(key: K, value: Preferences[K]): void {
    current = { ...current, [key]: value };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(current));
  },

  reset(): void {
    current = { ...DEFAULTS };
    localStorage.removeItem(STORAGE_KEY);
  }
};

export function languageName(code: string): string {
  return LANGUAGES.find((language) => language.code === code)?.name ?? code;
}

// ---- Subtitle appearance, owned by the shell ------------------------------

export const SUBTITLE_APPEARANCE = [
  {
    key: 'size',
    label: 'Subtitle size',
    options: [
      ['', 'Default'], ['32', 'Small'], ['45', 'Medium'], ['60', 'Large'], ['80', 'Very large']
    ]
  },
  {
    key: 'color',
    label: 'Subtitle colour',
    options: [
      ['', 'Default'], ['#FFFFFF', 'White'], ['#EEEEEE', 'Light grey'],
      ['#FBF93E', 'Yellow'], ['#FFFFCC', 'Light yellow']
    ]
  },
  {
    key: 'border_size',
    label: 'Outline',
    options: [['', 'Default'], ['0', 'None'], ['2', 'Thin'], ['4', 'Medium'], ['6', 'Heavy']]
  },
  {
    key: 'background_transparency',
    label: 'Background',
    options: [['', 'Default'], ['1.0', 'None'], ['0.5', 'Half'], ['0.0', 'Solid']]
  },
  {
    key: 'placement',
    label: 'Placement',
    options: [
      ['', 'Default'], ['center,bottom', 'Bottom'], ['center,top', 'Top'],
      ['left,bottom', 'Bottom left'], ['right,bottom', 'Bottom right']
    ]
  }
] as const;

let shellValues = $state<Record<string, unknown>>({});

export const subtitleAppearance = {
  get values(): Record<string, unknown> {
    return shellValues;
  },

  /** Reads the shell's current subtitle settings. Harmless in a browser; the mock stores them. */
  async load(): Promise<void> {
    const host = await getHost();
    await new Promise<void>((resolve) => {
      host.settings.allValues('subtitles', (values) => {
        shellValues = values ?? {};
        resolve();
      });
    });
  },

  async set(key: string, value: string): Promise<void> {
    const host = await getHost();
    host.settings.setValue('subtitles', key, value);
    shellValues = { ...shellValues, [key]: value };
  }
};
