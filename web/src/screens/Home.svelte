<script lang="ts">
  import Logo from '../components/Logo.svelte';
  import Row from '../components/Row.svelte';
  import { focusable, focusFirst } from '../lib/nav';
  import type { Item, Jellyfin } from '../lib/jellyfin';

  interface Props {
    client: Jellyfin;
    onOpen: (item: Item) => void;
    onAmbient: (item: Item) => void;
    onSearch: () => void;
    onSettings: () => void;
    onLibrary: (library: Item) => void;
  }

  const { client, onOpen, onAmbient, onSearch, onSettings, onLibrary }: Props = $props();

  interface Shelf {
    title: string;
    items: Item[];
    shape: 'poster' | 'still';
    group: string;
  }

  let libraries = $state<Item[]>([]);
  let resumeShelves = $state<Shelf[]>([]);
  let latestShelves = $state<Shelf[]>([]);
  let error = $state<string | null>(null);
  let loading = $state(true);

  async function load() {
    try {
      const [resume, nextUp, found] = await Promise.all([
        client.resume(),
        client.nextUp(),
        client.libraries()
      ]);

      const built: Shelf[] = [];

      // Resume first, always. On a television the most likely intent is
      // "carry on with the thing I was already watching".
      if (resume.length) {
        built.push({ title: 'Continue Watching', items: resume, shape: 'still', group: 'resume' });
      }
      if (nextUp.length) {
        built.push({ title: 'Next Up', items: nextUp, shape: 'still', group: 'next-up' });
      }
      resumeShelves = built;
      libraries = found;

      const latest = await Promise.all(
        found.map(async (library) => ({
          title: `Recently Added in ${library.Name}`,
          items: await client.latest(library.Id),
          shape: 'poster' as const,
          group: `latest-${library.Id}`
        }))
      );
      latestShelves = latest.filter((shelf) => shelf.items.length > 0);
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Could not reach the server.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    void load();
  });

  // Focus only once there is something to focus. Doing this on every change
  // would drag focus back to the top as later shelves arrive.
  let claimed = false;
  $effect(() => {
    if ((resumeShelves.length > 0 || libraries.length > 0) && !claimed) {
      claimed = true;
      queueMicrotask(focusFirst);
    }
  });

  const libraryImage = (library: Item) =>
    client.imageUrl(library, 'Primary', { maxWidth: 640 }) ??
    client.imageUrl(library, 'Backdrop', { maxWidth: 640 });
</script>

<div class="screen home scroller">
  <header>
    <h1><Logo size={34} wordmark /></h1>
    <div class="chrome">
      <button class="pill focusable" use:focusable={{ group: 'chrome', onSelect: onSearch }}>
        Search
      </button>
      <button class="pill focusable" use:focusable={{ group: 'chrome', onSelect: onSettings }}>
        Settings
      </button>
    </div>
  </header>

  {#if loading}
    <p class="state">Loading your library…</p>
  {:else if error}
    <p class="state error">{error}</p>
  {:else}
    {#each resumeShelves as shelf (shelf.group)}
      <Row
        title={shelf.title}
        items={shelf.items}
        {client}
        shape={shelf.shape}
        group={shelf.group}
        onSelect={onOpen}
        onFocus={onAmbient}
      />
    {/each}

    <!-- The way into everything, rather than only what is recent or unfinished. -->
    {#if libraries.length > 0}
      <section class="shelf">
        <h2>Libraries</h2>
        <div class="tiles scroller">
          {#each libraries as library (library.Id)}
            {@const image = libraryImage(library)}
            <button
              class="tile focusable"
              use:focusable={{
                group: 'libraries',
                enter: 'first',
                onSelect: () => onLibrary(library)
              }}
              style:background-image={image ? `url(${image})` : 'none'}
            >
              <span class="tile-veil"></span>
              <span class="tile-name">{library.Name}</span>
            </button>
          {/each}
        </div>
      </section>
    {/if}

    {#each latestShelves as shelf (shelf.group)}
      <Row
        title={shelf.title}
        items={shelf.items}
        {client}
        shape={shelf.shape}
        group={shelf.group}
        onSelect={onOpen}
        onFocus={onAmbient}
      />
    {/each}

    {#if resumeShelves.length === 0 && libraries.length === 0}
      <p class="state">Nothing here yet. Add some films or shows to your Jellyfin libraries.</p>
    {/if}
  {/if}
</div>

<style>
  .home {
    height: 100%;
    padding-top: var(--safe-y);
    padding-bottom: var(--safe-y);
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    padding: 0 var(--safe-x);
    margin-bottom: 2rem;
  }

  h1 {
    line-height: 1;
  }

  .chrome {
    display: flex;
    gap: 0.6rem;
  }

  .pill {
    font: inherit;
    font-size: 0.95rem;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: 999px;
    padding: 0.5rem 1.3rem;
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps these rules alive. */
  .pill:global(.is-focused) {
    color: var(--ground);
    background: var(--ink);
  }

  .shelf {
    margin-bottom: 2.6rem;
  }

  h2 {
    font-size: 1.05rem;
    font-weight: 500;
    color: var(--ink-dim);
    margin: 0 0 0.9rem var(--safe-x);
  }

  .tiles {
    display: flex;
    gap: 1.1rem;
    padding: var(--focus-room) var(--safe-x) 0.75rem;
    overflow-x: auto;
    overflow-y: visible;
    scroll-behavior: smooth;
  }

  /* Wider than a poster and shorter: a library is a place, not a title, and
     should not be mistaken for one at a glance. */
  .tile {
    position: relative;
    flex: 0 0 auto;
    width: calc(var(--poster-width) * 1.6);
    aspect-ratio: 16 / 9;
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    background-color: var(--raised);
    background-size: cover;
    background-position: center;
    overflow: hidden;
    padding: 0;
    font: inherit;
    color: var(--ink);
  }

  /* Fixed dark, in both themes: the wash and the name sit on library
     artwork, and artwork has no light mode. */
  .tile-veil {
    position: absolute;
    inset: 0;
    background: linear-gradient(to top, rgba(11, 17, 20, 0.85) 12%, rgba(11, 17, 20, 0.15) 70%);
  }

  .tile-name {
    position: absolute;
    left: 1rem;
    bottom: 0.85rem;
    font-size: 1.05rem;
    font-weight: 500;
    color: var(--over-ink);
  }

  .state {
    padding: 0 var(--safe-x);
    color: var(--ink-dim);
  }

  .state.error {
    color: var(--danger);
  }
</style>
