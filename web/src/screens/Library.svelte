<script lang="ts">
  import ScreenHeader from '../components/ScreenHeader.svelte';
  import Card from '../components/Card.svelte';
  import { focusable, focusGroup } from '../lib/nav';
  import type { Item, Jellyfin } from '../lib/jellyfin';

  interface Props {
    client: Jellyfin;
    library: Item;
    onOpen: (item: Item) => void;
    onAmbient: (item: Item) => void;
    onBack: () => void;
  }

  const { client, library, onOpen, onAmbient, onBack }: Props = $props();

  /**
   * A page, not the whole library. Asking for every item in a large collection
   * costs a slow first paint and a lot of image requests, and nobody scrolls
   * two thousand posters with a D-pad.
   */
  const PAGE = 60;

  let items = $state<Item[]>([]);
  let total = $state(0);
  let loading = $state(true);
  let loadingMore = $state(false);
  let error = $state<string | null>(null);

  const kind = $derived(library.CollectionType === 'tvshows' ? 'Series' : 'Movie');
  const more = $derived(items.length < total);

  async function page(startIndex: number) {
    const body = await client.items({
      parentId: library.Id,
      includeItemTypes: kind,
      sortBy: 'SortName',
      sortOrder: 'Ascending',
      startIndex,
      limit: PAGE
    });
    total = body.TotalRecordCount;
    return body.Items;
  }

  async function loadMore() {
    if (loadingMore || !more) return;
    loadingMore = true;
    try {
      items = [...items, ...(await page(items.length))];
    } catch {
      /* Keep what is already on screen; the button stays for another try. */
    } finally {
      loadingMore = false;
    }
  }

  $effect(() => {
    (async () => {
      loading = true;
      error = null;
      try {
        items = await page(0);
      } catch (cause) {
        error = cause instanceof Error ? cause.message : 'Could not load this library.';
      } finally {
        loading = false;
        queueMicrotask(() => focusGroup('library'));
      }
    })();
  });
</script>

<div class="screen library scroller">
  <ScreenHeader title={library.Name} {onBack} />

  {#if loading}
    <p class="state">Loading…</p>
  {:else if error}
    <p class="state error">{error}</p>
  {:else if items.length === 0}
    <p class="state">This library is empty.</p>
  {:else}
    <p class="count">{total} {kind === 'Series' ? 'series' : 'films'}</p>

    <div class="grid">
      {#each items as item (item.Id)}
        <Card
          {item}
          {client}
          group="library"
          onSelect={() => onOpen(item)}
          onFocus={() => onAmbient(item)}
        />
      {/each}
    </div>

    {#if more}
      <div class="more">
        <button class="focusable" use:focusable={{ group: 'library-more', onSelect: loadMore }}>
          {loadingMore ? 'Loading…' : `Show more (${items.length} of ${total})`}
        </button>
      </div>
    {/if}
  {/if}
</div>

<style>
  .library {
    height: 100%;
    padding: var(--safe-y) var(--safe-x);
  }

  .count {
    margin: -0.5rem 0 1.2rem;
    color: var(--ink-dim);
    font-size: 0.9rem;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--poster-width), 1fr));
    gap: 2rem 1.4rem;
    padding: 0.75rem 0.5rem;
  }

  .more {
    display: flex;
    justify-content: center;
    padding: 1.5rem 0 2.5rem;
  }

  button {
    font: inherit;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    padding: 0.8rem 1.6rem;
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps this rule alive. */
  button:global(.is-focused) {
    transform: none;
    box-shadow: 0 0 0 3px var(--ink);
  }

  .state {
    color: var(--ink-dim);
  }

  .state.error {
    color: var(--danger);
  }
</style>
