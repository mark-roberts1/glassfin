# Glassfin

A Jellyfin client for the television, forked from
[Jellyfin Media Player](https://github.com/jellyfin/jellyfin-media-player).

JMP already solves the hard half of the problem. It embeds **mpv**, which means direct play, HDR,
bitstreamed audio, and subtitle handling that a browser cannot match. What it does not have is an
interface you would choose to look at, or one that behaves under a D-pad.

Glassfin keeps the playback engine and replaces the interface.

## Scope

**Movies and TV series stored on a Jellyfin server.** No live TV, no music. That is the whole
surface, and narrowing it is what makes replacing the interface a tractable project rather than
a reimplementation of `jellyfin-web`.

## Target

**Bazzite**, first and for now only — delivered as a Flatpak, launched from a Steam Big Picture
session as a non-Steam shortcut. Other platforms are not being designed against and are not being
deliberately broken.

## How the fork is structured

JMP is three layers, and only the top one is wrong:

| Layer | What it does | Glassfin's plan |
| --- | --- | --- |
| **Native shell** (`src/`, C++/Qt) | Window, input, power, MPRIS, and the mpv player | **Keep.** This is the reason to fork rather than start over. |
| **Bridge** (`native/*.js`) | Exposes the shell to the web layer as `window.api` | **Keep the object, retarget the adapter.** |
| **Web client** | Whatever `jellyfin-web` the server happens to serve | **Replace.** This is the project. |

Upstream never bundled a web client. It shows a server-picker page and then points the webview
at `http://your-server/web/`, so the interface is the server's own copy of `jellyfin-web`,
fetched at run time. Glassfin builds `web/` during the CMake build, bakes it into the binary as
Qt resources, and serves it on its own `glassfin://app/` URL scheme — a real origin, so
`localStorage` works, which a `qrc:` page does not get.

The bridge is better than it needed to be. `window.api.player` is a general-purpose native API —
`load`, `stop`, `setAudioStream`, `setSubtitleStream`, `setSubtitleDelay`, `setVideoRectangle`,
plus signals for `playing`, `positionUpdate`, `finished`, `updateDuration`, `error`, `paused`,
and `bufferedRangesUpdated`. [native/mpvVideoPlayer.js](native/mpvVideoPlayer.js) is only an
*adapter* from `jellyfin-web`'s plugin interface onto that API. A new front end can call
`window.api.player` directly and never load `jellyfin-web` at all.

## Status

The front end lives in `web/` and runs in a browser.

Sign-in by **Quick Connect**, with a password path and sign-out from Settings. A home screen of
Continue Watching, Next Up, library tiles and Recently Added. Full library browsing with paging.
Detail screens for films and series — backdrop, tagline, synopsis, cast and crew, media badges
for resolution, dynamic range, codec and audio, resume, seasons and episodes. Search with an
on-screen keyboard a physical keyboard types into interchangeably. Settings for audio and
subtitle language, subtitle behaviour, intro and credit skipping, and mpv's own subtitle
appearance.

In playback: a transport overlay with a scrub bar that hides itself, intro and credit skipping,
and an audio and subtitle menu that handles the transcoding case properly — reloading at position
when the server has to be asked again, switching in place when mpv already holds the track.

Spatial navigation with per-row focus memory over a route stack throughout.

Branded to the Glassfin style guide: its palette, its wordmark, its fin mark — which redraws
itself per theme and drops to the flat silhouette below 32px, as the guide asks — and Space
Grotesk, vendored so the appliance never needs the internet to render its own name. Light and
dark themes, chosen in Settings or followed from the shell, with everything that sits over video
or artwork deliberately left dark in both.

The shell now loads it. `cmake` builds `web/` with npm as part of the build; pass
`-DBUILD_WEB_CLIENT=OFF -DWEB_CLIENT_DIST=<path>` on a build host without Node. Set
`path/startupurl_desktop` to `http://localhost:5180` to run `npm run dev` against real mpv.

The application is Glassfin all the way down: `glassfin` on disk, `org.glassfin.Glassfin` as
the app ID, desktop entry, MPRIS name and Wayland app ID, and its own icon at every size a
launcher asks for. Config lives in `~/.local/share/glassfin/`; nothing is migrated from Jellyfin
Desktop or Jellyfin Media Player.


## Licence

GPLv2, inherited from JMP (itself a fork of Plex Media Player). Not negotiable — the front end
ships in the same binary and takes the same licence.
