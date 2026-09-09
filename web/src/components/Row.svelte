<script lang="ts">
  import Card from './Card.svelte';
  import type { Item, Jellyfin } from '../lib/jellyfin';

  interface Props {
    title: string;
    items: Item[];
    client: Jellyfin;
    shape?: 'poster' | 'still';
    group: string;
    onSelect: (item: Item) => void;
    onFocus?: (item: Item) => void;
  }

  const { title, items, client, shape = 'poster', group, onSelect, onFocus }: Props = $props();
</script>

{#if items.length > 0}
  <section class="row">
    <h2>{title}</h2>
    <div class="track scroller">
      {#each items as item (item.Id)}
        <!--
          enter="first": this row scrolls on its own, so coming into it from
          above or below has to start at the beginning. Anywhere else is a
          position the viewer never chose.
        -->
        <Card
          {item}
          {client}
          {shape}
          {group}
          enter="first"
          onSelect={() => onSelect(item)}
          onFocus={() => onFocus?.(item)}
        />
      {/each}
    </div>
  </section>
{/if}

<style>
  .row {
    margin-bottom: 2.6rem;
  }

  h2 {
    font-size: 1.05rem;
    font-weight: 500;
    color: var(--ink-dim);
    margin: 0 0 0.9rem var(--safe-x);
    text-transform: none;
  }

  .track {
    display: flex;
    gap: 1.1rem;
    /* The safe-area padding lives on the track, not the page, so the first
       card can still scroll flush to the edge without being clipped. The top is
       --focus-room rather than a round number: a scrolling box clips its own
       overflow, so a card that grows on focus needs the space reserved for it. */
    padding: var(--focus-room) var(--safe-x) 0.75rem;
    overflow-x: auto;
    overflow-y: visible;
    scroll-behavior: smooth;
  }
</style>
