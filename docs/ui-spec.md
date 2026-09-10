# Glassfin UI specification

The interface to rebuild, transcribed from the Svelte implementation in `glassfin_old/web/src/`.
This is the reference for the Flutter recreation: it records exact tokens, sizes, timings and
behaviours, including the reasoning behind the non-obvious ones.

Where this document and the old code disagree, the old code is right — but the old code is a
translation target, not a thing to copy structurally. Read this for *what the interface is*, not
for how Svelte expressed it.

**Three exceptions, all decided during the rebuild and all marked in place:** the focus ring
(§1.8), focus over video (§1.8a) and the primary action (§1.11). There the old code is history,
not the reference.

---

## 0. Global shape and stacking

`index.html` carries a pre-paint theme guard: it reads `localStorage['glassfin.preferences'].theme`,
resolves `'system'` via `matchMedia('(prefers-color-scheme: light)')`, and sets
`data-theme="light"` on `<html>` before the stylesheet loads. Its inline `<style>` sets
`html { background: #0b1114 }` / `html[data-theme='light'] { background: #f5f3ee }` purely as a
flash guard. **In Flutter this whole mechanism disappears** — `ThemeMode` covers it.

`App.svelte` renders, in order: the ambient backdrop, the ambient veil, one screen from the route
stack (or Login), the Player, the PlaybackMenu when open, the on-screen Keyboard when text entry
is active and the route isn't Search, the skip prompt, and the loading/error overlay.

### Z-index ladder (exact)

| Layer | z |
| --- | --- |
| ambient backdrop | 0 |
| ambient veil | 1 |
| screen | 2 |
| focused element (within a screen) | 2 |
| Player stand-in (browser only) | 12 |
| keyboard sheet backdrop | 15 |
| transport | 16 |
| playback-menu scrim | 17 |
| playback menu, menu footnote, skip prompt | 18 |
| loading / error overlay | 22 |

### Routing

A **stack**, not a current-screen name:
`{name:'home'} | {name:'search'} | {name:'settings'} | {name:'library', item} | {name:'detail', item}`.
Detail is reachable from home, a library and search, and Back must return to whichever it was.
`push` appends and refocuses; `pop` refuses to empty the stack; the `home` action replaces the
whole stack. Signing out resets it, so a deep stack isn't waiting after the next sign-in.

**Selection rule:** `Type === 'Episode'` plays immediately (from Continue Watching or Next Up
there is exactly one thing you meant); Movies and Series push a detail route (a film has a resume
point worth showing; a series has no single obvious episode).

### Input routing — the single entry point

Everything enters through one function. The playback/navigation split is total: while playing, it
returns before reaching text entry or spatial navigation, so the transport owns the controller.

```
notePadInput()                       // leave pointer mode

if playing:
    nudgeChrome()                    // any button revives the transport
    if menuOpen:  back|exit closes it; otherwise spatial nav runs INSIDE the menu; return
    if skip offered and (select|enter): take the skip; return
    if up|menu: open track menu; return
    cycle_audio / cycle_subtitles / toggle_subtitles
    play_pause|select|enter|play|pause → toggle pause
    back|stop|exit                     → stop
    seek_forward|right                 → +30s
    seek_backward|left                 → −30s
    return                           // never falls through to navigation

textEntry.handle(actions)            // text entry gets first refusal
spatial navigation (directions, select/enter)
search → push Search;  home → reset stack;  back → pop
```

Priority within playback matters: menu → skip offer → open-menu → track cycling → transport. So
`select` means "take the skip" when one is offered and "pause" otherwise. `SEEK_STEP_MS = 30_000`.

### During playback

`.playing` is set on both `<body>` and `<html>`; background drops to `rgba(0,0,0,0.004)`
(**not** exactly 0 — Chromium/Qt stops compositing an exactly-transparent layer) and
`visibility: hidden` is applied to the screen, hero, hero veil, ambient and veil. **Screens are
hidden, never unmounted**, so scroll position and focus survive a film.

*In Flutter this is all obsolete* — the video is a widget below the UI in a `Stack`, and hiding a
screen is just not painting it. Keep the "hidden, not destroyed" property so state survives.

---

## 1. Design system

### 1.1 Typography

Space Grotesk, vendored. **Only weights 400 and 500 exist** — 600+ synthesises fake bold, which
reads as a rendering fault on a television. Every "bold" in the app is 500.

```
font-family: Space Grotesk, Segoe UI, system-ui, sans-serif
font-size:      18px          (body)
font-weight:    400
line-height:    1.45
letter-spacing: -0.005em      (body)   /  -0.02em (headings)
```

Headings (`h1,h2,h3`): `margin: 0; font-weight: 500; letter-spacing: -0.02em`.

**Unit note for the port:** `<html>` font-size is never set, so `1rem = 16px`, while body text
renders at 18px. Every `rem` value below is ×16. `em` inside body is ×18.

