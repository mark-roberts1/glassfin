# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## What this is

A Jellyfin television client, forked from Jellyfin Media Player. The fork exists to replace the
interface, not the player. See [Idea.md](Idea.md) for the brief and [README.md](README.md) for
the layer breakdown.

Sibling project: [../media-center](../media-center), the Bazzite TV appliance this client is
being built for. Its `steps/pillar-jellyfin.md` is the requirement Glassfin answers.

## This is a fork, and the history is upstream's

`upstream` → `jellyfin/jellyfin-media-player`. There is no `origin` yet; add one when a
repository exists to push to.

Consequences that matter when editing:

- **Touching `src/` costs merge pain forever.** Every C++ change is a change you rebase against
  upstream for the life of the project. Do it when the shell genuinely cannot do what the UI
  needs — HDR, display modes, input — and not to save an afternoon in the web layer.
- **Upstream's `README.md` was replaced** by Glassfin's. It is in the git history if needed.
- **Branch `libmpv-vulkan-gpu-next-wayland-hdr`** exists upstream and is directly relevant to HDR
  under Bazzite's Wayland session. Read it before writing any HDR code.
- The project is **GPLv2**. Anything vendored into the front end has to be compatible.

## The bar, inherited from media-center

**A solution that needs a keyboard, a terminal, or desktop-scale UI in normal use does not meet
the bar,** however well it works otherwise. Three metres, a D-pad, and a remote with about eight
usable buttons.

Practical consequences: every interactive element is reachable by directional navigation, focus
is visible at all times and never lost, hover states are decoration rather than a means of
operation, and nothing important is smaller than it would be on a phone held at arm's length.

## Where the seam is, and how the front end is served

Upstream JMP has no web client of its own and never did. It loads a server-picker page from
`qrc:`, and that page navigates the webview at `http://your-server/web/` — so the interface is
**the Jellyfin server's own copy of jellyfin-web**, fetched at run time. That is the thing
Glassfin replaces, and replacing it means having somewhere else for the interface to come from.

The chain, end to end:

1. `CMakeModules/WebClientConfiguration.cmake` builds `web/` with npm (or takes a prebuilt
   `-DWEB_CLIENT_DIST`) and defines the `web_client` target.
2. `CMakeModules/GenerateQtResources.cmake` bakes `web/dist` into the binary under `/glassfin`.
3. `src/ui/GlassfinScheme.cpp` serves `:/glassfin/…` on the `glassfin://app/` URL scheme.
4. `SettingsComponent::getWebClientUrl()` returns `GLASSFIN_URL` for the `bundled` setting.

**It is a custom scheme rather than `qrc:` for one specific reason.** A `qrc:` URL has no host,
so Chromium gives the page an opaque origin, and an opaque origin has no Web Storage —
`localStorage` throws, which here means no saved server, no saved sign-in, no saved preferences.
`glassfin://app/` is a real origin, registered as a secure scheme so it is also a trustworthy
context. If you ever find yourself "simplifying" this back to `qrc:///glassfin/index.html`, that
is what breaks.

Point `path/startupurl_desktop` at `http://localhost:5180` to run `npm run dev` against real mpv.

`native/nativeshell.js` is injected into whatever loads there, and is the only file left in
`native/`. It creates `window.api` over QWebChannel and owns `getDeviceProfile()`. Its plugin
registration and its settings modal are dead code — they serve `jellyfin-web`, which never
loads now — but the file is kept byte-identical to upstream **on purpose**, because
`getDeviceProfile()` is worth merging from upstream and a file we have not touched merges
cleanly. The adapters it registers (`mpvVideoPlayer`, `mpvAudioPlayer`, `inputPlugin`,
`updatePlugin`) and the server picker are deleted. **Call `window.api.player` directly.**

## Scope: movies and shows, nothing else

Glassfin plays **movies and TV series stored on a Jellyfin server**. Not live TV, not music.
This is a deliberate narrowing of JMP's surface, not a backlog.

What that removes: the entire live TV area (guide, channels, recordings, timers, tuners), the
music library and its player, and everything downstream of them. `native/mpvAudioPlayer.js`
becomes dead weight and the audio half of the device profile can be trimmed with it.

What that leaves the front end owing: `Movie`, `Series`, `Season`, `Episode`, and the small set
of queries around them — resume, next up, favourites, played state, search. Do not add feature
areas back without the project owner deciding to.

## What the shell already gives you

The reason a new front end is affordable. None of this lives in `jellyfin-web`, so none of it is
lost by dropping it:

