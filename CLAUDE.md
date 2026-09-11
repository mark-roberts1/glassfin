# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## What this is

A Jellyfin television client for the living room: Flutter on Linux desktop, with
[media_kit](https://pub.dev/packages/media_kit) — which is libmpv — doing playback.

It is a **rewrite of a fork**. The first version was Jellyfin Media Player with its web client
replaced: a Qt6/QtWebEngine C++ shell hosting a Svelte 5 front end, with mpv drawing video in a
layer *behind* a transparent web view. That arrangement worked, but the seam between two
independent GPU renderers sharing one window was the source of every hard bug in the project, and
eventually the Chromium side stopped launching at all on the development machine for reasons
never explained. Flutter removes the seam: video is a widget, the interface stacks on top of it,
one renderer composites both.

The old tree is at `../glassfin_old` and its history is on the same remote. It is the reference
for anything this document says was "ported" — read it there rather than guessing.

Sibling project: `../media-center`, the Bazzite TV appliance this client is built for.

## Read these two documents before building anything

They were written by reading the old codebase exhaustively, and they are expensive to regenerate:

- **[docs/ui-spec.md](docs/ui-spec.md)** — the complete interface specification. Both palettes,
  every design token with its computed pixel value, all six screens, all seven components, the
  z-index ladder, and the spatial-navigation scoring algorithm. Phase 5 builds against this file.
- **[docs/native-audit.md](docs/native-audit.md)** — everything the Qt shell did that Flutter
  does not give away free. The Jellyfin device profile, the mpv properties that were tuned the
  hard way, subtitle mapping, HDMI-CEC, input mapping constants, and refresh-rate selection.

If something in the code contradicts these documents, one of them is wrong — find out which
before changing either.

## The bar, inherited from media-center

**A solution that needs a keyboard, a terminal, or desktop-scale UI in normal use does not meet
the bar,** however well it works otherwise. Three metres, a D-pad, and a remote with about eight
usable buttons.

Practical consequences: every interactive element is reachable by directional navigation, focus
is visible at all times and never lost, hover states are decoration rather than a means of
operation, and nothing important is smaller than it would be on a phone held at arm's length.

## Scope: movies and shows, nothing else

Glassfin plays **movies and TV series stored on a Jellyfin server**. Not live TV, not music. This
is a deliberate narrowing of JMP's surface, not a backlog.

What the client owes: `Movie`, `Series`, `Season`, `Episode`, and the small set of queries around
them — resume, next up, search. Do not add feature areas back without the project owner deciding
to.

## The application's identity

Settled, and settled everywhere at once. Changing any of it moves people's config directories.

| | |
| --- | --- |
| Application ID | `org.glassfin.Glassfin` (`linux/CMakeLists.txt`) |
| Binary | `glassfin` |
| Data / config | `~/.local/share/glassfin/` |
| Desktop entry | `linux/packaging/org.glassfin.Glassfin.desktop` |
| CEC OSD name | `Glassfin` — what the television shows; libcec caps it at 13 characters |
| Icons | `assets/images/icon.svg` (+ `.png`) |

**"Jellyfin" still appears, and most of it is correct.** The server is Jellyfin, the API is
Jellyfin's, ticks are Jellyfin's unit, and the GPLv2 licence and copyright belong to upstream JMP
— we are porting GPLv2 code, so `LICENSE` stays as it is.

## Layout

```
lib/
  main.dart            entry point, window setup, root widget
  design/              tokens, theme, metrics, focus visuals  → docs/ui-spec.md §1
  nav/                 spatial focus traversal policy         → docs/ui-spec.md §5
  jellyfin/            API client, models, device profile     → docs/native-audit.md §1
  playback/            mpv configuration and orchestration    → docs/native-audit.md §2
  input/               mapping engine, gamepad, CEC client    → docs/native-audit.md §3
  settings/            preferences, persistence
  components/          Card, Row, ScreenHeader, Logo, Keyboard, Player, PlaybackMenu
  screens/             Home, Search, Library, Detail, Settings, Login
  nav/routes.dart      the route stack
  format.dart          clock and runtime strings
assets/
  inputmaps/           copied verbatim from the Qt build — same format, do not rewrite
  fonts/               Space Grotesk 400 and 500, static instances, OFL
linux/packaging/       desktop entry and appdata
docs/                  the two reference documents above
```

## Three rules that keep this coherent

In rough order of how much damage breaking them does.

1. **Input enters at exactly one place.** One router at the root, with a total split: during
   playback the transport owns the controller, otherwise navigation does. No widget adds its own
   global key listener. (The old app's `route()` in `App.svelte`; see docs/ui-spec.md §2.)
2. **If it can be focused, it is registered.** An element reachable by eye but not by the
   traversal policy is a dead end, and dead ends are the specific failure the couch bar exists to
   prevent.
3. **Nothing outside `lib/design/` names a colour or a size.** Same discipline the CSS custom
   properties enforced. A raw `Color(0xFF…)` or a magic `24.0` in a screen is a bug. Sizes quoted
   in the spec as `rem` are written as `Metrics.rem(2.6)` and `Type.rem(0.92)` so they can be read
   straight back against `docs/ui-spec.md` rather than pre-multiplied into constants nobody can
   trace.

Three components carry a `Media`/`Detail` prefix — `MediaCard`, `MediaRow`, `DetailHero` — because
Flutter already owns `Card`, `Row` and `Hero`. The spec calls them Card, Row and the hero; a file
importing both names would silently get the wrong widget.

## Spatial navigation: three behaviours that are deliberate

Flutter's default focus traversal is not good enough for a ten-foot interface. The custom policy
in `lib/nav/` reproduces the scoring from the old `nav.ts`, and three of its behaviours look like
bugs until you sit three metres away:

1. **Horizontal moves never leave the row they started on.** A candidate with zero vertical
   overlap is penalised so heavily it can never win a left/right move.
2. **Entering a horizontally scrolling row from above or below lands on its first item**, not the
   nearest column. A carousel is scrolled to a position the viewer did not choose, so the column
   they came from points at nothing they can see. **Grids and static button rows must keep the
   column** — the on-screen keyboard is the clearest case, where "first" would mean landing on
   `A` every time you pressed up from Done.
3. **Focus is never lost.** A destroyed focused node schedules a refocus rather than leaving the
   app with nothing highlighted, which from the couch is indistinguishable from a freeze.

Plus per-group focus memory, and a `reveal()` equivalent over `Scrollable.ensureVisible` that
centres an axis **only** when the target is not already comfortably visible (4px margin).

**`focusRoom`** is the space a focused card's growth needs on one side (`posterWidth × 0.045 +
8px`). A scrolling row reserves it as top padding and a card uses it as the gap to its own title.
A row that substitutes its own round number will slice the top off the focus ring — the half of
the highlight that makes it read from a sofa — and let the artwork sit on the title.

## Navigation is a stack

Keep a `List<Route>`, not a current-screen name. Detail is reachable from home, a library, and
search, and Back has to return to whichever it was. Push to go deeper, pop to go back, and `home`
resets to a single entry.

Selection rules, deliberate rather than incidental: **episodes play, films and series open their
detail screen.** An episode in Continue Watching or Next Up is unambiguous; a film has a resume
point worth showing first, and a series has no single obvious episode.

Screens are kept alive rather than disposed, so scroll position and focus survive a film.

## Playback

media_kit *is* libmpv, so every tuning decision from the old `PlayerComponent.cpp` transfers as a
raw property set through `NativePlayer.setProperty()`. **docs/native-audit.md §2 lists the ones
that were expensive to learn** — `demuxer-mkv-probe-start-time=false`, `hwdec` defaulting to
`auto-copy` rather than `auto`, the S/PDIF channel policy, the subtitle scale mapping. Do not
"clean these up".

### Changing tracks is not one operation

`setAudioTrack` / `setSubtitleTrack` only work when mpv actually holds the track. Whether it does
depends on what the server decided:

| Situation | What happens | Cost |
| --- | --- | --- |
| Direct play / direct stream | mpv switches the track in place | Instant |
| Transcoding, audio change | Re-request `PlaybackInfo` with `AudioStreamIndex`, reload at position | A pause |
| Subtitle with `DeliveryMethod: 'Encode'` | Burned into the picture; only the server can change it | A pause |
| Subtitle with `DeliveryMethod: 'External'` | Sideloaded into mpv from its URL | Instant |
| Subtitle with `DeliveryMethod: 'Embed'` | mpv switches in place | Instant |

Audio switching is keyed on the *source-level* `TranscodingUrl`; subtitle switching is keyed on
the *stream-level* `DeliveryMethod`. That asymmetry is correct. A client that only ever calls
`setAudioTrack` looks broken on transcoded content — the menu closes and nothing changes.

**External subtitle URLs must be made absolute.** The server returns them server-relative, and
mpv is not a browser — it has no page to resolve them against.

**Preferences resolve to indices *before* the first load, not after it.** Applying a subtitle
preference afterwards would start the film and then restart it visibly, which is why the track
choice type is `int | null | 'auto'` and `'auto'` is distinct from `null`. When auto-resolving
against a transcode, a second `PlaybackInfo` request happens before the first frame.

## Settings are split, on purpose

- **Behaviour is Glassfin's** — preferred audio and subtitle language, subtitle mode, intro and
  outro skipping, theme. Persisted by us, applied before the first frame.
- **Subtitle appearance is mpv's** — size, font, colour, border, background, placement. That is
  libass drawing pixels. These are stored as our settings but *applied* as mpv properties; see
  the mapping in docs/native-audit.md §3.

If a preference could be honoured by either side, it belongs to whichever one actually acts on it.

Intro and outro markers come from `/MediaSegments/{itemId}` — native in Jellyfin 10.10+, the
Intro Skipper plugin before that. A server with neither returns nothing, which is a normal
outcome and never an error.

## The brand is a file, not a set of hex codes

Colour, type and the mark come from the Glassfin style guide; `docs/ui-spec.md` §1.3–1.4
transcribes it. `lib/design/tokens.dart` is the only file that names a colour.

Three layers, and it is worth understanding before adding one:

- **Brand palette** — Ink, Paper, Lead, Silver, Trail, Accent, plus the greys. **Never referenced
  by a widget.**
- **Role tokens** — `ground`, `raised`, `edge`, `ink`, `inkDim`, `inkFaint`, `accent`,
  `accentText`, `danger`, `focusRing`, the `primary*` trio, and the shadows. Redefined for light.
  **This is what widgets use.**
- **`over*`** — for anything that floats over video or over artwork.

Type is Space Grotesk, 400 and 500. **500 is the heaviest weight that exists.** A
`FontWeight.w600` will render as synthesised fake bold, which on a television looks like a
rendering fault.

The logo is a `CustomPainter`. Two things about it are load-bearing: the facets read theme-defined
fin colours, and the cuts between them are painted in the *background* colour rather than an ink —
so on anything but the page ground the caller must pass a cut colour. Below 32px it draws a flat
silhouette instead.

## Light and dark, and the one thing that has neither

Dark is the default, not system. A television in a dark room is the case to be right about, and
most shells have no palette preference worth consulting.

**The picture is not themeable.** The transport, the track menu, the skip prompt, the wash under
a library tile's name, the progress bar on a poster and the watched tick are dark in both themes,
because they are read against a photograph and a photograph has no light mode. Those use the
`over*` tokens. Getting this wrong produces something that looks fine in review and is unreadable
the moment a film starts.

Two contrast notes, so they are not "fixed" back:

- Light `inkFaint` is the guide's Mist darkened about 14%. Mist itself lands at 3.2:1 on paper,
  fine on a printed sheet and not fine as hint text seen from three metres.
- Light `accentText` is a deeper gold than Lead. Lead manages 2.8:1 on paper; gold on white is
  simply a harder problem than gold on black.

## Text entry is now ordinary — and that is a change

The Qt shell's `EventFilter` returned `true` for every key press, so a physical keyboard produced
no DOM events at all, case was destroyed by the input mapping, and one key could emit several
actions. The entire old `textentry.svelte.ts` existed to work around that.

**None of it applies here.** Flutter receives real `KeyEvent`s with real case. Use ordinary text
fields. The on-screen keyboard still exists — it is how a D-pad or a remote types — and it writes
into the same controller a physical keyboard does, so a DualShock's keypad can be used mid-word.
Its shift is **sticky**, not momentary.

Generate the same canonical strings (`"Ctrl+Shift+F"`) that `assets/inputmaps/keyboard.json`
already expects, so that file works unchanged. `canonicalKeyName` in `lib/input/keyboard.dart` is
where that happens, and it is fussier than it looks: the file is written in **Qt's** vocabulary, so
`Left` not `Arrow Left`, `Esc` not `Escape`, `PgUp` not `Page Up`, `Space` is a *named key* rather
than the character it produces, and modifiers come in Qt's order — **Meta, Ctrl, Alt, Shift**. Any
other order produces a string that matches nothing and a shortcut that silently stops working.

## The input maps are a contract

`assets/inputmaps/*.json` came over from the Qt build byte for byte and keep working unchanged.
Everything that reads them is in `lib/input/`: `input_map.dart` (what a key means),
`pipeline.dart` (when it fires — the short/long split and autorepeat), `engine.dart` (binding the
two to the router), `gamepad.dart` (SDL2 by FFI).

Three consequences worth knowing before editing any of it:

- **A key can mean several things at once.** Every pattern that matches contributes, so `P` yields
  both `"P"` and `"play_pause"`. That is the design, not a bug to deduplicate — a text field takes
  the character and leaves the action unused, and with no field open the action runs.
- **An action name with no case in `InputAction.fromId` is normal.** The files address a superset of
  what any one client does; the Qt interface handled about twenty names and dropped the rest. Add a
  name when there is something for it to do.
- **The tuned constants are tuned**: long press 500ms, autorepeat 650ms then 60ms, SDL axis
  hysteresis 16384 on / 10000 off. The two axis thresholds are not redundant — one threshold makes a
  resting thumbstick chatter.

`docs/native-audit.md` §3 lists the five places the engine deliberately diverges from the original,
and why each original behaviour was an accident rather than a decision.

## Build and test

```
flutter run -d linux       # develop
flutter analyze            # must be clean
flutter test               # the ported logic is pure and finally testable
flutter build linux --release
```

The old project had **zero** front-end tests, because everything interesting was tangled with the
DOM and a live shell. That excuse is gone. The track-choice helpers, the device-profile builder,
the direct-play/transcode branching and the navigation scoring are all pure functions — unit-test
them.

Target is Bazzite, packaged as a Flatpak and launched from Steam Big Picture as a non-Steam
shortcut. Development happens on Arch; `libmpv.so.2` must be present at build and run time.

## Open decisions — do not silently settle these

- **HDR.** The old device profile sets `force_transcode_dovi: true` by default (mpv renders DoVi
  profile 5 with wrong colours) and there was no HDR code at all — the app already asked the
  server to transcode HDR away. Flutter's SDR texture pipeline therefore costs nothing *today*,
  but it lowers the ceiling. Needs testing on the actual television before anything depends on it.
- **Refresh-rate switching on Wayland.** The old C++ had **no Wayland backend at all**, so this
  subsystem was already dead on Bazzite. The scoring arithmetic ports verbatim; the plumbing is
  new work either way and may be compositor-dependent. Find out early.
- **Steam Input.** Untested. Launching from Big Picture puts Steam Input between the pad and
  SDL, and it may present a virtual pad, emulate a keyboard, or double up with the raw device.