### 1.2 Brand palette — never referenced by a component

```
--brand-ink        #0e1518      --brand-mist        #7c8a90
--brand-paper      #f5f3ee      --brand-mist-light  #8da0a8
--brand-lead       #c68331      --brand-tile        #e7e4db
--brand-silver     #7a9d8f      --brand-night       #0b1114
--brand-trail      #5697de
--brand-accent     #d5a051
```

### 1.3 Role tokens — dark (the default)

| Token | Value |
| --- | --- |
| `ground` | `#0b1114` |
| `ground-rgb` | `11 17 20` |
| `raised` | `#162026` |
| `edge` | `rgba(245,243,238,0.10)` |
| `ink` | `#f5f3ee` |
| `ink-dim` | `rgba(245,243,238,0.64)` |
| `ink-faint` | `#8da0a8` |
| `accent` | `#d5a051` |
| `accent-text` | `#d5a051` |
| `danger` | `#e0908c` |
| `focus-ring` | `#5697de` (Trail) |
| `ambient-opacity` | `0.28` |
| `veil-near` / `veil-mid` | `0.35` / `0.78` |
| `shadow-focus` | `0 18px 44px rgba(0,0,0,0.7)` |
| `shadow-lift` | `0 10px 24px rgba(0,0,0,0.6)` |
| `shadow-poster` | `0 24px 60px rgba(0,0,0,0.6)` |
| `fin-1..12` | `#f4b46d #e0be76 #cdc586 #bec998 #b4cba9 #b1cab6 #abcbbe #9dcec7 #8ed0d5 #83d0e6 #81cdf9 #95c7ff` |

### 1.4 Role tokens — light

Light is **not an inversion**: shadows get lighter and shallower, and the artwork treatments
(§1.5) don't change at all.

| Token | Value |
| --- | --- |
| `ground` | `#f5f3ee` |
| `ground-rgb` | `245 243 238` |
| `raised` | `#e7e4db` |
| `edge` | `rgba(14,21,24,0.14)` |
| `ink` | `#0e1518` |
| `ink-dim` | `rgba(14,21,24,0.66)` |
| `ink-faint` | `#6b777c` — Mist darkened ~14%; Mist itself is only 3.2:1 on paper |
| `accent` | `#c68331` (Lead, not Accent) |
| `accent-text` | `#986424` — Lead manages only 2.8:1; this is 4.5:1 |
| `danger` | `#a6323f` |
| `focus-ring` | `#3f7cbf` — Trail deepened; Trail itself is 2.75:1 on paper |
| `ambient-opacity` | `0.16` |
| `veil-near` / `veil-mid` | `0.62` / `0.90` |
| `shadow-focus` | `0 14px 32px rgba(14,21,24,0.18)` |
| `shadow-lift` | `0 8px 18px rgba(14,21,24,0.14)` |
| `shadow-poster` | `0 20px 44px rgba(14,21,24,0.22)` |
| `fin-1..12` | `#c68331 #b28e3e #9f9652 #8f9a67 #859c79 #819c87 #7a9d8f #6ba098 #59a1a7 #4ba1b9 #489ecc #5697de` |

### 1.5 The `over-*` family — theme-invariant

Anything floating over video or artwork. **A photograph has no light mode.** These values are
identical in both themes; getting this wrong looks fine in review and is unreadable the moment a
film starts.

```
over-scrim      rgba(11,17,20,0.86)      over-ink        #f5f3ee
over-panel      rgba(22,32,38,0.92)      over-ink-dim    rgba(245,243,238,0.64)
over-artwork    rgba(11,17,20,0.55)      over-ink-faint  #8da0a8
over-edge       rgba(245,243,238,0.14)   over-accent     #d5a051
                                         over-danger     #e0908c
over-on-ink     #0b1114 (Night)          over-focus-ring #5697de (Trail)
over-video-scrim rgba(0,0,0,0.92)        over-track      rgba(255,255,255,0.22)
```

`over-on-ink` is what is drawn *on* `over-ink` — the glyph inside a card's watched tick.
`over-video-scrim` is the dark end of the transport's gradient: pure black rather than Night,
because it fades into the film itself rather than into any surface of ours. `over-track` is the
unplayed part of the scrub bar, neutral white so it does not tint against the frame behind it.

Users: the transport, the track menu, the skip prompt, the loading/error overlay, the wash and
name on a Home library tile, the resume bar and watched tick on a card, the Player stand-in.

### 1.6 Geometry and motion

```
safe-x        4.5vw        →  86.4px @1920
safe-y        4vh          →  43.2px @1080
radius        10px
radius-lg     16px
ease          cubic-bezier(0.22, 0.61, 0.36, 1)
fast          180ms        (focus transform + shadow)
slow          420ms        (ambient opacity, transport fade)
poster-width  15.5vw       →  297.6px @1920  (2:3 → 446.4px tall)
still-width   26vw         →  499.2px @1920  (16:9 → 280.8px tall)
focus-scale   1.06
focus-room    poster-width × 0.045 + 8px  →  ≈21.4px @1920
```

