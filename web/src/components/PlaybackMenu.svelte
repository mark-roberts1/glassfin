<script lang="ts">
  import { focusable, focusGroup, resetGroup } from '../lib/nav';
  import {
    playback,
    setAudioTrack,
    setSubtitleTrack
  } from '../lib/playback.svelte';
  import { languageName } from '../lib/settings.svelte';
  import type { MediaStream } from '../lib/jellyfin';

  interface Props {
    onClose: () => void;
  }

  const { onClose }: Props = $props();

  /**
   * The server's own DisplayTitle is usually the best label — "English -
   * AAC - 5.1" says more than anything assembled here. The fallback is for
   * streams that have none.
   */
  function label(stream: MediaStream): string {
    if (stream.DisplayTitle) return stream.DisplayTitle;
    const parts = [
      stream.Language ? languageName(stream.Language) : 'Unknown',
      stream.Codec?.toUpperCase()
    ].filter(Boolean);
    return parts.join(' · ');
  }

  function badges(stream: MediaStream): string[] {
    const marks: string[] = [];
    if (stream.IsDefault) marks.push('Default');
    if (stream.IsForced) marks.push('Forced');
    if (stream.DeliveryMethod === 'Encode') marks.push('Burned in');
    return marks;
  }

  $effect(() => {
    resetGroup('menu-audio');
    resetGroup('menu-subtitles');
    queueMicrotask(() => {
      if (!focusGroup('menu-audio')) focusGroup('menu-subtitles');
    });
  });
</script>

<div class="scrim"></div>

<div class="menu">
  <div class="column">
    <h2>Audio</h2>
    {#if playback.audioTracks.length === 0}
      <p class="none">No audio tracks reported.</p>
    {:else}
      {#each playback.audioTracks as track (track.Index)}
        <button
          class="track focusable"
          class:current={track.Index === playback.audioIndex}
          use:focusable={{
            group: 'menu-audio',
            onSelect: () => {
              void setAudioTrack(track.Index);
              onClose();
            }
          }}
        >
          <span class="tick">{track.Index === playback.audioIndex ? '✓' : ''}</span>
          <span class="label">{label(track)}</span>
          {#each badges(track) as badge}<span class="badge">{badge}</span>{/each}
        </button>
      {/each}
    {/if}
  </div>

  <div class="column">
    <h2>Subtitles</h2>
    <button
      class="track focusable"
      class:current={playback.subtitleIndex === null}
      use:focusable={{
        group: 'menu-subtitles',
        onSelect: () => {
          void setSubtitleTrack(null);
          onClose();
        }
      }}
    >
      <span class="tick">{playback.subtitleIndex === null ? '✓' : ''}</span>
      <span class="label">Off</span>
    </button>

    {#each playback.subtitleTracks as track (track.Index)}
      <button
        class="track focusable"
        class:current={track.Index === playback.subtitleIndex}
        use:focusable={{
          group: 'menu-subtitles',
          onSelect: () => {
            void setSubtitleTrack(track.Index);
            onClose();
          }
        }}
      >
        <span class="tick">{track.Index === playback.subtitleIndex ? '✓' : ''}</span>
        <span class="label">{label(track)}</span>
        {#each badges(track) as badge}<span class="badge">{badge}</span>{/each}
      </button>
    {/each}
  </div>
</div>

<p class="footnote">
  Changing a track the server is transcoding reloads the stream and takes a moment.
</p>

<style>
  /* The menu opens over the film, so it is dark in both themes — see the
     "over the picture" block in app.css. */
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 17;
    background: var(--over-scrim);
  }

  .menu {
    position: fixed;
    z-index: 18;
    left: var(--safe-x);
    right: var(--safe-x);
    bottom: calc(var(--safe-y) + 4rem);
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 3rem;
    max-height: 58vh;
    overflow: auto;
    scrollbar-width: none;
  }

  .menu::-webkit-scrollbar {
    display: none;
  }

  .column {
    min-width: 0;
  }

  h2 {
    font-size: 1rem;
    color: var(--over-ink-dim);
    margin: 0 0 0.9rem;
  }

  .track {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 0.7rem;
    font: inherit;
    text-align: left;
    color: var(--over-ink);
    background: var(--over-panel);
    border: 1px solid var(--over-edge);
    border-radius: var(--radius);
    padding: 0.7rem 1rem;
    margin-bottom: 0.5rem;
  }

  .tick {
    flex: 0 0 1ch;
    color: var(--over-accent);
  }

  .label {
    flex: 1 1 auto;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .track.current .label {
    font-weight: 500;
  }

  .badge {
    flex: 0 0 auto;
    font-size: 0.74rem;
    color: var(--over-ink-faint);
    border: 1px solid var(--over-edge);
    border-radius: 4px;
    padding: 0.1rem 0.4rem;
  }

  .none {
    color: var(--over-ink-faint);
    margin: 0;
  }

  .footnote {
    position: fixed;
    z-index: 18;
    left: var(--safe-x);
    bottom: calc(var(--safe-y) + 1.5rem);
    margin: 0;
    font-size: 0.85rem;
    color: var(--over-ink-faint);
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps this rule alive. */
  .track:global(.is-focused) {
    transform: none;
    box-shadow: 0 0 0 3px var(--over-ink);
  }
</style>
