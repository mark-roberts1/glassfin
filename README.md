<p align="center">
  <img src="branding/steamgriddb/hero.png" alt="Glassfin" width="640">
</p>

<p align="center">
  A Jellyfin television client for the living room.
</p>

---

Glassfin plays the films and television shows on your [Jellyfin](https://jellyfin.org) server, on
a television, from a sofa. Every part of it is reachable with a game controller or a remote —
nothing needs a mouse, a keyboard or a terminal in normal use.

It is a Flutter rewrite of a fork of
[Jellyfin Media Player](https://github.com/jellyfin/jellyfin-media-player): the interface is
Flutter, and [media_kit](https://pub.dev/packages/media_kit) — which is libmpv — does playback.
Video is a widget rather than a layer behind a browser, so there is no seam between two GPU
renderers sharing one window.

## Features

- **Built for a couch, not a desk.** Every interactive element is reachable by directional
  navigation, with a custom spatial-focus policy tuned for rows, grids and an on-screen keyboard.
  Focus is always visible and never lost.
- **libmpv playback**, not a browser's `<video>` element — hardware decoding, audio passthrough,
  and formats that would otherwise force the server to transcode.
- **Direct play, direct stream and transcoding**, including mid-playback audio and subtitle
  switching on both paths, and burned-in subtitles where the server has to encode them.
- **A real gamepad and HDMI-CEC-shaped input pipeline**, driven by the same input-map format
  Jellyfin Media Player used, so existing controller and remote mappings keep working.
- **Movies and TV series only.** No music, no live TV — a deliberate narrowing of scope, not a
  missing feature.
- **Intro/outro skipping** from Jellyfin's native media segments API (10.10+) or the Intro Skipper
  plugin, when the server has either.

## Status

The interface, playback engine and input pipeline (keyboard, mouse, and gamepad via SDL2) are
built and working against a real Jellyfin server: sign-in, browsing, direct play, transcoded
playback with track switching, resume, and spatial navigation all work. HDMI-CEC support and
Wayland refresh-rate switching are the remaining planned work — see
[CLAUDE.md](CLAUDE.md#open-decisions--do-not-silently-settle-these) for what's open and why.

## Requirements

- The [Flutter SDK](https://docs.flutter.dev/get-started/install/linux)
- A Linux desktop toolchain: `clang`, `cmake`, `ninja`, `pkg-config`, GTK 3
- `libmpv.so.2` at build and run time
- A Jellyfin server to connect to

## Building

```sh
flutter pub get
flutter run -d linux
```

```sh
flutter analyze   # must be clean
flutter test      # the ported logic is pure Dart and unit-tested
flutter build linux --release
```

### Flatpak

```sh
./linux/packaging/build-flatpak.sh           # build and install for this user
./linux/packaging/build-flatpak.sh --bundle  # also write a single .flatpak file
```

The first run compiles libmpv, libplacebo and libass from source and takes a while; after that,
`flatpak-builder` caches them and only the application rebuilds. See the comments in
[linux/packaging/org.glassfin.Glassfin.yml](linux/packaging/org.glassfin.Glassfin.yml) for why the
Flutter build happens outside the sandbox.

## Documentation

- **[CLAUDE.md](CLAUDE.md)** — architecture, conventions, and the decisions that are settled
- **[docs/ui-spec.md](docs/ui-spec.md)** — the complete interface specification: palettes, design
  tokens, every screen and component, and the spatial-navigation scoring algorithm
- **[docs/native-audit.md](docs/native-audit.md)** — everything the old Qt shell did that Flutter
  doesn't give away free: the Jellyfin device profile, tuned mpv properties, subtitle mapping,
  HDMI-CEC, input mapping constants, and refresh-rate selection

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

GPLv2 — see [LICENSE](LICENSE). Glassfin is a rewrite of a fork of
[Jellyfin Media Player](https://github.com/jellyfin/jellyfin-media-player), which is GPLv2, so
this stays GPLv2 too. Space Grotesk is licensed under the SIL Open Font License; see
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
