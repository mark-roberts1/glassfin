<script lang="ts">
  import { focusable, type FocusableOptions } from '../lib/nav';
  import type { Item } from '../lib/jellyfin';
  import { Jellyfin, ticksToMs } from '../lib/jellyfin';

  interface Props {
    item: Item;
    client: Jellyfin;
    /** Posters for films and series; stills for episodes and resumable items. */
    shape?: 'poster' | 'still';
    group: string;
    /**
     * `first` in a scrolling row, where the column you were in means nothing;
     * the default everywhere else, because a grid is aligned to the page.
     */
    enter?: FocusableOptions['enter'];
    onSelect?: () => void;
    onFocus?: () => void;
  }

  const {
    item,
    client,
    shape = 'poster',
    group,
    enter = 'nearest',
    onSelect,
    onFocus
  }: Props = $props();

  const image = $derived(
    shape === 'poster'
      ? client.imageUrl(item, 'Primary', { maxWidth: 480 })
      : (client.imageUrl(item, 'Thumb', { maxWidth: 720 }) ??
         client.imageUrl(item, 'Backdrop', { maxWidth: 720 }) ??
         client.imageUrl(item, 'Primary', { maxWidth: 720 }))
  );

  /** How far through the viewer already is, 0–100. */
  const progress = $derived.by(() => {
    const played = item.UserData?.PlayedPercentage;
    if (played != null) return played;
    const position = item.UserData?.PlaybackPositionTicks;
    if (position && item.RunTimeTicks) return (position / item.RunTimeTicks) * 100;
    return 0;
  });

  const title = $derived(item.Type === 'Episode' ? (item.SeriesName ?? item.Name) : item.Name);

  /**
   * A series is captioned by its years, not by a season count.
   *
   * `ChildCount` looks like the number of seasons and sometimes is, but it is
   * whatever the endpoint felt like counting: on `/Items/Latest`, which groups
   * new episodes under their series, it is the number of recently added
   * episodes — so a show with one new episode read "1 season". Nothing asks the
   * server for a season count, and the field that would answer it costs a
   * request per tile. Years are already here and are always true.
   */
  const caption = $derived.by(() => {
    if (item.Type === 'Episode') {
      const season = item.ParentIndexNumber;
      const episode = item.IndexNumber;
      const code = season != null && episode != null ? `S${season}:E${episode}` : '';
      return [code, item.Name].filter(Boolean).join(' · ');
    }

    if (!item.ProductionYear) return '';
    if (item.Type !== 'Series') return String(item.ProductionYear);

    if (item.Status === 'Continuing') return `${item.ProductionYear}–present`;
    const ended = item.EndDate ? new Date(item.EndDate).getFullYear() : undefined;
    return ended && ended !== item.ProductionYear
      ? `${item.ProductionYear}–${ended}`
      : String(item.ProductionYear);
  });

  const runtime = $derived(
    item.RunTimeTicks ? `${Math.round(ticksToMs(item.RunTimeTicks) / 60000)} min` : ''
  );
</script>

<!--
  data-reveal: the title and caption below are what get cut off at the bottom of
  a screen, and they are not inside the focusable. See reveal() in nav.ts.
-->
<div class="card" class:still={shape === 'still'} data-reveal>
  <div class="art focusable" use:focusable={{ group, enter, onSelect, onFocus }}>
    {#if image}
      <img src={image} alt="" loading="lazy" draggable="false" />
    {:else}
      <div class="placeholder"><span>{title}</span></div>
    {/if}

    {#if progress > 1 && progress < 99}
      <div class="progress"><div class="progress-fill" style:width="{progress}%"></div></div>
    {:else if item.UserData?.Played}
      <div class="watched" aria-hidden="true">✓</div>
    {/if}
  </div>

  <div class="label">
    <div class="title">{title}</div>
    {#if caption}<div class="caption">{caption}</div>{/if}
    {#if shape === 'still' && runtime}<div class="caption">{runtime}</div>{/if}
  </div>
</div>

<style>
  .card {
    width: var(--poster-width);
    flex: 0 0 auto;
  }

  .card.still {
    width: var(--still-width);
  }

  .art {
    position: relative;
    aspect-ratio: 2 / 3;
    border-radius: var(--radius);
    overflow: hidden;
    background: var(--raised);
    border: 1px solid var(--edge);
  }

  .card.still .art {
    aspect-ratio: 16 / 9;
  }

  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .placeholder {
    display: grid;
    place-items: center;
    height: 100%;
    padding: 1rem;
    text-align: center;
    color: var(--ink-faint);
    font-size: 0.85rem;
  }

  /* Resume progress. Sits on the artwork because that is where the eye already
     is, and it is the one piece of state worth reading before you commit. */
  .progress {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 4px;
    background: var(--over-artwork);
  }

  /* Over the poster, so it takes the gold that works on a photograph rather
     than the theme's. */
  .progress-fill {
    height: 100%;
    background: var(--over-accent);
  }

  .watched {
    position: absolute;
    top: 8px;
    right: 8px;
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
    border-radius: 50%;
    font-size: 0.8rem;
    /* Also on the poster, so also fixed. A watched tick that inverted with the
       theme would read as two different states across a library. */
    color: var(--brand-night);
    background: var(--over-ink);
  }

  /* Cleared by the same amount the artwork grows, so a focused card lifts off
     its own title instead of sitting on top of it. */
  .label {
    margin-top: var(--focus-room);
    padding: 0 2px;
  }

  .title {
    font-size: 0.92rem;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .caption {
    font-size: 0.82rem;
    color: var(--ink-dim);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