**One duration and one curve, everywhere.**

**The `focus-room` contract.** It is half the extra *height* a focused 2:3 poster gains, plus 8px.
Viewport-relative on purpose, so it holds at 1080p and 4K. Two consumers must both honour it:

1. A horizontally scrolling row uses it as **top padding**. A scrolling box clips its own
   overflow, so without it the top of the focus ring is sliced off — and that is the half of the
   highlight that reads from a sofa.
2. A card's label uses it as **top margin**, so a focused card lifts off its own title instead of
   sitting on it.

### 1.7 Global element rules

`box-sizing: border-box` everywhere. `html, body { height:100%; margin:0; overflow:hidden }` — the
interface pans; **the document never scrolls**. `user-select: none`. `cursor: none` until a real
mouse movement. Browser focus rings suppressed (`:focus { outline: none }`) — focus is drawn by
the app, not the platform. Every scroller hides its scrollbar.

### 1.8 Focus styling

Default:

```
transition: transform 180ms ease, box-shadow 180ms ease
focused:    transform: scale(1.06)
            box-shadow: 0 0 0 3px <focus-ring>, <shadow-focus>
            z-index: 2
```

**Scale is the primary signal** — it survives photography off a screen, colour-blindness and bad
TV calibration. The 3px ring is support.

**The ring is `focus-ring` (Trail), not the page's ink — a second deliberate departure from the
Qt build**, alongside §1.11. Trail is the one brand colour with no other job in the interface,
which is exactly what a system signal wants: focus stops competing with content colour and cannot
be mistaken for part of the artwork it surrounds. Light uses a deepened Trail because `#5697de`
manages only 2.75:1 on paper, under the 3:1 a non-text indicator needs.

Two notes on drawing it. It is an **outline, not a filled rect behind the child** — a spread
shadow paints straight through a transparent `.quiet` button and hides its label. And it is drawn
*outside* the element's bounds, so a container that clips (a scrolling row, a `Wrap` in a narrow
pane) must reserve `focus-room` or 3px+1 of padding for it.

Per-component overrides:

| Where | Override |
| --- | --- |
| Card artwork | default (1.06 + ring) |
| Home pill / library tile | pill inverts to ink background; both keep the scale |
| ScreenHeader Back | inverts to ink background, keeps the scale |
| Settings rows, Library button, Detail buttons, Login buttons | **ring only, no scale** (scale blurs text at that size) |
| Keyboard keys | `scale(1.1)` + ring + `shadow-lift` — keys are small, so they scale *more* |
| Transport icon controls | **`scale(1.1)` + an `over-highlight` circle, no ring** (§1.8a) |
| Scrub bar | **no ring, no scale** — the bar thickens 5→8px and its head grows 14→18px |
| PlaybackMenu / settings rows, skip prompt | **no ring, no scale** — the row fills with `over-highlight` |

#### 1.8a Nothing over the film takes a ring — a third departure

`over-highlight` is `rgba(245,243,238,0.18)`.

A rectangle drawn around a glyph is a page idiom. On a photograph it stops reading as a highlight
and starts reading as a box that was always there — and with a control row of eight of them, the
transport looked ruled rather than focused. The reference client draws no rings at all: its
controls grow under the pointer and light a circle behind themselves.

So over the film, **scale carries focus** — which §1.8 already calls the primary signal — with the
wash as support. It is safe at 0.18 alpha only because the transport lays a near-black gradient
over the picture first, so the backdrop is dark whatever the film is doing. **Do not reuse
`over-highlight` on anything drawn straight onto artwork**, where there is no such guarantee.

Two shapes cannot scale: the scrub bar and the menu rows are full-width, and growing them shoves
their neighbours around. They thicken and light their own surface instead.

The panel hairlines went with the rings, for the same reason — every track row carrying a 1px
border turned the menu into a stack of boxes. The `over-panel` fill gives the same shape with none
of the ruling. The `over-edge` chips on the track menu's badges are still there.

### 1.9 The ambient backdrop

```
position: fixed; inset: 0; z: 0; pointer-events: none
background-size: cover; background-position: center top
opacity: 0  →  <ambient-opacity> when visible   (0.28 dark / 0.16 light)
transform: scale(1.08)
filter: blur(28px) saturate(1.15)
transition: opacity 420ms ease
```

**Only the opacity cross-fades; the image swaps instantly underneath.** Shown when there is an
ambient image, nothing is playing, and the route isn't Detail (which has its own hero).

The veil is **always present**, even with no ambient image — it is what tints the left edge and
bottom of every screen:

```
linear-gradient(to bottom, ground/0.55 0%, ground/0.20 35%, ground/1 92%),
linear-gradient(to right,  ground/1 0%,    ground/0 45%)
```

