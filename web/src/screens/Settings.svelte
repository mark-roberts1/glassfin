<script lang="ts">
  import Logo from '../components/Logo.svelte';
  import ScreenHeader from '../components/ScreenHeader.svelte';
  import { focusable, focusGroup } from '../lib/nav';
  import { session } from '../lib/session.svelte';
  import {
    LANGUAGES,
    SUBTITLE_APPEARANCE,
    preferences,
    subtitleAppearance,
    type Preferences
  } from '../lib/settings.svelte';

  interface Props {
    onBack: () => void;
  }

  const { onBack }: Props = $props();

  /**
   * Every row cycles on select rather than opening a picker.
   *
   * A sub-screen per setting is a lot of navigation for lists this short, and
   * left/right are already spoken for by spatial movement. One button, one
   * step forward through the options, wrapping at the end.
   */
  type Option = readonly [value: string, label: string];

  const LANGUAGE_OPTIONS: Option[] = LANGUAGES.map((l) => [l.code, l.name] as const);

  const SUBTITLE_MODES: Option[] = [
    ['off', 'Off'],
    ['forced', 'Forced only'],
    ['preferred', 'On, preferred language']
  ];

  const SKIP_MODES: Option[] = [
    ['off', 'Off'],
    ['prompt', 'Show a button'],
    ['auto', 'Skip automatically']
  ];

  const THEMES: Option[] = [
    ['dark', 'Dark'],
    ['light', 'Light'],
    ['system', 'Follow the system']
  ];

  function labelOf(options: Option[], value: string): string {
    return options.find(([candidate]) => candidate === value)?.[1] ?? 'Default';
  }

  function cycle<K extends keyof Preferences>(key: K, options: Option[]) {
    const current = preferences.value[key] as string;
    const index = options.findIndex(([value]) => value === current);
    const next = options[(index + 1) % options.length][0];
    preferences.set(key, next as Preferences[K]);
  }

  function cycleAppearance(key: string, options: readonly Option[]) {
    const current = String(subtitleAppearance.values[key] ?? '');
    const index = options.findIndex(([value]) => value === current);
    void subtitleAppearance.set(key, options[(index + 1) % options.length][0]);
  }

  $effect(() => {
    void subtitleAppearance.load();
    queueMicrotask(() => focusGroup('settings'));
  });

  const prefs = $derived(preferences.value);
  const credentials = $derived(session.client?.credentials ?? null);
</script>

