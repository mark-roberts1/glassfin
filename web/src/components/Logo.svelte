<script lang="ts" module>
  /*
   * Gradient and mask ids are document-global, so two marks on one screen —
   * the sign-in lockup behind a modal keyboard, say — would otherwise share
   * whichever definition rendered last.
   */
  let instances = 0;
</script>

<script lang="ts">
  /**
   * The Glassfin mark, and optionally the wordmark beside it.
   *
   * Geometry is transcribed from the style guide's primary lockup: thirteen
   * cuts across a fin, twelve facets between them running Lead to Trail, and a
   * mask fading the tail into the surface.
   *
   * Two things about it are not decoration.
   *
   * The facet colours come from --fin-1..12, which app.css redefines per
   * theme. The guide draws a darker ramp on paper and a lighter one on ink;
   * this is how the mark obeys that without knowing what a theme is.
   *
   * The cuts are painted in the *background* colour, not in an ink. They are
   * gaps, not lines. Anywhere other than the page ground — on a pill, on a
   * card — the caller has to say so with --logo-cut.
   */

  interface Props {
    /** Height of the mark in CSS pixels. */
    size?: number;
    /** Set the wordmark beside it, as the primary lockup does. */
    wordmark?: boolean;
  }

  const { size = 48, wordmark = false }: Props = $props();

  /*
   * From the guide: "Below 32px the facets close up. The flat silhouette is
   * the small-size mark, not a fallback."
   */
  const FACET_FLOOR = 32;
  const faceted = $derived(size >= FACET_FLOOR);

  /* The artboard is 156 × 106; hold the aspect at whatever height. */
  const width = $derived((size * 156) / 106);

  const uid = `fin-${++instances}`;

  const FACETS = [
    'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 L 31.05 110.19 Z',
    'M 31.05 110.19 L 53.54 44.03 Q 66 41.02 70.69 29.1 L 43.69 108.5 Z',
    'M 43.69 108.5 L 70.69 29.1 Q 78.62 29.91 83.84 23.89 L 55.56 107.05 Z',
    'M 55.56 107.05 L 83.84 23.89 Q 88.97 27.11 94.56 24.76 L 66.96 105.94 Z',
    'M 66.96 105.94 L 94.56 24.76 Q 97.87 29.59 103.72 29.65 L 78.02 105.24 Z',
    'M 78.02 105.24 L 103.72 29.65 Q 105.85 35.53 111.88 37.16 L 88.81 105 Z',
    'M 88.81 105 L 111.88 37.16 Q 113.29 43.68 119.44 46.27 L 99.39 105.24 Z',
    'M 99.39 105.24 L 119.44 46.27 Q 120.49 53.11 126.7 56.18 L 109.79 105.94 Z',
    'M 109.79 105.94 L 126.7 56.18 Q 127.68 63.09 133.9 66.25 L 120.03 107.05 Z',
    'M 120.03 107.05 L 133.9 66.25 Q 135.05 72.98 141.22 75.91 L 130.14 108.5 Z',
    'M 130.14 108.5 L 141.22 75.91 Q 142.75 82.24 148.81 84.63 L 140.12 110.19 Z',
    'M 140.12 110.19 L 148.81 84.63 Q 151.14 90.15 157 91.41 L 150 112 Z'
  ];

  const CUTS = [
    'M 16 112 L 24.98 85.6',
    'M 31.05 110.19 L 53.54 44.03',
    'M 43.69 108.5 L 70.69 29.1',
    'M 55.56 107.05 L 83.84 23.89',
    'M 66.96 105.94 L 94.56 24.76',
    'M 78.02 105.24 L 103.72 29.65',
    'M 88.81 105 L 111.88 37.16',
    'M 99.39 105.24 L 119.44 46.27',
    'M 109.79 105.94 L 126.7 56.18',
    'M 120.03 107.05 L 133.9 66.25',
    'M 130.14 108.5 L 141.22 75.91',
    'M 140.12 110.19 L 148.81 84.63',
    'M 150 112 L 157 91.41'
  ];

  const SILHOUETTE =
    'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 Q 66 41.02 70.69 29.1 ' +
    'Q 78.62 29.91 83.84 23.89 Q 88.97 27.11 94.56 24.76 Q 97.87 29.59 103.72 29.65 ' +
    'Q 105.85 35.53 111.88 37.16 Q 113.29 43.68 119.44 46.27 Q 120.49 53.11 126.7 56.18 ' +
    'Q 127.68 63.09 133.9 66.25 Q 135.05 72.98 141.22 75.91 Q 142.75 82.24 148.81 84.63 ' +
    'Q 151.14 90.15 157 91.41 L 150 112 L 140.12 110.19 L 130.14 108.5 L 120.03 107.05 ' +
    'L 109.79 105.94 L 99.39 105.24 L 88.81 105 L 78.02 105.24 L 66.96 105.94 ' +
    'L 55.56 107.05 L 43.69 108.5 L 31.05 110.19 L 16 112 Z';
</script>

<span class="lockup" style:gap="{size * 0.16}px">
  <svg viewBox="10 14 156 106" {width} height={size} role="img" aria-label="Glassfin">
    {#if faceted}
      <defs>
        <!-- The tail dissolves into the surface rather than ending. -->
        <linearGradient id="{uid}-fade" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#ffffff" stop-opacity="1" />
          <stop offset=".58" stop-color="#ffffff" stop-opacity=".82" />
          <stop offset="1" stop-color="#ffffff" stop-opacity=".2" />
        </linearGradient>
        <mask id="{uid}-mask">
          <rect x="10" y="14" width="156" height="106" fill="url(#{uid}-fade)" />
        </mask>
      </defs>

      <g mask="url(#{uid}-mask)">
        {#each FACETS as d, index (d)}
          <path {d} fill="var(--fin-{index + 1})" />
        {/each}
      </g>

      <g
        fill="none"
        stroke="var(--logo-cut, var(--ground))"
        stroke-width="2.1"
        stroke-linecap="round"
      >
        {#each CUTS as d (d)}<path {d} />{/each}
      </g>

      <!-- A hairline of the page's own ink, so the tail still has an edge
           where the mask has taken the colour out of it. -->
      <path
        d={SILHOUETTE}
        fill="none"
        stroke="var(--ink)"
        stroke-opacity=".32"
        stroke-width="1"
        stroke-linejoin="round"
      />
    {:else}
      <!-- One ink. Facets become cuts in the silhouette. -->
      <path d={SILHOUETTE} fill="var(--ink)" />
      <g
        fill="none"
        stroke="var(--logo-cut, var(--ground))"
        stroke-width="2.2"
        stroke-linecap="round"
      >
        {#each CUTS as d (d)}<path {d} />{/each}
      </g>
    {/if}
  </svg>

  {#if wordmark}
    <span class="word" style:font-size="{size * 0.42}px">glassfin</span>
  {/if}
</span>

<style>
  .lockup {
    display: inline-flex;
    align-items: center;
  }

  /* 500 and -.02em, exactly as the guide sets the wordmark. Lowercase in the
     markup rather than by transform, because that is what the word is. */
  .word {
    font-weight: 500;
    letter-spacing: -0.02em;
    line-height: 1;
    color: var(--ink);
  }
</style>