### 1.10 Reduced motion

Honoured for: ambient fade, scroll behaviour, transport fade, caret blink.
**Focus scale is deliberately kept** — it is not decoration.

### 1.11 The primary action — a departure from the Qt build

The rest of this document transcribes what the old interface did. This does not: the primary
button was **changed on purpose** during the Flutter rebuild, so if the two disagree, this section
is right and the old CSS is history.

| | |
| --- | --- |
| `primary-fill` | `raised` — the same surface as any other button |
| `primary-ink` | `accent-text` |
| `primary-border` | `accent-text`, 1px |
| Weight | 500 |

Derived from the role tokens rather than stored per theme, so the rule and the label cannot drift
apart from the gold they are made of.

The old app's `.primary { background: var(--ink) }` filled the largest control on the screen with
the brightest colour in the palette, which in a dark room makes it the brightest *object* in the
room. The style guide never asked for it — it is an identity guide, and carries no button
specification at all — so there was nothing to preserve. A gold rule and a gold label carry the
same "this is what you came here to do" with nothing on screen exceeding the brightness of body
text. Four treatments (Paper, gold fill, dimmed paper, outlined gold) were trialled on the actual
panel behind a debug key; outlined gold won and the trial scaffolding was deleted.

`accent-text` rather than `accent` for the rule: in dark they are the same colour already, and in
light the deeper gold takes the boundary against `raised` from 2.5:1 to 4.5:1.

---

## 2. Spatial navigation

### 2.1 Registration

Every focusable registers with options: `group` (items sharing a group are a row or grid, and the
group remembers its last focus), `enter` (`'first' | 'nearest'`, default nearest), `onSelect`,
`onFocus` (drives the ambient backdrop), `disabled` (skipped without unregistering), and
`priority` (weight for "focus something sensible", ties broken by document order).

### 2.2 Directional scoring

For a move in some direction, each candidate scores:

1. `travel` = distance along the direction of travel. If `travel < -1`, reject — the 1px tolerance
   forgives sub-pixel layout and ragged row heights.
2. `overlap` = cross-axis overlap between the two boxes.
3. **If the move is horizontal and `overlap <= 0`, reject.** This is the "left/right stay on the
   line you started on" rule — you cannot fall off the end of a row into the next one.
4. `misalignment` = distance between cross-axis centres.
5. `score = travel + (overlap > 0 ? misalignment × 0.2 : misalignment × 4 + 1000)`

Lowest wins. Travel dominates; cross-axis misalignment is penalised gently; anything with no
overlap at all (vertical moves only) is pushed past a +1000 barrier.

### 2.3 Group entry

On a vertical move into a *different* group whose `enter` is `'first'`, focus that group's **first**
registered element rather than the geometric winner.

`enter: 'first'` is set on **horizontally scrolling rows and nowhere else.** A carousel is scrolled
to a position the viewer did not choose, so the column they came from points at nothing they can
see. Grids and static button rows keep the column — the on-screen keyboard is the clearest case:
`'first'` there would land on `A` every time you pressed Up from Done.

### 2.4 Reveal (auto-scroll)

`REVEAL_MARGIN = 4px` — room for the ring, which is drawn outside the box.

1. Resolve the target to the nearest ancestor marked `data-reveal`, falling back to the node
   itself. **A card's title and runtime are siblings of the focusable artwork**, so scrolling only
   the artwork leaves the metadata under the fold. Anything where the focusable is smaller than
   the thing the viewer is actually choosing marks its outer box.
2. Find the nearest scrollable ancestor per axis.
3. Per axis: "visible" means the box sits inside the viewport with 4px to spare. **Centre an axis
   only when it isn't already comfortably visible; otherwise leave it alone.**

The reasoning: `nearest` alone parks the focused row flush against the edge it came in from, which
is where things get clipped. Centring unconditionally would scroll a film's title away to centre
the Play button, and would slam a fully-visible carousel to centre for every card a mouse crosses.

Reveal is **on** for pad moves (they step one card at a time and want the row recentring) and
**off** for hover and click — a trackpad already scrolls at the viewer's pace, and auto-centring
under a moving cursor reads as the row dodging the cursor.

### 2.5 Focus is never lost

When a focused element is destroyed, clear it and schedule "focus something sensible" on the next
microtask. An interface with nothing focused is a dead end, and dead ends are the specific failure
the couch bar exists to prevent.

### 2.6 Pointer vs pad mode

Two modes, default **pad** (a TV with no mouse never shows a cursor). Pointer mode shows the
cursor and enables hover-to-focus. Any semantic action switches back to pad mode.

A `mousemove` listener switches to pointer mode **only on a genuinely changed position** — a
stationary cursor over content that spatial navigation scrolls underneath must not knock a
controller session into pointer mode.

### 2.7 Group inventory