- **Transcode negotiation.** `getDeviceProfile()` in [native/nativeshell.js](native/nativeshell.js)
  builds the `DeviceProfile` posted to `/Items/{id}/PlaybackInfo` — direct play vs transcode,
  DoVi/HDR force-transcode toggles, HLS transcoding profiles, subtitle formats. The *server*
  makes the decision; the client only has to describe itself honestly, and that description is
  already written.
- **A real input stack.** `src/input/` has SDL joystick (`InputSDL.cpp`), HDMI-CEC
  (`InputCEC.cpp`, so the TV remote works), LIRC infrared, and a mapping layer
  (`InputMapping.cpp`) driven by `resources/inputmaps/*.json`. It emits **semantic actions** —
  `up`, `select`, `back`, `play_pause` — over `api.input.hostInput`, not raw key codes.
  `SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS` is set, so it reads the pad unfocused.
- **mpv**, with ASS/SSA subtitle rendering, audio passthrough, and display-mode switching.

## Decisions already made — do not relitigate without new evidence

- **The front end is a new application, not a restyled `jellyfin-web`.** Ratified. The fear that
  drove the original plan — that Jellyfin's under-the-hood behaviour would be hard to
  reimplement — does not apply, because the device profile and the input stack are in the
  native/bridge layers this fork keeps. What remains to build is API orchestration, not protocol
  work.

## The application's identity

Settled, and settled everywhere at once. Changing any of it again moves people's config
directories, so don't.

| | |
| --- | --- |
| Application ID | `org.glassfin.Glassfin` |
| Binary | `glassfin` (`Glassfin` on macOS and Windows) |
| CMake target | `Glassfin` |
| Data / config | `~/.local/share/glassfin/`, `glassfin.conf` |
| Desktop entry | `resources/meta/org.glassfin.Glassfin.desktop` |
| MPRIS | `org.mpris.MediaPlayer2.Glassfin.profile_<n>` |
| CEC OSD name | `Glassfin` — this is what the television shows; libcec caps it at 13 characters |
| Icons | `resources/images/icon.svg` (+ `.png`), `bundle/win/glassfin.ico`, `bundle/osx/glassfin.icns` |

Nothing migrates from Jellyfin Desktop or Jellyfin Media Player, deliberately: their settings
describe a different interface.

