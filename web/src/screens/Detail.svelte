<script lang="ts">
  import ScreenHeader from '../components/ScreenHeader.svelte';
  import Card from '../components/Card.svelte';
  import { focusable, focusGroup, resetGroup } from '../lib/nav';
  import { ticksToMs, type Item, type Jellyfin } from '../lib/jellyfin';
  import { mediaBadges } from '../lib/mediainfo';
  import { clock } from '../lib/format';
  import { languageName } from '../lib/settings.svelte';

  interface Props {
    client: Jellyfin;
    item: Item;
    onPlay: (item: Item) => void;
    onOpen: (item: Item) => void;
    onBack: () => void;
  }

  const { client, item, onPlay, onOpen, onBack }: Props = $props();

  /** Matches playback's floor: below this a resume point is not worth offering. */
  const RESUME_FLOOR_MS = 10_000;

  /** Enough to recognise the film by; a full cast list is a database, not a screen. */
  const CAST_LIMIT = 12;

  // Derived rather than copied: capturing the prop into state would leave a
  // stale screen if the route ever swapped the item without remounting.
  let detail = $state<Item | null>(null);
  const full = $derived(detail ?? item);

  let seasons = $state<Item[]>([]);
  let episodes = $state<Item[]>([]);
  let seasonId = $state<string | null>(null);
  let nextEpisode = $state<Item | null>(null);
  let loading = $state(true);
  let error = $state<string | null>(null);

  const backdrop = $derived(
    client.imageUrl(full, 'Backdrop', { maxWidth: 1920 }) ??
      client.imageUrl(full, 'Primary', { maxWidth: 1280 })
  );
  const poster = $derived(client.imageUrl(full, 'Primary', { maxWidth: 600 }));

  const resumeMs = $derived(ticksToMs(full.UserData?.PlaybackPositionTicks ?? 0));
  const canResume = $derived(resumeMs > RESUME_FLOOR_MS);

  const runtime = $derived(
    full.RunTimeTicks ? `${Math.round(ticksToMs(full.RunTimeTicks) / 60000)} min` : ''
  );

  const tagline = $derived(full.Taglines?.[0] ?? '');
  const badges = $derived(mediaBadges(full));

  const cast = $derived(
    (full.People ?? []).filter((person) => person.Type === 'Actor').slice(0, CAST_LIMIT)
  );

  const crew = $derived.by(() => {
    const people = full.People ?? [];
    const named = (kind: string) =>
      people.filter((person) => person.Type === kind).map((person) => person.Name);
    return [
      { label: 'Director', names: named('Director') },
      { label: 'Writer', names: named('Writer') }
    ].filter((entry) => entry.names.length > 0);
  });

  const playLabel = $derived.by(() => {
    if (full.Type === 'Series') {
      if (!nextEpisode) return 'Play';
      const code =
        nextEpisode.ParentIndexNumber != null && nextEpisode.IndexNumber != null
          ? `S${nextEpisode.ParentIndexNumber}:E${nextEpisode.IndexNumber}`
          : '';
      return `Play ${code}`.trim();
    }
    return canResume ? `Resume from ${clock(resumeMs)}` : 'Play';
  });

  async function loadSeason(seriesId: string, id: string) {
    seasonId = id;
    resetGroup('episodes');
    episodes = await client.episodes(seriesId, id);
  }

  async function load(id: string) {
    loading = true;
    error = null;
    detail = null;
    seasons = [];
    episodes = [];
    nextEpisode = null;

    try {
      const fetched = await client.item(id);
      detail = fetched;

      if (fetched.Type === 'Series') {
        const [found, upNext] = await Promise.all([
          client.seasons(fetched.Id),
          client.nextUp(1).catch(() => [])
        ]);
        seasons = found;
        nextEpisode = upNext.find((candidate) => candidate.SeriesId === fetched.Id) ?? null;
        if (found.length > 0) await loadSeason(fetched.Id, found[0].Id);
      }
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Could not load this item.';
    } finally {
      loading = false;
      queueMicrotask(() => focusGroup('detail-actions'));
    }
  }

  function play() {
    if (full.Type === 'Series') {
      const target = nextEpisode ?? episodes[0];
      if (target) onPlay(target);
      return;
    }
    onPlay(full);
  }

  $effect(() => {
    void load(item.Id);
  });
</script>

<div
  class="hero"
  style:background-image={backdrop ? `url(${backdrop})` : 'none'}
  aria-hidden="true"
></div>
<div class="hero-veil" aria-hidden="true"></div>