| Group | Where | `enter` |
| --- | --- | --- |
| `chrome` | Home Search/Settings pills, ScreenHeader Back | nearest |
| `resume`, `next-up`, `latest-<libId>` | Home shelves | **first** |
| `libraries` | Home library tiles | **first** |
| `search-results` | Search grid | nearest |
| `osk` / `osk-controls` | Keyboard keys / Space-Delete-Clear-Done | nearest |
| `login` | Login buttons | nearest |
| `settings` | Settings rows | nearest |
| `library` / `library-more` | Library grid / Show more | nearest |
| `detail-actions` | Play, Start from the beginning (Play has priority 2) | nearest |
| `seasons` / `episodes` | Detail season pills / episode cards | nearest |
| `menu-audio` / `menu-subtitles` | PlaybackMenu columns | nearest |

Groups whose contents are replaced reset their memory: Detail on season change, Keyboard on mount,
PlaybackMenu on mount.

**Anything that opens or reveals a region should focus that region by name**, because a generic
"focus first" would reach past a modal to the screen behind it.

---

## 3. Screens

### 3.1 Home

Header: the wordmark logo at size 34, and two pills (Search, Settings) in group `chrome`.
Then shelves in order: **Continue Watching** (still shape), **Next Up** (still), a **Libraries**
row of tiles, then **Recently Added in {Library}** (poster shape) per library.

Data: `resume` (limit 12), `nextUp` (16), `libraries` filtered to `movies`/`tvshows`, then
`latest(libraryId)` (20) per library in parallel, dropping empty ones.

**Focus latch:** claim focus once, the first time any content arrives. Doing it on every change
would drag focus back to the top as later shelves stream in.

Layout: `padding-top/bottom: safe-y`; header `padding: 0 safe-x`, `margin-bottom: 2rem`.
Shelf `margin-bottom: 2.6rem`. Shelf headings are `1.05rem`, weight 500, `ink-dim`, with
`margin-left: safe-x` — so the heading aligns with the first card while the track is full-bleed.

Pills: `0.95rem`, `raised` on a `1px edge` border, fully rounded, `padding: .5rem 1.3rem`.
Focused: inverted to ink background, plus the default scale and ring.

Library tiles: `width: poster-width × 1.6` (≈476px), **16:9** — wider *and* shorter than a poster
on purpose, because a library is a place, not a title. `radius`, `1px edge`, cover image from
`Primary` falling back to `Backdrop` at 640px. A veil
(`linear-gradient(to top, rgba(11,17,20,0.85) 12%, rgba(11,17,20,0.15) 70%)`, **hardcoded dark in
both themes**) carries the name at `1.05rem`/500 in `over-ink`, positioned `left: 1rem; bottom: .85rem`.

### 3.2 Search — the one two-pane screen

Grid: `minmax(340px, 32%)` for the keyboard pane and `1fr` for results, `gap: 3.5rem`, with a
`1px edge` vertical rule between them and 3.5rem gutters either side. Without the rule the
keyboard and the results read as one thing.

The keyboard is **inline here**, not a modal sheet. The field is **persistent**: Done means "I'm
done typing, move to the results" (focus the results group) rather than closing.

Debounce 350ms, minimum term 2 characters, limit 40, `includeItemTypes: Movie,Series`. A
generation counter discards responses that land after a newer query.

Results grid: `repeat(auto-fill, minmax(poster-width, 1fr))`, `gap: 1.8rem 1.4rem`. Its padding
exists purely so focused cards don't clip against the divider and the window edge.

States: "Searching…" / "Type to search your films and series." / `Nothing matched “{term}”.`
(curly quotes).

Teardown closes the field **without** firing cancel — the navigation has already moved on, and
cancel would pop it again.

### 3.3 Settings

Every row is a button that **cycles** to the next option on select, wrapping. No pickers, no
sub-screens: left/right are already spoken for by spatial movement, and the lists are short.

Sections:

1. **Appearance** — Theme (`Dark` / `Light` / `Follow the system`), placed first because it's the
   one setting whose effect you can see while making it. Then a static, non-focusable row showing
   the wordmark at size 36, which sets `--logo-cut` to the row colour (see §4.4).
2. **Playback** — Preferred audio language; Subtitles (`Off` / `Forced only` / `On, preferred
   language`); Preferred subtitle language, **disabled and dimmed to 0.45 opacity when subtitles
   are off**.
3. **Skipping** — Intros and Credits, each `Off` / `Show a button` / `Skip automatically`, with a
   note: "Uses the markers your server provides. Jellyfin 10.10 and later supply these natively;
   earlier versions need the Intro Skipper plugin. With neither, nothing is skipped."
4. **Subtitle appearance** — note: "Drawn by mpv, so these are the shell's own settings rather
   than Glassfin's. They apply to every video, and survive a restart." Size, colour, outline,
   background, placement.
