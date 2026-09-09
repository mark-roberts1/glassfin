/**
 * Spatial navigation.
 *
 * The shell hands us six semantic actions and no pointer. Everything reachable
 * has to be reachable by geometry, focus has to be visible at all times, and it
 * must never be lost — those are the terms of the couch bar in CLAUDE.md.
 *
 * Two rules keep movement predictable, and both exist because a carousel
 * scrolls independently of the page:
 *
 * Left and right stay on the line they started on. You cannot fall off the end
 * of a row into the next one.
 *
 * Up and down into a carousel land on its first item, not on whatever happens
 * to be at the same screen x. A row is scrolled to a position the viewer did
 * not choose and cannot see the start of, so "the column you were in" points at
 * nothing meaningful — which is what makes geometric entry feel random. Grids
 * and static button rows are aligned to the page, so they keep the column.
 */

import type { HostAction } from './host';

export type Direction = 'up' | 'down' | 'left' | 'right';

export interface FocusableOptions {
  /** Items sharing a group are a row or grid; the group remembers its last focus. */
  group?: string;
  /**
   * Where focus lands when it arrives in this group from another one.
   *
   * `nearest` (the default) keeps the visual column, which is right for
   * anything laid out against the page. `first` goes to the start of the group
   * — the only sane answer for a horizontally scrolling row.
   */
  enter?: 'first' | 'nearest';
  onSelect?: () => void;
  /** Fired when this element receives focus. Drives the ambient backdrop. */
  onFocus?: () => void;
  /** Skip during navigation without unregistering, e.g. a disabled control. */
  disabled?: boolean;
  /** Weight this element for initial focus when nothing is focused yet. Higher wins. */
  priority?: number;
}

interface Entry {
  node: HTMLElement;
  options: FocusableOptions;
}

const entries = new Map<HTMLElement, Entry>();
const groupMemory = new Map<string, HTMLElement>();
let current: HTMLElement | null = null;

const listeners = new Set<(node: HTMLElement | null) => void>();

export function onFocusChange(handler: (node: HTMLElement | null) => void): () => void {
  listeners.add(handler);
  return () => listeners.delete(handler);
}

function isNavigable(entry: Entry): boolean {
  if (entry.options.disabled) return false;
  const rect = entry.node.getBoundingClientRect();
  if (rect.width === 0 && rect.height === 0) return false;
  return entry.node.isConnected;
}

function candidates(): Entry[] {
  return [...entries.values()].filter(isNavigable);
}

/**
 * Lower is better; null means the candidate is not in this direction.
 *
 * Distance along the direction of travel dominates. Misalignment across it is
 * penalised heavily, so that pressing down from a poster lands under the poster
 * rather than wherever happens to be marginally closer.
 */
function score(from: DOMRect, to: DOMRect, direction: Direction): number | null {
  const horizontal = direction === 'left' || direction === 'right';

  const fromNear = direction === 'right' ? from.right
    : direction === 'left' ? from.left
    : direction === 'down' ? from.bottom
    : from.top;
  const toNear = direction === 'right' ? to.left
    : direction === 'left' ? to.right
    : direction === 'down' ? to.top
    : to.bottom;

  // Must lie in the direction of travel. The tolerance forgives sub-pixel
  // layout and lets same-row items with ragged heights still qualify.
  const travel = direction === 'right' || direction === 'down'
    ? toNear - fromNear
    : fromNear - toNear;
  if (travel < -1) return null;

  const fromStart = horizontal ? from.top : from.left;
  const fromEnd = horizontal ? from.bottom : from.right;
  const toStart = horizontal ? to.top : to.left;
  const toEnd = horizontal ? to.bottom : to.right;

  const overlap = Math.min(fromEnd, toEnd) - Math.max(fromStart, toStart);

  // A horizontal move stays on the line it started on. Something that shares no
  // vertical band with the focused element is not to its left or right in any
  // sense the viewer would recognise — it is on another row. Without this the
  // last card in a carousel has somewhere to go, and where it goes is decided
  // by geometry nobody can see.
  if (horizontal && overlap <= 0) return null;

  const fromCentre = (fromStart + fromEnd) / 2;
  const toCentre = (toStart + toEnd) / 2;
  const misalignment = Math.abs(fromCentre - toCentre);

  return travel + (overlap > 0 ? misalignment * 0.2 : misalignment * 4 + 1000);
}

/** The nearest ancestor that actually scrolls vertically, if there is one. */
function verticalScroller(node: HTMLElement): HTMLElement | null {
  for (let element = node.parentElement; element; element = element.parentElement) {
    const overflow = getComputedStyle(element).overflowY;
    if (
      (overflow === 'auto' || overflow === 'scroll') &&
      element.scrollHeight > element.clientHeight
    ) {
      return element;
    }
  }
  return null;
}

/* Room for the focus ring, which is drawn outside the element's own box. */
const REVEAL_MARGIN = 4;