<div class="screen detail scroller">
  <ScreenHeader title={full.Type === 'Series' ? 'Series' : 'Film'} {onBack} />

  <div class="masthead">
    {#if poster}
      <img class="poster" src={poster} alt="" draggable="false" />
    {/if}

    <div class="facts">
      <h1>{full.Name}</h1>
      {#if tagline}<p class="tagline">{tagline}</p>{/if}

      <div class="meta">
        {#if full.ProductionYear}<span>{full.ProductionYear}</span>{/if}
        {#if runtime}<span>{runtime}</span>{/if}
        {#if full.OfficialRating}<span class="chip">{full.OfficialRating}</span>{/if}
        {#if full.CommunityRating}<span>★ {full.CommunityRating.toFixed(1)}</span>{/if}
        {#if full.Genres?.length}<span>{full.Genres.slice(0, 3).join(' · ')}</span>{/if}
        {#if full.Studios?.length}<span>{full.Studios[0].Name}</span>{/if}
      </div>

      <!--
        What you are about to ask the machine to decode. On a box without
        hardware decode this is the difference between a smooth film and a
        stuttering one, so it belongs above the fold rather than in a submenu.
      -->
      {#if badges.video.length || badges.audio.length}
        <div class="badges">
          {#each badges.video as badge}<span class="badge">{badge}</span>{/each}
          {#each badges.audio as badge}<span class="badge quiet">{badge}</span>{/each}
          {#if badges.subtitleLanguages.length}
            <span class="badge quiet">
              Subtitles: {badges.subtitleLanguages.slice(0, 3).map(languageName).join(', ')}
              {badges.subtitleLanguages.length > 3 ? '…' : ''}
            </span>
          {/if}
        </div>
      {/if}

      {#if full.Overview}
        <p class="overview">{full.Overview}</p>
      {/if}

      {#if crew.length}
        <div class="crew">
          {#each crew as entry}
            <p>
              <span class="crew-label">{entry.label}{entry.names.length > 1 ? 's' : ''}</span>
              {entry.names.slice(0, 3).join(', ')}
            </p>
          {/each}
        </div>
      {/if}

      <div class="actions">
        <button
          class="primary focusable"
          use:focusable={{ group: 'detail-actions', priority: 2, onSelect: play }}
        >
          {playLabel}
        </button>
        {#if canResume && full.Type !== 'Series'}
          <button
            class="focusable"
            use:focusable={{
              group: 'detail-actions',
              onSelect: () =>
                onPlay({ ...full, UserData: { ...full.UserData, PlaybackPositionTicks: 0 } })
            }}
          >
            Start from the beginning
          </button>
        {/if}
      </div>
    </div>
  </div>

  {#if error}
    <p class="state error">{error}</p>
  {:else if loading}
    <p class="state">Loading…</p>
  {:else}
    <!--
      Cast is information, not navigation: there is no person screen to open, so
      these are deliberately not focusable. A wrapping grid rather than a
      scroller, because an unfocusable row could never be scrolled.
    -->
    {#if cast.length}
      <section class="block">
        <h2>Cast</h2>
        <div class="cast">
          {#each cast as person (person.Id)}
            {@const face = client.personImageUrl(person)}
            <div class="person">
              <div class="face">
                {#if face}
                  <img src={face} alt="" loading="lazy" draggable="false" />
                {:else}
                  <span class="initials">{person.Name.slice(0, 1)}</span>
                {/if}
              </div>
              <div class="person-name">{person.Name}</div>
              {#if person.Role}<div class="person-role">{person.Role}</div>{/if}
            </div>
          {/each}
        </div>
      </section>
    {/if}

    {#if full.Type === 'Series'}
      {#if seasons.length > 1}
        <div class="seasons">
          {#each seasons as season (season.Id)}
            <button
              class="season focusable"
              class:current={season.Id === seasonId}
              use:focusable={{ group: 'seasons', onSelect: () => void loadSeason(full.Id, season.Id) }}
            >
              {season.Name}
            </button>
          {/each}
        </div>
      {/if}

      <div class="episodes">
        {#each episodes as episode (episode.Id)}
          <Card
            item={episode}
            {client}
            shape="still"
            group="episodes"
            onSelect={() => onOpen(episode)}
          />
        {/each}
      </div>
    {/if}
  {/if}
</div>

<style>
  /* The backdrop is part of the page here rather than the ambient wash, so it
     can sit at full strength behind the title and fade into what follows. */
  .hero {
    position: fixed;
    inset: 0 0 auto 0;
    height: 62vh;
    z-index: 0;
    background-size: cover;
    background-position: center 18%;
  }

  .hero-veil {
    position: fixed;
    inset: 0;
    z-index: 1;
    /* Fades the backdrop into whatever the page ground is. The two stop
       alphas are theme tokens because paper needs far more of itself over a
       photograph than near-black does before text is readable on it. */
    background:
      linear-gradient(
        to bottom,
        rgb(var(--ground-rgb) / var(--veil-near)) 0%,
        rgb(var(--ground-rgb) / var(--veil-mid)) 45%,
        rgb(var(--ground-rgb) / 1) 72%
      ),
      linear-gradient(to right, rgb(var(--ground-rgb) / 1) 5%, rgb(var(--ground-rgb) / 0.1) 70%);
  }

  .detail {
    position: relative;
    z-index: 2;
    height: 100%;
    padding: var(--safe-y) var(--safe-x);
  }

  .masthead {
    display: flex;
    gap: 2.4rem;
    align-items: flex-end;
    margin: 4vh 0 3rem;
  }

  .poster {
    width: 17vw;
    max-width: 260px;
    border-radius: var(--radius-lg);
    border: 1px solid var(--edge);
    box-shadow: var(--shadow-poster);
    flex: 0 0 auto;
  }

  .facts {
    min-width: 0;
    max-width: 66ch;
  }

  h1 {
    font-size: clamp(2rem, 3.4vw, 3.2rem);
    line-height: 1.1;
    margin-bottom: 0.35rem;
  }

  .tagline {
    margin: 0 0 0.7rem;
    color: var(--ink-dim);
    font-style: italic;
  }

  .meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.9rem;
    color: var(--ink-dim);
    font-size: 0.95rem;
    margin-bottom: 0.9rem;
  }

  .chip {
    border: 1px solid var(--edge);
    border-radius: 4px;
    padding: 0 0.4rem;
  }

  .badges {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
    margin-bottom: 1.2rem;
  }

  .badge {
    font-size: 0.78rem;
    font-weight: 500;
    letter-spacing: 0.03em;
    padding: 0.28rem 0.62rem;
    border-radius: 5px;
    color: var(--ground);
    background: var(--ink);
  }

  .badge.quiet {
    color: var(--ink-dim);
    background: transparent;
    border: 1px solid var(--edge);
    font-weight: 500;
  }

  .overview {
    margin: 0 0 1.2rem;
    color: var(--ink-dim);
    line-height: 1.55;
    /* Long synopses push the actions off screen; four lines is enough to
       decide, and the rest is rarely read from a sofa. */
    display: -webkit-box;
    -webkit-line-clamp: 4;
    line-clamp: 4;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .crew {
    margin-bottom: 1.4rem;
    font-size: 0.92rem;
    color: var(--ink-dim);
  }

  .crew p {
    margin: 0 0 0.2rem;
  }

  .crew-label {
    color: var(--ink-faint);
    margin-right: 0.4rem;
  }

  .actions {
    display: flex;
    gap: 0.7rem;
    flex-wrap: wrap;
  }

  button {
    font: inherit;
    font-size: 1rem;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    padding: 0.8rem 1.5rem;
  }

  .primary {
    font-weight: 500;
    color: var(--ground);
    background: var(--ink);
    border-color: var(--ink);
  }

  .block {
    margin-bottom: 2.6rem;
  }

  h2 {
    font-size: 1.05rem;
    font-weight: 500;
    color: var(--ink-dim);
    margin: 0 0 1rem;
  }

  .cast {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 1.4rem 1rem;
    max-width: 1400px;
  }

  .person {
    min-width: 0;
  }

  .face {
    aspect-ratio: 1;
    width: 84px;
    border-radius: 50%;
    overflow: hidden;
    background: var(--raised);
    border: 1px solid var(--edge);
    display: grid;
    place-items: center;
    margin-bottom: 0.55rem;
  }

  .face img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .initials {
    font-size: 1.6rem;
    color: var(--ink-faint);
  }

  .person-name {
    font-size: 0.9rem;
    font-weight: 500;
  }

  .person-role {
    font-size: 0.84rem;
    color: var(--ink-faint);
  }

  .person-name,
  .person-role {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .seasons {
    display: flex;
    gap: 0.55rem;
    flex-wrap: wrap;
    margin-bottom: 1.5rem;
  }

  .season {
    font-size: 0.95rem;
    padding: 0.55rem 1.2rem;
    border-radius: 999px;
  }

  .season.current {
    border-color: var(--accent-text);
    color: var(--accent-text);
  }

  .episodes {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(var(--still-width), 1fr));
    gap: 1.8rem 1.4rem;
    padding: 0.5rem 0.5rem 2rem;
  }

  .state {
    color: var(--ink-dim);
  }

  .state.error {
    color: var(--danger);
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps these rules alive. */
  button:global(.is-focused) {
    transform: none;
    box-shadow: 0 0 0 3px var(--ink);
  }
</style>
