<script lang="ts">
  import Login from './screens/Login.svelte';
  import Home from './screens/Home.svelte';
  import Search from './screens/Search.svelte';
  import Settings from './screens/Settings.svelte';
  import Library from './screens/Library.svelte';
  import Detail from './screens/Detail.svelte';
  import Keyboard from './components/Keyboard.svelte';
  import Player from './components/Player.svelte';
  import PlaybackMenu from './components/PlaybackMenu.svelte';
  import { session } from './lib/session.svelte';
  import { handleAction, focusFirst } from './lib/nav';
  import { textEntry } from './lib/textentry.svelte';
  import { getHost, onHostActions, type HostAction } from './lib/host';
  import { preferences } from './lib/settings.svelte';
  import { applyTheme, onSystemThemeChange } from './lib/theme';
  import {
    playback,
    isPlaying,
    start,
    stop,
    togglePause,
    seekBy,
    takeSkip,
    nudgeChrome,
    cycleAudio,
    cycleSubtitles,
    toggleSubtitles
  } from './lib/playback.svelte';
  import type { Item } from './lib/jellyfin';

  const SEEK_STEP_MS = 30_000;

  /**
   * A stack, not a current-screen string. Detail can be reached from home,
   * from a library, or from search, and Back has to return to whichever it
   * was — which a flat name cannot express.
   */
  type Route =
    | { name: 'home' }
    | { name: 'search' }
    | { name: 'settings' }
    | { name: 'library'; item: Item }
    | { name: 'detail'; item: Item };

  let stack = $state<Route[]>([{ name: 'home' }]);
  const route = $derived(stack[stack.length - 1]);

  let ambient = $state<string | null>(null);
  let native = $state(false);
  let menuOpen = $state(false);

  const playbackBackdrop = $derived.by(() => {
    const client = session.client;
    const item = playback.item;
    if (!client || !item) return null;
    return (
      client.imageUrl(item, 'Backdrop', { maxWidth: 1920 }) ??
      client.imageUrl(item, 'Primary', { maxWidth: 1280 })
    );
  });

  function push(next: Route) {
    stack = [...stack, next];
    queueMicrotask(focusFirst);
  }

  function pop() {
    if (stack.length <= 1) return;
    stack = stack.slice(0, -1);
    queueMicrotask(focusFirst);
  }

  function setAmbient(item: Item) {
    const client = session.client;
    if (!client) return;
    ambient =
      client.imageUrl(item, 'Backdrop', { maxWidth: 1280 }) ??
      client.imageUrl(item, 'Primary', { maxWidth: 1280 });
  }

  /**
   * Episodes play; films and series open their detail screen.
   *
   * An episode reached from Continue Watching or Next Up is unambiguous — there
   * is exactly one thing you meant. A film has a resume point worth showing you
   * before it jumps in, and a series has no single obvious episode at all.
   */
  function open(item: Item) {
    const client = session.client;
    if (!client) return;

    if (item.Type === 'Episode') {
      void start(client, item);
      return;
    }
    push({ name: 'detail', item });
  }

  function play(item: Item) {
    const client = session.client;
    if (client) void start(client, item);
  }

  function route_(actions: HostAction[]) {
    if (isPlaying()) {
      // Any button brings the transport back, so the screen is never silent.
      nudgeChrome();

      // The track menu is the one time spatial navigation runs during playback,
      // so it takes input before the transport does.
      if (menuOpen) {
        if (actions.includes('back') || actions.includes('exit')) {
          menuOpen = false;
          return;
        }
        for (const action of actions) {
          if (handleAction(action)) return;
        }
        return;
      }

      // An offered skip claims OK while it is showing. That is what the button
      // says it does, and what every other client does.
      if (playback.skip && (actions.includes('select') || actions.includes('enter'))) {
        takeSkip();
        return;
      }

      if (actions.includes('up') || actions.includes('menu')) {
        menuOpen = true;
        return;
      }

      // Remote and keyboard shortcuts, straight from the shell's input maps.
      if (actions.includes('cycle_audio')) {
        void cycleAudio();
        return;
      }
      if (actions.includes('cycle_subtitles')) {
        void cycleSubtitles();
        return;
      }
      if (actions.includes('toggle_subtitles')) {
        void toggleSubtitles();
        return;
      }

      for (const action of actions) {
        switch (action) {
          case 'play_pause': case 'select': case 'enter': case 'play': case 'pause':
            togglePause();
            return;
          case 'back': case 'stop': case 'exit':
            void stop();
            return;
          case 'seek_forward': case 'right':
            void seekBy(SEEK_STEP_MS);
            return;
          case 'seek_backward': case 'left':
            void seekBy(-SEEK_STEP_MS);
            return;
        }
      }
      return;
    }

    if (textEntry.handle(actions)) return;

    for (const action of actions) {
      if (handleAction(action)) return;
    }

    if (actions.includes('search') && route.name !== 'search') {
      push({ name: 'search' });
      return;
    }

    if (actions.includes('home')) {
      stack = [{ name: 'home' }];
      queueMicrotask(focusFirst);
      return;
    }

    if (actions.includes('back')) pop();
  }

  // The menu belongs to a playing item; it must not outlive one.
  $effect(() => {
    if (playback.item === null) menuOpen = false;
  });

  // The theme lives on the document element, not in any component, so the
  // inline guard in index.html can set it before the first paint. Under
  // 'system' the shell can change its mind while the application is running.
  $effect(() => {
    const theme = preferences.value.theme;
    applyTheme(theme);
    if (theme !== 'system') return;
    return onSystemThemeChange(() => applyTheme('system'));
  });

  // The shell composites this page over mpv, so the body has to stop painting
  // a background while video is playing. See app.css.
  $effect(() => {
    document.body.classList.toggle('playing', playback.item !== null);
  });

  // Signing out must not leave a deep stack waiting on the other side of the
  // next sign-in.
  $effect(() => {
    if (!session.signedIn) stack = [{ name: 'home' }];
  });

  $effect(() => {
    void getHost().then((host) => {
      native = host.native;
    });
  });

  $effect(() => {
    let detach: (() => void) | undefined;
    void onHostActions(route_).then((off) => {
      detach = off;
    });
    return () => detach?.();
  });