5. **Account** — a static "Signed in" row, a `danger`-coloured Sign out, and Reset preferences.

Rows: full width, `raised` on `1px edge`, `radius`, `padding: .85rem 1.1rem`, name left and value
right in `ink-dim`, baseline-aligned. Focus is **ring only, no scale**. Sections `max-width: 900px`.

### 3.4 Library

Paging: 60 per page, sorted by `SortName` ascending, `Series` or `Movie` by collection type.
A "Show more ({n} of {total})" button in its own group. Failures keep the existing items so the
button remains for a retry.

Grid: `repeat(auto-fill, minmax(poster-width, 1fr))`, `gap: 2rem 1.4rem`. A count line above
("{total} series" / "{total} films") in `ink-dim` at `0.9rem`.

### 3.5 Detail — the richest screen

A fixed **hero**: the backdrop at `62vh`, `background-position: center 18%`, veiled by two
gradients that *do* vary by theme:

```
linear-gradient(to bottom, ground/<veil-near> 0%, ground/<veil-mid> 45%, ground/1 72%),
linear-gradient(to right,  ground/1 5%, ground/0.1 70%)
```

Masthead: poster (`17vw`, max 260px, `radius-lg`, `shadow-poster`) beside the facts, bottom-aligned,
`gap: 2.4rem`.

Facts, in order: title (`clamp(2rem, 3.4vw, 3.2rem)`, `line-height 1.1`); italic tagline in
`ink-dim`; a meta line of year · runtime · rating chip · ★rating · up to 3 genres · first studio;
media badges; a 4-line-clamped overview in `ink-dim`; crew (Directors then Writers, 3 names each);
and the actions.

Badges: video badges are solid inverted chips (`ink` background, `ground` text, `0.78rem`/500,
`letter-spacing .03em`); audio badges and the subtitle list are "quiet" — transparent with a
`1px edge` border and `ink-dim` text.

Actions: a primary Play (outlined gold, weight 500 — see §1.11) and, for non-Series with a resume
point over 10s,
"Start from the beginning" — which zeroes the resume point in a *copy* of the item rather than
passing a start-position argument. Play on a Series plays the next-up episode, falling back to the
first. The Play button carries priority 2.

Cast: up to 12 actors, `repeat(auto-fill, minmax(150px, 1fr))`, each an 84px circular face
(cover-fitted, or a first-initial fallback at `1.6rem` in `ink-faint`) above name (`0.9rem`/500)
and role (`0.84rem`, `ink-faint`), both single-line ellipsised. **Not focusable** — there is no
person screen.

