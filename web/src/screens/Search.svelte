<script lang="ts">
  import Keyboard from '../components/Keyboard.svelte';
  import Card from '../components/Card.svelte';
  import ScreenHeader from '../components/ScreenHeader.svelte';
  import { focusGroup } from '../lib/nav';
  import { textEntry } from '../lib/textentry.svelte';
  import type { Item, Jellyfin } from '../lib/jellyfin';

  interface Props {
    client: Jellyfin;
    onOpen: (item: Item) => void;
    onAmbient: (item: Item) => void;
    onExit: () => void;
  }

  const { client, onOpen, onAmbient, onExit }: Props = $props();

  /** Long enough that a D-pad user is not firing a request per letter. */
  const DEBOUNCE_MS = 350;
  const MIN_TERM = 2;

  let results = $state<Item[]>([]);
  let searching = $state(false);
  let term = $state('');
  let debounce: ReturnType<typeof setTimeout> | undefined;

  /** Discard responses that arrive after a newer query has been sent. */
  let generation = 0;

  async function run(value: string) {
    const mine = ++generation;
    if (value.trim().length < MIN_TERM) {
      results = [];
      searching = false;
      return;
    }

    searching = true;
    try {
      const found = await client.search(value.trim());
      if (mine === generation) results = found;
    } catch {
      if (mine === generation) results = [];
    } finally {
      if (mine === generation) searching = false;
    }
  }

  $effect(() => {
    textEntry.open({
      label: 'Search',
      value: '',
      placeholder: 'Film or series title',
      persistent: true,
      onChange: (value) => {
        term = value;
        clearTimeout(debounce);
        debounce = setTimeout(() => void run(value), DEBOUNCE_MS);
      },
      onCommit: () => {
        // "Done" means move to the results, if there are any to move to.
        if (results.length > 0) queueMicrotask(() => focusGroup('search-results'));
      },
      onCancel: onExit
    });

    return () => {
      clearTimeout(debounce);
      if (textEntry.active) textEntry.cancel();
    };
  });
</script>

<div class="screen search">
  <ScreenHeader title="Search" onBack={onExit} />

  <div class="body">
    <div class="pane">
      <Keyboard />
    </div>

    <div class="results scroller">
      {#if searching}
        <p class="state">Searching…</p>
      {:else if term.trim().length < MIN_TERM}
        <p class="state">Type to search your films and series.</p>
      {:else if results.length === 0}
        <p class="state">Nothing matched “{term}”.</p>
      {:else}
        <div class="grid">
          {#each results as item (item.Id)}
            <Card
              {item}
              {client}
              group="search-results"
              onSelect={() => onOpen(item)}
              onFocus={() => onAmbient(item)}
            />
          {/each}
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .search {
    display: grid;
    grid-template-rows: auto 1fr;
    height: 100%;
    padding: var(--safe-y) var(--safe-x);
    min-height: 0;
  }

  .body {
    display: grid;
    grid-template-columns: minmax(340px, 32%) 1fr;
    /* The keyboard and the results are two separate things to look at, and
       were reading as one. A rule and real space between them fixes that. */
    gap: 3.5rem;
    min-height: 0;
  }

  .pane {
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 0.5rem;
    padding-right: 3.5rem;
    border-right: 1px solid var(--edge);
    min-width: 0;
  }

  .results {
    min-width: 0;
    /* Focused cards scale to 1.06, so the track needs room or they clip
       against the divider and the window edge. */
    padding: 0.25rem 1rem 2rem 0.5rem;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--poster-width), 1fr));
    gap: 1.8rem 1.4rem;
    padding: 0.75rem 0.5rem;
  }

  .state {
    color: var(--ink-dim);
    padding: 1.25rem 0.5rem;
  }
</style>