/**
 * Bring the focused thing into view — the whole thing, and near the middle.
 *
 * Two corrections to the obvious implementation, both of them things that only
 * show up on a television:
 *
 * A card's title and runtime are siblings of the focusable artwork, not part of
 * it, so scrolling the artwork into view happily leaves the metadata under the
 * fold. Anything with more to it than the part that takes focus marks its outer
 * box with `data-reveal`, and that is what gets revealed.
 *
 * And `nearest` — the browser's minimum-effort scroll — parks the focused row
 * flush against the edge it came in from, which is where things get clipped.
 * Centring instead is what a television does. But centring *unconditionally* is
 * wrong too: opening a film's page would immediately scroll its title away to
 * put the Play button in the middle. So: leave it alone while it is comfortably
 * visible, and centre it the moment it is not.
 */
function reveal(node: HTMLElement): void {
  const target = node.closest<HTMLElement>('[data-reveal]') ?? node;
  const scroller = verticalScroller(target);

  if (!scroller) {
    // Nothing scrolls vertically here, but a row still might horizontally.
    target.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
    return;
  }

  const box = target.getBoundingClientRect();
  const view = scroller.getBoundingClientRect();
  const visible = box.top - REVEAL_MARGIN >= view.top && box.bottom + REVEAL_MARGIN <= view.bottom;

  target.scrollIntoView({
    block: visible ? 'nearest' : 'center',
    inline: 'center',
    behavior: 'smooth'
  });
}

export function focus(node: HTMLElement | null): void {
  if (node === current) return;
  current?.classList.remove('is-focused');
  current = node;
  if (node) {
    node.classList.add('is-focused');
    const group = entries.get(node)?.options.group;
    if (group) groupMemory.set(group, node);
    node.focus({ preventScroll: true });
    reveal(node);
    entries.get(node)?.options.onFocus?.();
  }
  listeners.forEach((handler) => handler(current));
}

export function move(direction: Direction): boolean {
  const pool = candidates();
  if (pool.length === 0) return false;

  if (!current || !current.isConnected) {
    focusFirst();
    return true;
  }

  const from = current.getBoundingClientRect();
  let best: Entry | null = null;
  let bestScore = Infinity;

  for (const entry of pool) {
    if (entry.node === current) continue;
    const value = score(from, entry.node.getBoundingClientRect(), direction);
    if (value !== null && value < bestScore) {
      best = entry;
      bestScore = value;
    }
  }

  if (!best) return false;

  // Arriving in a new group from above or below. A group that asked for it
  // takes focus at its start rather than wherever the geometry pointed.
  const currentGroup = entries.get(current)?.options.group;
  const targetGroup = best.options.group;
  if (
    (direction === 'up' || direction === 'down') &&
    targetGroup &&
    targetGroup !== currentGroup &&
    best.options.enter === 'first'
  ) {
    const first = pool.find((entry) => entry.options.group === targetGroup);
    if (first) {
      focus(first.node);
      return true;
    }
  }

  focus(best.node);
  return true;
}

export function select(): boolean {
  if (!current) return false;
  const entry = entries.get(current);
  if (!entry?.options.onSelect) return false;
  entry.options.onSelect();
  return true;
}

/** Focus the highest-priority element, breaking ties by document order. */
export function focusFirst(): void {
  const pool = candidates();
  if (pool.length === 0) {
    focus(null);
    return;
  }
  const best = pool.reduce((a, b) =>
    (b.options.priority ?? 0) > (a.options.priority ?? 0) ? b : a
  );
  focus(best.node);
}

/**
 * Focus a specific group: its remembered element, or its first.
 *
 * `focusFirst` ranks by priority across the whole registry, which is wrong
 * whenever something is layered over something else — a modal keyboard would
 * hand focus to the screen behind it. Anything that opens or reveals a region
 * should name that region.
 */
export function focusGroup(group: string): boolean {
  const remembered = groupMemory.get(group);
  if (remembered?.isConnected && entries.has(remembered)) {
    focus(remembered);
    return true;
  }
  const first = candidates().find((entry) => entry.options.group === group);
  if (!first) return false;
  focus(first.node);
  return true;
}

export function currentFocus(): HTMLElement | null {
  return current;
}

/** Forget a group's remembered position, e.g. when its contents are replaced. */
export function resetGroup(group: string): void {
  groupMemory.delete(group);
}

const DIRECTIONS: readonly string[] = ['up', 'down', 'left', 'right'];

function isDirection(action: HostAction): action is Direction {
  return DIRECTIONS.includes(action);
}

export function handleAction(action: HostAction): boolean {
  if (isDirection(action)) return move(action);
  // The shell emits 'enter' for Return and 'select' from gamepads and CEC.
  // jellyfin-web's plugin normalises the two; nothing does that for us.
  if (action === 'select' || action === 'enter') return select();
  return false;
}

/**
 * Svelte action. `use:focusable={{ group: 'continue', onSelect: play }}`
 *
 * Registration order follows DOM order, which is what focusFirst falls back to.
 */
export function focusable(node: HTMLElement, options: FocusableOptions = {}) {
  entries.set(node, { node, options });
  if (node.tabIndex < 0) node.tabIndex = -1;

  return {
    update(next: FocusableOptions = {}) {
      const entry = entries.get(node);
      if (entry) entry.options = next;
    },
    destroy() {
      entries.delete(node);
      for (const [group, remembered] of groupMemory) {
        if (remembered === node) groupMemory.delete(group);
      }
      if (current === node) {
        current = null;
        // Do not leave the interface with nothing focused.
        queueMicrotask(() => { if (!current) focusFirst(); });
      }
    }
  };
}
