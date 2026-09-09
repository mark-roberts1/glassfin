<script lang="ts">
  import Logo from '../components/Logo.svelte';
  import { focusable, focusFirst } from '../lib/nav';
  import { textEntry } from '../lib/textentry.svelte';
  import { Jellyfin } from '../lib/jellyfin';
  import { session } from '../lib/session.svelte';

  /**
   * Three steps, and only the first needs typing.
   *
   * Quick Connect is the default because it is the only sign-in that respects
   * the couch bar: the server shows a code, you approve it from a phone, and no
   * password is ever spelled out on a D-pad. The password path stays for
   * servers with Quick Connect switched off.
   */
  type Stage = 'address' | 'choose' | 'quick' | 'password';

  const POLL_INTERVAL_MS = 3000;

  let stage = $state<Stage>('address');
  let address = $state('');
  let quickEnabled = $state(false);
  let code = $state('');
  let username = $state('');
  let password = $state('');
  let error = $state<string | null>(null);
  let busy = $state(false);

  let poller: ReturnType<typeof setInterval> | undefined;

  function editAddress() {
    textEntry.open({
      label: 'Server address',
      value: address,
      placeholder: 'nas.local:8096',
      onCommit: (value) => {
        address = value.trim();
        if (address) void checkServer();
      }
    });
  }

  async function checkServer() {
    busy = true;
    error = null;
    try {
      quickEnabled = await Jellyfin.quickConnectEnabled(address);
      stage = quickEnabled ? 'choose' : 'password';
    } finally {
      busy = false;
      queueMicrotask(focusFirst);
    }
  }

  async function startQuickConnect() {
    error = null;
    busy = true;
    try {
      const state = await Jellyfin.quickConnectInitiate(address);
      code = state.code;
      stage = 'quick';

      poller = setInterval(async () => {
        try {
          if (!(await Jellyfin.quickConnectApproved(address, state.secret))) return;
          clearInterval(poller);
          session.signIn(await Jellyfin.authenticateWithQuickConnect(address, state.secret));
        } catch (cause) {
          clearInterval(poller);
          error = cause instanceof Error ? cause.message : 'Quick Connect failed.';
          stage = 'choose';
        }
      }, POLL_INTERVAL_MS);
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Quick Connect failed.';
    } finally {
      busy = false;
      queueMicrotask(focusFirst);
    }
  }

  function editField(which: 'username' | 'password') {
    textEntry.open({
      label: which === 'username' ? 'Username' : 'Password',
      value: which === 'username' ? username : password,
      onCommit: (value) => {
        if (which === 'username') username = value;
        else password = value;
      }
    });
  }

  async function signInWithPassword() {
    error = null;
    busy = true;
    try {
      session.signIn(await Jellyfin.authenticate(address, username, password));
    } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Could not reach that server.';
    } finally {
      busy = false;
    }
  }

  function back() {
    clearInterval(poller);
    stage = quickEnabled ? 'choose' : 'address';
    queueMicrotask(focusFirst);
  }

  $effect(() => () => clearInterval(poller));

  $effect(() => {
    focusFirst();
  });
</script>

<div class="screen sign-in">
  <div class="panel">
    <!-- The one screen with room for the mark at a size that shows the facets,
         and the one screen where nobody is in a hurry. -->
    <h1><Logo size={64} wordmark /></h1>

    {#if stage === 'address'}
      <p class="lede">Where does your Jellyfin server live?</p>
      <button class="field focusable" use:focusable={{ group: 'login', priority: 1, onSelect: editAddress }}>
        <span class="field-label">Server</span>
        <span class="field-value" class:empty={!address}>{address || 'nas.local:8096'}</span>
      </button>
      {#if address}
        <button class="primary focusable" use:focusable={{ group: 'login', onSelect: checkServer }}>
          {busy ? 'Checking…' : 'Continue'}
        </button>
      {/if}

    {:else if stage === 'choose'}
      <p class="lede">Signed in as this device on {address}</p>
      <button class="primary focusable" use:focusable={{ group: 'login', priority: 1, onSelect: startQuickConnect }}>
        {busy ? 'Starting…' : 'Use Quick Connect'}
      </button>
      <button class="focusable" use:focusable={{ group: 'login', onSelect: () => (stage = 'password') }}>
        Sign in with a password
      </button>
      <button class="quiet focusable" use:focusable={{ group: 'login', onSelect: () => (stage = 'address') }}>
        Change server
      </button>

    {:else if stage === 'quick'}
      <p class="lede">Open Jellyfin on your phone or computer and enter this code.</p>
      <div class="code">{code}</div>
      <p class="waiting">Waiting for approval…</p>
      <button class="quiet focusable" use:focusable={{ group: 'login', priority: 1, onSelect: back }}>
        Cancel
      </button>

    {:else}
      <p class="lede">Sign in to {address}</p>
      <button class="field focusable" use:focusable={{ group: 'login', priority: 1, onSelect: () => editField('username') }}>
        <span class="field-label">Username</span>
        <span class="field-value" class:empty={!username}>{username || 'Not set'}</span>
      </button>
      <button class="field focusable" use:focusable={{ group: 'login', onSelect: () => editField('password') }}>
        <span class="field-label">Password</span>
        <span class="field-value" class:empty={!password}>{password ? '•'.repeat(password.length) : 'Not set'}</span>
      </button>
      <button class="primary focusable" use:focusable={{ group: 'login', onSelect: signInWithPassword }}>
        {busy ? 'Signing in…' : 'Sign in'}
      </button>
      {#if quickEnabled}
        <button class="quiet focusable" use:focusable={{ group: 'login', onSelect: back }}>Back</button>
      {/if}
    {/if}

    {#if error}
      <p class="error" role="alert">{error}</p>
    {/if}
  </div>
</div>

<style>
  .sign-in {
    display: grid;
    place-items: center;
  }

  .panel {
    width: min(520px, 74vw);
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  h1 {
    line-height: 1;
    margin-bottom: 0.4rem;
  }

  .lede {
    margin: -0.25rem 0 0.75rem;
    color: var(--ink-dim);
  }

  button {
    font: inherit;
    text-align: left;
    color: var(--ink);
    background: var(--raised);
    border: 1px solid var(--edge);
    border-radius: var(--radius);
    padding: 0.85rem 1rem;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .field-label {
    font-size: 0.8rem;
    color: var(--ink-dim);
  }

  .field-value.empty {
    color: var(--ink-faint);
  }

  .primary {
    text-align: center;
    font-weight: 500;
    color: var(--ground);
    background: var(--ink);
    border-color: var(--ink);
  }

  .quiet {
    text-align: center;
    background: transparent;
    color: var(--ink-dim);
  }

  /* The code is the whole point of the screen: readable from a sofa, and
     unmistakable when you are holding a phone in the other hand. */
  .code {
    font-size: 3.4rem;
    font-weight: 500;
    letter-spacing: 0.35em;
    text-align: center;
    padding: 1.2rem 0 1rem;
    text-indent: 0.35em;
  }

  .waiting {
    margin: 0;
    text-align: center;
    color: var(--ink-dim);
  }

  /* nav.ts adds .is-focused at runtime, so :global keeps this rule alive.
     Scale would blur text at this size; the ring carries the signal. */
  button:global(.is-focused) {
    transform: none;
    box-shadow: 0 0 0 3px var(--ink);
  }

  .error {
    color: var(--danger);
    font-size: 0.9rem;
    margin: 0.25rem 0 0;
  }
</style>