<div class="screen settings scroller">
  <ScreenHeader title="Settings" {onBack} />

  <!-- First, because it is the one setting whose effect you can see while you
       are making it: the page changes under the cursor as the row cycles. -->
  <section>
    <h2>Appearance</h2>

    <button
      class="row focusable"
      use:focusable={{ group: 'settings', onSelect: () => cycle('theme', THEMES) }}
    >
      <span class="name">Theme</span>
      <span class="value">{labelOf(THEMES, prefs.theme)}</span>
    </button>

    <div class="row static swatches">
      <span class="name">Glassfin</span>
      <span class="mark"><Logo size={36} wordmark /></span>
    </div>
  </section>

  <section>
    <h2>Playback</h2>

    <button
      class="row focusable"
      use:focusable={{ group: 'settings', onSelect: () => cycle('audioLanguage', LANGUAGE_OPTIONS) }}
    >
      <span class="name">Preferred audio language</span>
      <span class="value">{labelOf(LANGUAGE_OPTIONS, prefs.audioLanguage)}</span>
    </button>

    <button
      class="row focusable"
      use:focusable={{ group: 'settings', onSelect: () => cycle('subtitleMode', SUBTITLE_MODES) }}
    >
      <span class="name">Subtitles</span>
      <span class="value">{labelOf(SUBTITLE_MODES, prefs.subtitleMode)}</span>
    </button>

    <button
      class="row focusable"
      use:focusable={{
        group: 'settings',
        disabled: prefs.subtitleMode === 'off',
        onSelect: () => cycle('subtitleLanguage', LANGUAGE_OPTIONS)
      }}
      class:muted={prefs.subtitleMode === 'off'}
    >
      <span class="name">Preferred subtitle language</span>
      <span class="value">{labelOf(LANGUAGE_OPTIONS, prefs.subtitleLanguage)}</span>
    </button>
  </section>

  <section>
    <h2>Skipping</h2>
    <p class="note">
      Uses the markers your server provides. Jellyfin 10.10 and later supply these natively;
      earlier versions need the Intro Skipper plugin. With neither, nothing is skipped.
    </p>

    <button
      class="row focusable"
      use:focusable={{ group: 'settings', onSelect: () => cycle('introSkip', SKIP_MODES) }}
    >
      <span class="name">Intros</span>
      <span class="value">{labelOf(SKIP_MODES, prefs.introSkip)}</span>
    </button>

    <button
      class="row focusable"
      use:focusable={{ group: 'settings', onSelect: () => cycle('outroSkip', SKIP_MODES) }}
    >
      <span class="name">Credits</span>
      <span class="value">{labelOf(SKIP_MODES, prefs.outroSkip)}</span>
    </button>
  </section>

  <section>
    <h2>Subtitle appearance</h2>
    <p class="note">
      Drawn by mpv, so these are the shell's own settings rather than Glassfin's. They apply to
      every video, and survive a restart.
    </p>

    {#each SUBTITLE_APPEARANCE as setting (setting.key)}
      <button
        class="row focusable"
        use:focusable={{
          group: 'settings',
          onSelect: () => cycleAppearance(setting.key, setting.options)
        }}
      >
        <span class="name">{setting.label}</span>
        <span class="value">
          {setting.options.find(
            ([value]) => value === String(subtitleAppearance.values[setting.key] ?? '')
          )?.[1] ?? 'Default'}
        </span>
      </button>
    {/each}
  </section>

  <section>
    <h2>Account</h2>

    {#if credentials}
      <div class="row static">
        <span class="name">Signed in</span>
        <span class="value">{credentials.userName} · {credentials.address}</span>
      </div>
    {/if}

    <button
      class="row danger focusable"
      use:focusable={{ group: 'settings', onSelect: () => session.signOut() }}
    >
      <span class="name">Sign out</span>
      <span class="value">Return to the server and sign-in screen</span>
    </button>

    <button
      class="row focusable"
      use:focusable={{ group: 'settings', onSelect: () => preferences.reset() }}
    >
      <span class="name">Reset preferences</span>
      <span class="value">Restore the defaults above</span>
    </button>
  </section>
</div>

<style>
  .settings {
    height: 100%;
    padding: var(--safe-y) var(--safe-x);
  }

  section {
    margin-bottom: 2.4rem;
    max-width: 900px;
  }

  h2 {
    font-size: 1rem;
    color: var(--ink-dim);
    margin-bottom: 0.8rem;
  }

  .note {
    margin: -0.35rem 0 0.9rem;
    font-size: 0.88rem;
    color: var(--ink-faint);
    max-width: 62ch;
  }

  .row {
    width: 100%;
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 1.5rem;
    font: inherit;
    text-align: left;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    padding: 0.85rem 1.1rem;
    margin-bottom: 0.55rem;
  }

  .row.static {
    color: var(--ink-dim);
  }

  /* The mark sits on a raised row rather than on the page, so its cuts have to
     be told what colour they are cut out of. */
  .swatches {
    align-items: center;
    --logo-cut: var(--raised);
  }

  .mark {
    display: inline-flex;
  }

  .row.muted {
    opacity: 0.45;
  }

  .name {
    flex: 1 1 auto;
  }

  .value {
    flex: 0 0 auto;
    color: var(--ink-dim);
    text-align: right;
  }

  .danger .name {
    color: var(--danger);
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps this rule alive.
     Rows are full width, so they take the ring without scaling. */
  .row:global(.is-focused) {
    box-shadow: 0 0 0 3px var(--ink);
    transform: none;
  }
</style>
