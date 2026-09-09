<script lang="ts">
  import { focusable } from '../lib/nav';

  interface Props {
    title: string;
    onBack: () => void;
  }

  const { title, onBack }: Props = $props();
</script>

<!--
  A visible way out. The B button and Escape both work, but a control you can
  see is the difference between knowing you can leave and hoping you can —
  and on a screen whose keyboard eats Backspace, hoping is not enough.
-->
<header>
  <button class="back focusable" use:focusable={{ group: 'chrome', onSelect: onBack }}>
    <span class="chevron" aria-hidden="true">‹</span> Back
  </button>
  <h1>{title}</h1>
</header>

<style>
  header {
    display: flex;
    align-items: center;
    gap: 1.2rem;
    margin-bottom: 1.6rem;
  }

  h1 {
    font-size: 1.35rem;
    letter-spacing: -0.02em;
  }

  .back {
    font: inherit;
    font-size: 0.95rem;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: 999px;
    padding: 0.5rem 1.2rem 0.5rem 0.95rem;
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
  }

  .chevron {
    font-size: 1.25em;
    line-height: 1;
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps this rule alive. */
  .back:global(.is-focused) {
    color: var(--ground);
    background: var(--ink);
    border-color: var(--ink);
  }
</style>
