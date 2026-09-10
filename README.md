# Glassfin

A Jellyfin television client for the living room — Flutter on Linux desktop, with
[media_kit](https://pub.dev/packages/media_kit) (libmpv) doing playback.

Three metres, a D-pad, and a remote with about eight usable buttons. Movies and TV series only.

## Status

Being rebuilt. The previous version — Jellyfin Media Player forked, its web client replaced with a
Svelte front end, mpv compositing behind a transparent QtWebEngine view — is at `../glassfin_old`
and on this same remote's history. It worked, but the seam between two GPU renderers in one window
produced every hard bug in the project.

## Building

Needs the Flutter SDK, a Linux desktop toolchain (clang, cmake, ninja, pkg-config, GTK 3) and
`libmpv.so.2`.

```sh
flutter pub get
flutter run -d linux
```

`flutter analyze` and `flutter test` should both be clean.

## Documentation

- [CLAUDE.md](CLAUDE.md) — architecture, conventions, and the decisions that are settled
- [docs/ui-spec.md](docs/ui-spec.md) — the complete interface specification
- [docs/native-audit.md](docs/native-audit.md) — what the Qt shell did, and how it ports

## Licence

GPLv2 — see [LICENSE](LICENSE). Ported from
[Jellyfin Media Player](https://github.com/jellyfin/jellyfin-media-player), which is GPLv2, so
this stays. Space Grotesk is under the SIL Open Font License; see
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
