<script lang="ts">
  import { playback } from '../lib/playback.svelte';
  import { clock } from '../lib/format';

  interface Props {
    /** False in a browser, where there is no mpv and nothing is on screen. */
    native: boolean;
    /** Artwork for the browser stand-in. Never shown in the shell — mpv is there. */
    backdrop: string | null;
  }

  const { native, backdrop }: Props = $props();

  const item = $derived(playback.item);

  const title = $derived.by(() => {
    if (!item) return '';
    if (item.Type === 'Episode') return item.SeriesName ?? item.Name;
    return item.Name;
  });

  const subtitle = $derived.by(() => {
    if (!item || item.Type !== 'Episode') return '';
    const code =
      item.ParentIndexNumber != null && item.IndexNumber != null
        ? `S${item.ParentIndexNumber}:E${item.IndexNumber}`
        : '';
    return [code, item.Name].filter(Boolean).join(' · ');
  });

  const percent = $derived(
    playback.durationMs > 0 ? (playback.positionMs / playback.durationMs) * 100 : 0
  );

  const remaining = $derived(Math.max(0, playback.durationMs - playback.positionMs));
</script>

{#if item}
  <!--
    In the shell, mpv draws the video in a layer behind this page, so the page
    must be transparent for any of it to be visible — see .playing in app.css.
    In a browser there is no mpv at all, which is why the panel below exists:
    without it, starting playback looks exactly like the app freezing.
  -->
  {#if !native}
    <div class="stand-in" style:background-image={backdrop ? `url(${backdrop})` : 'none'}>
      <div class="stand-in-veil"></div>
      <p class="stand-in-title">No video here</p>
      <p class="stand-in-body">
        mpv lives in the native shell. This is the simulated player: position advances, transport
        controls work, and progress is reported to your server for real.
      </p>
    </div>
  {/if}

  <div class="transport" class:hidden={native && !playback.chrome}>
    <div class="titles">
      <h1>{title}</h1>
      {#if subtitle}<p class="sub">{subtitle}</p>{/if}
    </div>

    <div class="bar">
      <span class="time">{clock(playback.positionMs)}</span>
      <div class="track">
        <div class="fill" style:width="{percent}%"></div>
        <div class="head" style:left="{percent}%"></div>
      </div>
      <span class="time">−{clock(remaining)}</span>
    </div>

    <div class="hints">
      <span class="state">
        {playback.switching ? 'Changing track…' : playback.paused ? 'Paused' : 'Playing'}
      </span>
      <span><b>OK</b> {playback.paused ? 'play' : 'pause'}</span>
      <span><b>←  →</b> skip 30s</span>
      <span><b>Up</b> audio &amp; subtitles</span>
      <span><b>Back</b> stop</span>
    </div>
  </div>
{/if}

<style>
  .stand-in {
    position: fixed;
    inset: 0;
    z-index: 12;
    color: var(--over-ink);
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 0.5rem;
    text-align: center;
    padding: 0 var(--safe-x);
    background-color: #000;
    background-size: cover;
    background-position: center;
  }

  /* Dimmed hard: this stands in for a moving picture, and it must not be
     mistaken for one, but a black void is a poor surface to judge the
     transport against. */
  .stand-in-veil {
    position: absolute;
    inset: 0;
    background: rgba(0, 0, 0, 0.78);
  }

  .stand-in-title,
  .stand-in-body {
    position: relative;
  }

  .stand-in-title {
    margin: 0;
    font-size: 1.4rem;
    font-weight: 500;
  }

  .stand-in-body {
    margin: 0;
    max-width: 52ch;
    color: var(--over-ink-dim);
  }

  .transport {
    position: fixed;
    z-index: 16;
    left: 0;
    right: 0;
    bottom: 0;
    padding: 6rem var(--safe-x) calc(var(--safe-y) + 1.5rem);
    /* Fixed ink, not the theme's: this reads against a film. The page behind
       it may be paper, and paper-on-picture is illegible at any hour. */
    color: var(--over-ink);
    background: linear-gradient(to top, rgba(0, 0, 0, 0.92) 30%, rgba(0, 0, 0, 0));
    transition: opacity var(--slow) var(--ease);
  }

  .transport.hidden {
    opacity: 0;
  }

  .titles {
    margin-bottom: 1.2rem;
  }

  h1 {
    font-size: 1.8rem;
    letter-spacing: -0.02em;
  }

  .sub {
    margin: 0.25rem 0 0;
    color: var(--over-ink-dim);
  }

  .bar {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .time {
    font-variant-numeric: tabular-nums;
    font-size: 0.95rem;
    color: var(--over-ink-dim);
    min-width: 5.5ch;
  }

  .track {
    position: relative;
    flex: 1;
    height: 5px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.22);
  }

  .fill {
    height: 100%;
    border-radius: 999px;
    background: var(--over-ink);
  }

  /* The head is what the eye tracks while seeking; the fill alone is too
     subtle to follow at a distance. */
  .head {
    position: absolute;
    top: 50%;
    width: 14px;
    height: 14px;
    margin-left: -7px;
    border-radius: 50%;
    background: var(--over-ink);
    transform: translateY(-50%);
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.8);
  }

  .hints {
    display: flex;
    gap: 1.6rem;
    margin-top: 1rem;
    font-size: 0.88rem;
    color: var(--over-ink-faint);
  }

  .hints .state {
    color: var(--over-ink-dim);
    font-weight: 500;
  }

  .hints b {
    color: var(--over-ink-dim);
    font-weight: 500;
  }

  @media (prefers-reduced-motion: reduce) {
    .transport {
      transition: none;
    }
  }
</style>