Series: season pills (shown only when there's more than one), the current one outlined and
coloured in `accent-text`; then episodes as still-shaped cards in a
`repeat(auto-fill, minmax(still-width, 1fr))` grid.

### 3.6 Login

Four stages in one centred panel of `min(520px, 74vw)`, with the wordmark at size **64** — the
only place the mark is large enough to show its facets properly.

1. **address** — "Where does your Jellyfin server live?", a field button (placeholder
   `nas.local:8096`), and a Continue button once an address exists. Committing checks the server.
2. **choose** (only when Quick Connect is available) — "Use Quick Connect", "Sign in with a
   password", "Change server".
3. **quick** — "Open Jellyfin on your phone or computer and enter this code.", then the code at
   **`3.4rem`, weight 500, `letter-spacing: .35em`, `text-indent: .35em`** (compensating the
   trailing letter-space so it optically centres). Polls every 3000ms.
4. **password** — username and password fields (password shown as bullets), Sign in, and Back.

Buttons are left-aligned text rows in `raised`; `.primary` is outlined gold and centred (§1.11);
`.quiet` is transparent in `ink-dim`. Focus is **ring only, no scale**. Errors in `danger` at `0.9rem` with
`role="alert"`. Focus is claimed on mount and after every stage transition; the first field or
action in each stage carries priority 1.

---

## 4. Components

### 4.1 Card

Poster or still shape. Poster art comes from `Primary` at 480px; still art from `Thumb` →
`Backdrop` → `Primary` at 720px.

- **Title** — the series name for an episode, otherwise the item name.
- **Caption** — for an episode, `S{season}:E{episode} · {name}` (code omitted if either index is
  missing). For a series, `{year}–present` when continuing, `{year}–{endYear}` when ended and
  different, else the year. For anything else, the year. **Never a season count** — `ChildCount`
  means different things on different endpoints, so any single reading is wrong somewhere.
- **Third line** — runtime in minutes, stills only.

Progress: `PlayedPercentage`, else position/runtime. A 4px bar in `over-artwork` with an
`over-accent` fill renders when progress is between 1 and 99; otherwise a watched item gets a
26px circular tick, `brand-night` on `over-ink`. **Both are fixed in either theme**, so a watched
tick doesn't read as two different states across a library.

Structure: the outer box carries `data-reveal`; the artwork is the focus target; the label sits
below with `margin-top: focus-room`. Artwork is `radius`, `1px edge`, `raised` background,
2:3 or 16:9. Missing images fall back to a centred title in `ink-faint` at `0.85rem`.
Title `0.92rem`/500, caption `0.82rem` in `ink-dim`, both single-line ellipsised.

### 4.2 Row

A heading (`1.05rem`/500, `ink-dim`, indented by `safe-x`) above a horizontal track:
`gap: 1.1rem`, `padding: focus-room safe-x .75rem`, `overflow-x: auto`, `overflow-y: visible`,
smooth scrolling. Renders nothing when empty. Cards always use `enter: 'first'`.

**Two load-bearing details:** the safe-area padding is on the *track*, not the page, so the first
card can scroll flush to the frame edge; and the top padding is `focus-room` rather than a round
number, because a scrolling box clips its own overflow.

### 4.3 ScreenHeader

A pill-shaped Back button (group `chrome`) and a title at `1.35rem`. The chevron is a literal `‹`
character, not an icon, at `1.25em`; the button's padding is asymmetric
(`.5rem 1.2rem .5rem .95rem`) because the chevron eats the left space.

### 4.4 Logo

Artboard `viewBox="10 14 156 106"`; width is `size × 156/106`.

At **≥32px** the faceted mark renders: 12 paths filled `fin-1..12`, wrapped in a vertical-gradient
mask (stops: 1 at 0, 0.82 at 0.58, 0.2 at 1) so the tail dissolves into the surface; then 13 "cuts"
stroked at 2.1px with round caps; then a hairline silhouette outline in `ink` at 32% opacity.

Below 32px it is a **flat one-ink silhouette** with the same 13 cuts at 2.2px. The style guide is
explicit that the flat silhouette is the small-size mark, not a fallback.

**The cuts are painted in the background colour — they are gaps, not lines.** On anything other
than the page ground the caller must override the cut colour (Settings does, to the row colour).

Wordmark: the word "glassfin" (lowercase in the content, not via text-transform) at `size × 0.42`,
weight 500, `letter-spacing -0.02em`, in `ink`, with a lockup gap of `size × 0.16`.

Sizes in use: 34 (Home), 36 (Settings), 64 (Login).

Path data lives in `glassfin_old/web/src/components/Logo.svelte` (the `FACETS`, `CUTS` and
`SILHOUETTE` arrays) — **transcribe verbatim**.

### 4.5 Keyboard

A **6-column grid**, not an alphabet strip: a strip is 25 presses to reach Z on a D-pad, while
6 columns keeps the worst case to about 7 presses each way.

```
letters:  A B C D E F / G H I J K L / M N O P Q R / S T U V W X / Y Z
symbols:  0 1 2 3 4 5 / 6 7 8 9 ! @ / # $ % ^ & * / ( ) - _ = + /
          [ ] { } ; : / ' " , . < > / / ? ~ ` \ |
```

**Shift is sticky, not momentary** — a D-pad has no second hand. Letters type lowercase unless
shift is on; symbols are unaffected; key faces show the character they will actually type.
Shift / `123` / `ABC` are wide keys spanning two columns.

Controls below: Space (wide), Delete, Clear, Done (primary).

**The caret rule.** The caret goes *before* the placeholder and *after* typed text. With a trailing
caret, `nas.local:8096` reads as already-typed text the next key will extend — when in fact the
next key replaces it. The caret is 2px wide, `1.15em` tall, in `accent-text`, blinking on a
**hard `steps(1)` 1.1s cycle**, not a fade.

The entry field is `width: 100%; max-width: 640px` specifically because Search embeds it in a pane
far narrower than 640px. Value text at `1.4rem` in a `raised` box.

Keys focus at `scale(1.1)`. **The active shift key is the only place `accent` is used as a fill**
in the entire application.

On mount, reset the group's memory and focus the **keys**, not Done, so the first press types.

A hint line: "A keyboard works here too — type straight into the field."

### 4.6 Player transport

**Rewritten in the Flutter build, at the project owner's direction, to match the player in
Jellyfin Media Player.** What is described here is the current design; the Svelte transport it
replaced was a title, a scrub bar and a line of keyboard hints, and is gone.

The reference is mouse-driven and this one is not, so the layout and control set are taken from
it while the scale and the input model are not: glyphs are `1.9rem` (play/pause `×1.25`) rather
than the reference's ~24px, and **every control is registered for directional navigation**.
Nothing is reachable only by pointer.

Fades over 420ms. **Chrome timeout is 4000ms**; any button revives it, mouse movement revives it,
and pausing shows it and cancels the timer entirely so it stays up while paused.

**Top bar** — over a downward `over-video-scrim` gradient: a back button (group `transport-top`),
then one line, `{title} — S{n}:E{n} · {episode}`, at `1.35rem`. The reference stacks nothing; the
series carries the episode on the same line.

**Scrubber** — elapsed (tabular numerals) · the track · remaining with a **minus sign U+2212**.
A 5px rounded track in `over-track` with an `over-ink` fill and a 14px circular head ("the head is
what the eye tracks while seeking"). It is **focusable, in its own group `transport-scrub`**, and
click-and-drag seeks.

**Control row** (group `transport`): previous episode, back 30s, play/pause, forward 30s, next
episode, then the wall-clock finish — `Ends at 11:11 PM`, which answers the question actually
being asked, where "1:10:57 remaining" needs arithmetic against a clock nobody is looking at.
Right-aligned: subtitles (lit `over-accent` when a track is on), volume, settings, fullscreen.

Previous and Next step through the season's episodes and **dim rather than disappear** on a film,
because a control that comes and goes moves everything beside it. Volume steps on select and wraps
at 100 — a drag-only slider would be unreachable from a remote.

**Left and right seek, and that survives the row being focusable.** The scrubber is deliberately
not in the `transport` group: the router hands the directions to navigation only when focus is on
an actual button, so the scrubber behaves like the slider it resembles while the row behaves like
a toolbar. Focus lands on the scrubber whenever the chrome appears, so the default gesture is
unchanged. With the chrome down, `up` still opens the track menu.

**Settings popover** (group `player-settings`) — anchored bottom-right over a dimmed picture, rows
lighting on focus as the reference lights on hover, each cycling on select: Aspect Ratio
(`Auto`/`Cover`/`Fill`, mapped to mpv's `keepaspect` and `panscan` — mpv has no single fit
switch), Playback Speed, Repeat Mode (mpv's `loop-file`), and Playback Info.

Playback Info reports **delivery first** — direct play, direct stream (remuxed), or transcoding —
which is the line that explains a stutter or a wrong-looking picture.

Deliberately absent: **favourites** (the heart in the reference; `CLAUDE.md` records favourites as
not ported) and **Quality**, which caps the streaming bitrate and therefore needs a fresh
`PlaybackInfo` and a reload — that belongs with the device profile, not with a menu.

Time format: `h:mm:ss` above an hour, `m:ss` below.

*The Svelte build also had a browser stand-in panel for when no mpv was present. In Flutter there
is always a real player, so it is gone.*

### 4.7 PlaybackMenu

A scrim in `over-scrim`, and a two-column panel (Audio, Subtitles) anchored above the transport,
`max-height: 58vh`. Subtitles always has an "Off" row first. **Entirely `over-*` coloured.**

Each row: a tick column of fixed `1ch` width in `over-accent` (empty when not current, so the
label column never shifts), the label, then badges. The current row's label is weight 500.

Label text prefers the server's own `DisplayTitle` ("English - AAC - 5.1" beats anything assembled
locally), falling back to language name + codec joined with ` · `. Badges: `Default`, `Forced`,
and `Burned in` for `DeliveryMethod === 'Encode'`.

A footnote below: "Changing a track the server is transcoding reloads the stream and takes a
moment."

On mount, reset both groups and focus Audio, falling back to Subtitles.

---

## 5. Things worth calling out for a faithful rebuild

1. **Two different backdrop treatments.** Ambient (blurred, dim, behind everything, opacity
   cross-fading over 420ms) on Home/Search/Library; hero (sharp, 62vh, two veil gradients tuned
   per theme) on Detail. They are not the same widget.
2. **Focus is scale plus a ring in the page's ink** — 1.06 for artwork and pills, 1.1 for keyboard
   keys, none at all for full-width rows and text buttons.
3. **`focus-room` is reserved space** in two places at once. Get it wrong and either the ring
   clips or the artwork lands on the title.
4. **Carousels:** left/right never leave the row; up/down into a row lands on card 1; reveal
   centres an axis only when the target isn't already comfortably visible.
5. **The picture is not themeable.** Everything over video or artwork uses `over-*` and stays dark
   in light mode.
6. **Type discipline:** Space Grotesk only, 400 and 500 only, nothing heavier.
7. **No cursor, no selection, no scrollbars, no document scroll** — until a real mouse moves.
8. **Gold appears as a fill exactly once** — the active shift key. Everywhere else it is text
   (`accent-text`: the caret, the current season pill) or an over-video accent (card progress
   fill, menu tick).

---

## 6. Computed pixel values at 1920×1080

| Token | Computed |
| --- | --- |
| `safe-x` | 86.4px |
| `safe-y` | 43.2px |
| `poster-width` | 297.6px (→ 446.4px tall at 2:3) |
| `still-width` | 499.2px (→ 280.8px tall at 16:9) |
| Home library tile | 476.2 × 267.8px |
| `focus-room` | ≈21.4px |
| Detail poster | 260px (17vw, capped) |
| Detail hero | 669.6px (62vh) |
| PlaybackMenu max height | 626.4px (58vh) |
| 1rem | 16px (body text is 18px) |