</script>

<!-- The focused item's artwork, blurred behind everything. -->
<div
  class="ambient"
  class:visible={ambient !== null && playback.item === null && route.name !== 'detail'}
  style:background-image={ambient ? `url(${ambient})` : 'none'}
></div>
<div class="ambient-veil"></div>

{#if !session.signedIn}
  <Login />
{:else if session.client}
  {#if route.name === 'home'}
    <Home
      client={session.client}
      onOpen={open}
      onAmbient={setAmbient}
      onSearch={() => push({ name: 'search' })}
      onSettings={() => push({ name: 'settings' })}
      onLibrary={(item) => push({ name: 'library', item })}
    />
  {:else if route.name === 'search'}
    <Search client={session.client} onOpen={open} onAmbient={setAmbient} onExit={pop} />
  {:else if route.name === 'settings'}
    <Settings onBack={pop} />
  {:else if route.name === 'library'}
    <Library
      client={session.client}
      library={route.item}
      onOpen={open}
      onAmbient={setAmbient}
      onBack={pop}
    />
  {:else}
    <Detail
      client={session.client}
      item={route.item}
      onPlay={play}
      onOpen={open}
      onBack={pop}
    />
  {/if}
{/if}

<Player {native} backdrop={playbackBackdrop} />

{#if menuOpen}
  <PlaybackMenu onClose={() => (menuOpen = false)} />
{/if}

<!-- Search hosts its keyboard inline; everywhere else it is a modal sheet. -->
{#if textEntry.active && route.name !== 'search'}
  <div class="sheet-backdrop">
    <Keyboard />
  </div>
{/if}

<!--
  Not focusable: during playback the transport owns the controller and spatial
  navigation is switched off, so this shows what OK will do rather than being
  something to navigate to.
-->
{#if playback.skip}
  <div class="skip">
    <span class="skip-key">OK</span>
    {playback.skip.label}
  </div>
{/if}

{#if playback.loading}
  <div class="overlay"><p>Starting…</p></div>
{/if}

{#if playback.error}
  <div class="overlay"><p class="error">{playback.error}</p></div>
{/if}

<style>
  .sheet-backdrop {
    position: fixed;
    inset: 0;
    z-index: 15;
    display: grid;
    place-items: center;
    padding: var(--safe-y) var(--safe-x);
    background: rgb(var(--ground-rgb) / 0.92);
  }

  /* Shown while mpv is starting or has failed, so it is over the picture even
     when there is not yet a picture. Dark in both themes — see app.css. */
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 22;
    display: grid;
    place-items: center;
    color: var(--over-ink);
    background: var(--over-scrim);
  }

  .overlay .error {
    color: var(--over-danger);
    max-width: 40ch;
    text-align: center;
  }

  .skip {
    position: fixed;
    z-index: 18;
    right: calc(var(--safe-x) + 1rem);
    bottom: calc(var(--safe-y) + 7rem);
    display: flex;
    align-items: center;
    gap: 0.7rem;
    padding: 0.85rem 1.4rem;
    border-radius: 999px;
    color: var(--over-ink);
    background: var(--over-panel);
    border: 1px solid var(--over-edge);
    font-weight: 500;
  }

  .skip-key {
    font-size: 0.78rem;
    letter-spacing: 0.06em;
    padding: 0.15rem 0.5rem;
    border-radius: 5px;
    color: var(--brand-night);
    background: var(--over-ink);
  }
</style>
