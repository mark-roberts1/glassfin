<script lang="ts">
  import { focusable, focusGroup, resetGroup } from '../lib/nav';
  import { textEntry } from '../lib/textentry.svelte';

  /**
   * A grid, not the alphabet strip tvOS uses. A strip is a long horizontal
   * travel — twenty-five presses to reach Z — which is tolerable with a
   * touch remote and miserable with a D-pad. Six columns keeps the worst
   * case to about seven presses in each direction.
   *
   * Letters are typed lowercase, matching an unshifted physical key, and
   * Shift is sticky rather than momentary — a D-pad has no second hand to
   * hold a modifier with, so it toggles case instead of applying to just the
   * next key. A physical keyboard genuinely cannot report case here (see the
   * note in host.ts), but this is a synthetic keyboard: nothing stops it from
   * inserting whichever case its own Shift key is showing.
   */
  const LETTERS = [
    ['A', 'B', 'C', 'D', 'E', 'F'],
    ['G', 'H', 'I', 'J', 'K', 'L'],
    ['M', 'N', 'O', 'P', 'Q', 'R'],
    ['S', 'T', 'U', 'V', 'W', 'X'],
    ['Y', 'Z']
  ];

  /** Digits and symbols, behind their own key — a password field needs more
   *  than the half-dozen that used to share the letter grid. */
  const SYMBOLS = [
    ['0', '1', '2', '3', '4', '5'],
    ['6', '7', '8', '9', '!', '@'],
    ['#', '$', '%', '^', '&', '*'],
    ['(', ')', '-', '_', '=', '+'],
    ['[', ']', '{', '}', ';', ':'],
    ["'", '"', ',', '.', '<', '>'],
    ['/', '?', '~', '`', '\\', '|']
  ];

  let page = $state<'letters' | 'symbols'>('letters');
  let shift = $state(false);

  const rows = $derived(page === 'letters' ? LETTERS : SYMBOLS);

  /** What a key actually types — lowercase unless Shift is on; symbols are unaffected. */
  function typed(key: string): string {
    return page === 'letters' && !shift ? key.toLowerCase() : key;
  }

  const field = $derived(textEntry.current);
  const shown = $derived(field?.value ?? '');

  $effect(() => {
    // Focus starts on the keys, not on Done, so the first press types. Named
    // explicitly: when this is a modal sheet, focusFirst would reach past it to
    // the screen underneath.
    resetGroup('osk');
    queueMicrotask(() => focusGroup('osk'));
  });
</script>

{#if field}
  <div class="sheet">
    <div class="entry">
      <span class="label">{field.label}</span>
      <!--
        The caret goes *before* the placeholder, never after it. With the caret
        trailing, "nas.local:8096" reads as something already typed that the
        next keypress will extend — and the next keypress replaces it instead.
        In front, with the text greyed, it reads as what it is: an empty field
        showing an example.
      -->
      <div class="value">
        {#if shown}
          <span>{shown}</span><span class="caret"></span>
        {:else}
          <span class="caret"></span><span class="ghost">{field.placeholder ?? ''}</span>
        {/if}
      </div>
    </div>

    <div class="keys">
      {#each rows as row}
        {#each row as key}
          <button
            class="key focusable"
            use:focusable={{ group: 'osk', priority: 1, onSelect: () => textEntry.insert(typed(key)) }}
          >
            {typed(key)}
          </button>
        {/each}
      {/each}

      {#if page === 'letters'}
        <button
          class="key wide-key focusable"
          class:active={shift}
          use:focusable={{ group: 'osk', onSelect: () => (shift = !shift) }}
        >
          Shift
        </button>
        <button
          class="key wide-key focusable"
          use:focusable={{ group: 'osk', onSelect: () => (page = 'symbols') }}
        >
          123
        </button>
      {:else}
        <button
          class="key wide-key focusable"
          use:focusable={{ group: 'osk', onSelect: () => (page = 'letters') }}
        >
          ABC
        </button>
      {/if}
    </div>

    <div class="controls">
      <button
        class="wide focusable"
        use:focusable={{ group: 'osk-controls', onSelect: () => textEntry.insert(' ') }}
      >
        Space
      </button>
      <button
        class="focusable"
        use:focusable={{ group: 'osk-controls', onSelect: () => textEntry.backspace() }}
      >
        Delete
      </button>
      <button
        class="focusable"
        use:focusable={{ group: 'osk-controls', onSelect: () => textEntry.clear() }}
      >
        Clear
      </button>
      <button
        class="primary focusable"
        use:focusable={{ group: 'osk-controls', onSelect: () => textEntry.commit() }}
      >
        Done
      </button>
    </div>

    <p class="hint">A keyboard works here too — type straight into the field.</p>
  </div>
{/if}

<style>
  .sheet {
    display: flex;
    flex-direction: column;
    gap: 1.4rem;
    align-items: center;
  }

  .entry {
    /* Full width of whatever hosts this: the centred modal sheet everywhere
       else, but Search embeds the keyboard inline in a pane far narrower
       than 640px, and a fixed width there overflowed it. */
    width: 100%;
    max-width: 640px;
  }

  .label {
    font-size: 0.85rem;
    color: var(--ink-dim);
  }

  .value {
    margin-top: 0.4rem;
    padding: 0.7rem 0.9rem;
    min-height: 3rem;
    font-size: 1.4rem;
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    word-break: break-all;
  }

  .ghost {
    color: var(--ink-faint);
  }

  .caret {
    display: inline-block;
    width: 2px;
    height: 1.15em;
    /* Logical, not left: it sits after typed text and before a placeholder. */
    margin-inline: 2px;
    vertical-align: text-bottom;
    background: var(--accent-text);
    animation: blink 1.1s steps(1) infinite;
  }

  @keyframes blink {
    50% {
      opacity: 0;
    }
  }

  .keys {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 0.55rem;
  }

  .controls {
    display: flex;
    gap: 0.55rem;
    flex-wrap: wrap;
    justify-content: center;
  }

  button {
    font: inherit;
    font-size: 1.05rem;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    min-width: 3.6rem;
    padding: 0.7rem 1rem;
  }

  .key {
    width: 3.6rem;
    text-align: center;
  }

  .wide-key {
    /* Sits in the same grid as the single-character keys, but Shift/123/ABC
       need room for a word, not a glyph — spans two columns rather than
       carrying its own fixed width like the modal-only .wide does. */
    width: auto;
    grid-column: span 2;
    font-size: 0.85rem;
  }

  .key.active {
    color: var(--ground);
    background: var(--accent);
    border-color: var(--accent);
  }

  .wide {
    min-width: 9rem;
  }

  .primary {
    color: var(--ground);
    background: var(--ink);
    border-color: var(--ink);
    font-weight: 500;
  }

  /* nav.ts adds .is-focused at runtime, so Svelte cannot see it; :global keeps
     these rules. Keys are small, so they scale a little less than artwork. */
  button:global(.is-focused) {
    transform: scale(1.1);
    box-shadow:
      0 0 0 3px var(--ink),
      var(--shadow-lift);
  }

  .hint {
    margin: 0;
    font-size: 0.85rem;
    color: var(--ink-faint);
  }

  @media (prefers-reduced-motion: reduce) {
    .caret {
      animation: none;
    }
  }
</style>