**"Jellyfin" still appears, and most of it is correct.** The server is Jellyfin, the API is
Jellyfin's, ticks are Jellyfin's unit, and the licence and copyright belong to upstream. Three
files keep their old names on purpose: `debian/copyright` (authorship), `debian/changelog`
(entries below the first are upstream's history, kept as written) and `native/nativeshell.js`
(byte-identical to upstream so it can be merged — see the seam section). Before renaming any
remaining "Jellyfin", check which one it is.

## Open decisions — do not silently settle these

- **Steam Input.** Untested. Adding Glassfin to Steam as a non-Steam shortcut and launching it in
  Big Picture puts Steam Input between the pad and `SDL_INIT_JOYSTICK`. It may present a virtual
  pad, emulate a keyboard, or double up with the raw device. Run the experiment on the Chuwi
  before any of the interface depends on current behaviour.

## The front end (`web/`)

Svelte 5 + Vite + TypeScript. `npm install`, then `npm run dev` (port 5180), `npm run check`,
`npm run build`. Development happens in a desktop browser; only the shell has mpv.

| Module | Holds | Rule |
| --- | --- | --- |
| `src/lib/host.ts` | `window.api` and a mock of it | **The only module allowed to touch `window.api`.** |
| `src/lib/nav.ts` | Spatial navigation and focus | Everything reachable registers with `use:focusable`. |
| `src/lib/textentry.svelte.ts` | The one text buffer | **No `<input>` elements.** See below. |
| `src/lib/settings.svelte.ts` | Preferences | Behaviour is ours; subtitle appearance is the shell's. |
| `src/lib/theme.ts` | Light and dark | Writes `data-theme`; the guard in `index.html` says the same thing. |
| `src/lib/jellyfin.ts` | Server API, movies and series only | Makes no playback decisions. |
| `src/lib/playback.svelte.ts` | PlaybackInfo → mpv → progress reporting | No interface; transport UI comes later. |
| `src/App.svelte` | Routes host actions | **The single place input enters the app.** |

Three rules that keep this coherent, in rough order of how much damage breaking them does:

1. **Input enters at exactly one place** — `route()` in `App.svelte`. No component adds a key
   listener. During playback the transport owns the controller; otherwise navigation does.
2. **If it can be focused, it is registered.** An element reachable by eye but not by
   `use:focusable` is a dead end, and dead ends are the specific failure the couch bar exists to
   prevent.
3. **Bundle size is a feature.** The build is ~100 kB of JavaScript (35 kB gzipped) including the
   Svelte runtime, 21 kB of CSS, and 27 kB of vendored font. On the BC-250 every byte the UI
   spends is taken from software decode. Weigh dependencies against that, not against
   convenience.

The browser mock maps arrow keys, Enter, Escape and space onto host actions, and simulates a
player that advances position on a timer. It is enough to build and navigate the interface; it
proves nothing about playback.

Two contracts around focus are spread across files, so they are easy to break by accident:

- **`--focus-room`** (app.css) is the space a focused card's growth needs on one side. A scrolling
  row reserves it as top padding and a card uses it as the gap to its own title. A row that sets
  its own round number instead will slice the top off the focus ring — which is the half of the
  highlight that makes it read from a sofa — and let the artwork sit on the title.
- **`data-reveal`** marks the box `reveal()` in nav.ts should scroll into view when something
  inside it takes focus. A card's title and runtime are siblings of the focusable artwork, so
  without it they stay under the fold at the bottom of a screen. Anything where the focusable is
  smaller than the thing the viewer is actually choosing wants this attribute.
- **`enter: 'first'`** says focus arriving in this group from another one lands at its start
  rather than in the nearest column. Set it on horizontally scrolling rows and nowhere else: a
  carousel is scrolled to a position the viewer did not choose, so the column they came from
  points at nothing they can see. Grids and static button rows are aligned to the page and must
  keep the column — the on-screen keyboard is the clearest case, where going to the first item
  would mean landing on `A` every time you pressed up from Done.

## Text entry, and why there are no `<input>` elements

`EventFilter::eventFilter` (src/ui/EventFilter.cpp) returns `true` for every key press —
*"in konvergo we intercept all keyboard events and translate them into web client actions"*.

**A physical keyboard produces no DOM key events inside the shell.** No keydown, no input event,
nothing an `<input>` could bind to. A text field built the ordinary way works perfectly in the
browser and is completely dead on the television. Letters arrive through `hostInput` as
single-character actions, mapped by `resources/inputmaps/keyboard.json`.

Two quirks follow from that mapping, and both are reproduced by the browser mock on purpose:

- **Case is lost.** `"(?:Shift\+)?([A-Z])": "%1"` sends both `a` and `A` as the action `"A"`.
  Search and hostnames are case-insensitive, so this costs little, but it cannot be fixed from
  the web layer.
- **One key can emit several actions.** `InputMapping::mapToAction` appends every pattern that
  matches, so `P` arrives as `["P", "play_pause"]`. Anything consuming text takes the character
  and discards the rest.

So all text goes through `src/lib/textentry.svelte.ts`. The on-screen keyboard and a physical
keyboard are not separate features — both write into the same buffer, and a DualShock's keyboard
attachment can be used mid-word with the D-pad.

## Settings are split, on purpose

`src/lib/settings.svelte.ts` holds two different things and they are not interchangeable:

- **Behaviour is Glassfin's** — preferred audio and subtitle language, subtitle mode, intro and
  outro skipping. Stored in localStorage, applied in `playback.svelte.ts` before the first frame.
- **Subtitle appearance is the shell's** — size, font, colour, border, background, placement.
  That is mpv drawing pixels; no web layer can restyle it. Those write through to
  `api.settings.setValue('subtitles', …)`, matching the `subtitles` section of
  `resources/settings/settings_description.json`.

Adding a rendering option means adding it to the shell's settings description, not to ours. If a
preference could be honoured by either side, it belongs to whichever one actually acts on it.

Intro and outro markers come from `/MediaSegments/{itemId}` — native in Jellyfin 10.10+, the
Intro Skipper plugin before that. A server with neither returns nothing, which is a normal
outcome and never an error.

## The page is composited over mpv

The shell draws video in a layer *behind* the web view. **An opaque page background hides the
film completely.** `body.playing` in `app.css` drops the background to transparent and hides the
screens while `playback.item` is set; `App.svelte` toggles that class. Anything that paints a
full-bleed background needs to respect it.

Screens are hidden rather than unmounted, so scroll position and focus survive a film.

In a browser there is no mpv, so `Player.svelte` shows a stand-in panel instead. That panel is
not decoration: without it, starting playback disables spatial navigation and changes nothing on
screen, which is indistinguishable from the app freezing.

## Navigation is a stack

`App.svelte` keeps `Route[]`, not a current-screen name. Detail is reachable from home, a
library, and search, and Back has to return to whichever it was. Push to go deeper, pop to go
back, and `home` resets to a single entry.

Selection rules, which are deliberate rather than incidental: **episodes play, films and series
open their detail screen.** An episode in Continue Watching or Next Up is unambiguous; a film has
a resume point worth showing first, and a series has no single obvious episode.

## Changing tracks is not one operation

`setAudioStream` and `setSubtitleStream` only work when mpv actually holds the track. Whether it
does depends on what the server decided:

| Situation | What happens | Cost |
| --- | --- | --- |
| Direct play / direct stream | mpv switches the track in place | Instant |
| Transcoding, audio change | Re-request `PlaybackInfo` with `AudioStreamIndex`, reload at position | A pause |
| Subtitle with `DeliveryMethod: 'Encode'` | Burned into the picture; only the server can change it | A pause |
| Subtitle with `DeliveryMethod: 'External'` | Passed to mpv as `#,<url>` | Instant |

A client that only ever calls `setAudioStream` looks broken on transcoded content — the menu
closes and nothing changes. `playback.svelte.ts` checks `source.TranscodingUrl` and the stream's
delivery method and reloads when it has to, holding position and setting `playback.switching`.

**External subtitle URLs must be made absolute** (`Jellyfin.absoluteUrl`). The server returns them
server-relative, and mpv is not a browser — it has no page to resolve them against.

Preferences resolve to indices *before* the first load, not after it. Applying a subtitle
preference afterwards would start the film and then restart it, which is why `load` takes
`'auto'` as a distinct value from `null`.

## The brand is a file, not a set of hex codes

Colour, type and the mark come from the Glassfin style guide, and the top of `web/src/app.css`
transcribes it. Nothing else in the application names a colour.

The structure is three layers, and it is worth understanding before adding one:

- `--brand-*` — the guide's own palette. Ink, Paper, Lead, Silver, Trail, Accent, plus the greys
  and specimen surfaces it draws on. **Never referenced by a component.**
- `--ground`, `--raised`, `--edge`, `--ink`, `--ink-dim`, `--ink-faint`, `--accent`,
  `--accent-text`, `--danger`, and the shadows — role tokens, redefined under
  `:root[data-theme='light']`. **This is what components use.**
- `--over-*` — for anything that floats over video or over artwork.

Type is Space Grotesk, 400 and 500, vendored in `web/src/assets/fonts/` rather than fetched
(see the README there). **500 is the heaviest weight that exists.** A `font-weight: 600` will
render as synthesised fake bold, which on a television looks like a rendering fault.

`web/src/components/Logo.svelte` draws the mark. Two things about it are load-bearing: the facets
read `--fin-1..12`, which the theme redefines, and the cuts between them are painted in the
*background* colour rather than an ink — so on anything but the page ground the caller must set
`--logo-cut`.

## Light and dark, and the one thing that has neither

Dark is what `:root` says, so it needs no marker; light is `data-theme="light"` on the document
element. Three moving parts, and they have to agree:

1. `lib/theme.ts` — `applyTheme()`, the only writer of that attribute at runtime.
2. The inline guard at the top of `index.html` — the same logic again, so the attribute is set
   before the first paint. Change one and change the other.
3. `preferences.theme` (`dark` | `light` | `system`), cycled from Settings, applied by an effect
   in `App.svelte`.

Dark is the default, not `system`. A television in a dark room is the case to be right about, and
most shells have no palette preference to consult.

**The picture is not themeable.** The transport, the track menu, the skip prompt, the wash under
a library tile's name, the progress bar on a poster and the watched tick are dark in both themes,
because they are read against a photograph and a photograph has no light mode. Those use
`--over-*`. Getting this wrong produces something that looks fine in review and is unreadable the
moment a film starts.

Two contrast notes, so they are not "fixed" back:

- Light `--ink-faint` is the guide's Mist darkened about 14%. Mist itself lands at 3.2:1 on
  paper, which is fine on a printed sheet and not fine as hint text seen from three metres.
- Light `--accent-text` is a deeper gold than Lead. Lead manages 2.8:1 on paper; gold on white is
  simply a harder problem than gold on black.

## Build reality

Qt6 + CMake + mpv, built on Linux for a Flatpak. **Building on this Windows machine is not the
path** — the target is Bazzite, and the shell needs a Linux toolchain to be worth testing. Assume
edits happen here and builds happen on a Bazzite box or in a container.

The build now needs Node as well as Qt, because the front end is built as part of it. `nodejs`
and `npm` are in `debian/control` and `dev/appimage/Dockerfile`; the macOS and Windows runners
already have Node. A host without it configures with `-DBUILD_WEB_CLIENT=OFF
-DWEB_CLIENT_DIST=<a built web/dist>`. There is deliberately no option that produces a binary
with no interface in it — that binary starts, shows nothing, and takes an afternoon to diagnose.
