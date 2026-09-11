# Contributing to Glassfin

Glassfin is a small, opinionated project — a television client for one specific use case, with a
scope that is deliberately narrow. Before writing code, read **[CLAUDE.md](CLAUDE.md)**. It is the
authoritative source on architecture, conventions and the decisions that are already settled, and
it takes precedence over anything below if the two ever disagree.

## Before you start

- **Read [CLAUDE.md](CLAUDE.md), [docs/ui-spec.md](docs/ui-spec.md) and
  [docs/native-audit.md](docs/native-audit.md) first.** They were written by reading the old
  codebase exhaustively and are expensive to regenerate — most "why does it work this way"
  questions are already answered there.
- **Scope is movies and TV series, nothing else.** No music, no live TV. Don't add a feature area
  back without raising it as an issue first.
- **The bar is a remote from a sofa.** A change that needs a keyboard, a mouse, or desktop-scale
  UI in normal use doesn't meet it, however well it works otherwise.
- For anything larger than a small fix, open an issue or a draft PR before investing time in a
  full implementation, so the approach can be agreed on first.

## Three rules that keep this coherent

Breaking these is the fastest way to get a PR sent back for rework:

1. **Input enters at exactly one place.** One router at the root; no widget adds its own global
   key listener.
2. **If it can be focused, it is registered.** An element reachable by eye but not by the
   traversal policy in `lib/nav/` is a dead end.
3. **Nothing outside `lib/design/` names a colour or a size.** A raw `Color(0xFF…)` or a magic
   `24.0` in a screen is a bug, not a shortcut. Sizes quoted in the UI spec as `rem` are written as
   `Metrics.rem(...)` / `Type.rem(...)`.

## Setting up

```sh
flutter pub get
flutter run -d linux
```

Requirements: the Flutter SDK, a Linux desktop toolchain (`clang`, `cmake`, `ninja`, `pkg-config`,
GTK 3), and `libmpv.so.2` at build and run time. See [README.md](README.md#requirements).

A gamepad and CEC-capable hardware are useful but not required — the input pipeline, navigation
scoring, device-profile builder and track-choice logic are all pure Dart, exercised by
`flutter test` without any of it plugged in.

## Before opening a PR

```sh
flutter analyze   # must be clean
flutter test      # must pass
dart format .     # keep formatting consistent
```

Test what you can against a real Jellyfin server. If your change touches gamepad input, CEC, or
anything display-related and you can't verify it on real hardware, say so plainly in the PR —
that's useful information, not a reason to hold the PR back.

## Code style

- Follow the conventions already in the surrounding file over any general Dart style preference —
  this codebase has specific reasons (documented in CLAUDE.md and in code comments) for choices
  that might look unconventional at a glance.
- Comments explain *why*, not *what*. If removing a comment wouldn't confuse a future reader,
  don't add it.
- No speculative abstraction. Don't generalise a widget or helper for a use case that doesn't
  exist yet.
- `assets/inputmaps/*.json` and anything under `lib/input/` that reads them is a contract with the
  old Qt build's file format — see CLAUDE.md's section on input maps before touching either.

## Commit messages

Commit subjects in this repo are imperative and describe the user-visible effect, not the
mechanism — e.g. `Fix the DualShock layout under Steam`, `Stop losing focus when a film ends`,
`Honour the launcher's Fullscreen action`. Look at `git log` for the tone before writing one.

## Reporting bugs

Open an issue with:

- What you did and what you expected
- Jellyfin server version, and whether the content in question direct plays or transcodes
- Whether you were using a keyboard, gamepad, or CEC remote
- Logs, if you have them — the input pipeline in particular logs unmapped keys and pad names on
  connect, which is usually the fastest way to diagnose a controller issue

## Licensing

Glassfin is GPLv2, inherited from Jellyfin Media Player (see [LICENSE](LICENSE)). By contributing,
you agree your contribution is licensed under the same terms.
