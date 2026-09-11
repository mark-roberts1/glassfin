# Native capability audit

What the old Qt/C++ shell (`glassfin_old/src/`, ~17,900 lines) actually provided, and what each
piece costs to replace in Flutter. Written during the migration so the domain knowledge buried in
that codebase isn't lost when the code is.

Three categories:

- **Data and policy** — copy or transcribe. Highest value per line; expensive to rediscover.
- **Algorithms** — port directly, they have no platform dependency.
- **Platform plumbing** — either a pub.dev package already solves it, or it's genuinely new work.

---

## 1. The device profile — the single highest-value artifact

`glassfin_old/native/nativeshell.js:64-213`. Describes the client to Jellyfin, which then decides
direct play vs transcode. Getting it wrong means silent transcodes or unplayable direct plays, and
the reasons behind each toggle are documented nowhere upstream.

### Static shape

```
Name:                             'Jellyfin Desktop'   (we override to 'Glassfin')
MaxStaticBitrate:                 1000000000           // 1 Gbps — i.e. never bitrate-limit direct play
MusicStreamingTranscodingBitrate: 1280000
TimelineOffsetSeconds:            5
ResponseProfiles / ContainerProfiles: []
```

### DirectPlayProfiles — deliberately unconstrained

```js
[{ Type: 'Audio' }, { Type: 'Photo' }]           // plus { Type: 'Video' } unless always_force_transcode
```

Note the shape: **no `Container`, no `Codec` fields.** In Jellyfin's profile semantics an
unconstrained direct-play profile means "anything". The client is declaring that mpv/ffmpeg will
play whatever the server has. That is why there is no codec enumeration anywhere — **mpv's answer
is "all of it."** media_kit is also libmpv, so this assumption carries over unchanged.

### TranscodingProfiles

```
{ Type: 'Audio' }                                       // unconstrained
{ Container: 'ts', Type: 'Video', Protocol: 'hls',
  AudioCodec: 'aac,mp3,ac3,opus,vorbis',
  VideoCodec: <below>,
  MaxAudioChannels: audio.channels === '2.0' ? '2' : '6' }
{ Container: 'jpeg', Type: 'Photo' }
```

`VideoCodec` is three-way, and **the ordering is the preference signal to the server**:

| Settings | Value |
| --- | --- |
| `allow_transcode_to_hevc` off | `h264,mpeg4,mpeg2video` |
| on, `prefer_transcode_to_h265` off | `h264,h265,hevc,mpeg4,mpeg2video` |
| on, `prefer_transcode_to_h265` on | `h265,hevc,h264,mpeg4,mpeg2video` |

`allow_transcode_to_hevc` exists as **a workaround for Dolby Vision content direct-playing when it
shouldn't**.

### CodecProfiles — the force-transcode toggles

Each is a *deliberately unsatisfiable condition*, which is how you force the server to transcode
rather than direct play.

| Setting | Condition pushed | Default |
| --- | --- | --- |
| `video.force_transcode_dovi` | `NotEquals VideoRangeType DOVI` | **`true`** |
| `video.force_transcode_hdr` | `Equals VideoRangeType SDR` | `false` |
| `video.force_transcode_hi10p` | `LessThanEqual VideoBitDepth 8` | `false` |
| `video.force_transcode_hevc` | `Codec: hevc` and `Codec: h265`, each `Equals Width 0` | `false` |
| `video.force_transcode_av1` | `Codec: av1`, `Equals Width 0` | `false` |
| `video.force_transcode_4k` | `LessThanEqual Width 1920`, `LessThanEqual Height 1080` | `false` |

**`Equals Width 0` is the idiom for "this codec can never be direct-played"** — no stream has
width 0. Comment it when porting.

**`force_transcode_dovi` defaults to `true`** because mpv renders Dolby Vision profile 5 with the
wrong colours. This is the flag to revisit if real DoVi support ever arrives.

### HDR, honestly

**There is no other HDR handling anywhere in the old `src/`.** The only HDR-adjacent C++ is a
macOS oversaturation fix (`format.setColorSpace(QColorSpace::SRgb)`) and `gpu-api=opengl` forced on
Windows. HDR today is entirely a "make the server transcode it away" policy. Upstream branch
`libmpv-vulkan-gpu-next-wayland-hdr` is where real HDR work would come from.

This matters for the Flutter migration: Flutter's texture pipeline is SDR, but the old app wasn't
passing HDR through either. The practical cost is close to zero today; it lowers the future ceiling.

### SubtitleProfiles — copy verbatim

```
srt, ass, sub, ssa, smi     → External and Embed
pgssub, dvdsub, dvbsub, pgs → Embed only        (bitmap formats)
```

---

## 2. mpv configuration — `glassfin_old/src/player/PlayerComponent.cpp` (1652 lines)

media_kit *is* libmpv and exposes `NativePlayer.setProperty()` / `.command()`, so **every property
below is directly settable from Dart.** Port the *set of properties and the reasoning*, not the code.

### Init-time — the hard-won ones

| Property | Value | Why |
| --- | --- | --- |
| `demuxer-mkv-probe-start-time` | `false` | **Load-bearing for Jellyfin.** MKV transcodes start at non-zero times; mpv would rebase to 0 and every reported position would be wrong. |
| `demuxer-lavf-probe-info` | `true` | Upstream mpv uses `auto`, which disables probing for HLS. |
| `audio-fallback-to-null` | `yes` | Don't abort playback when the audio device won't open — let the app decide. |
| `ad-lavc-downmix` | `false` | Don't let the decoder downmix; the app controls channel layout (needed by the passthrough logic). |
| `cache-seek-min` | `5000` | plex-media-player issue #736. |
| `audio-swresample-o` | `surround_mix_level=1` | Makes downmix behave like PHT. |
| `force-window` | `true` | Keeps the VO alive when idle. **See the render-context race below.** |

Boilerplate not worth porting: `msg-level`, `osd-level`, `ytdl`, `audio-client-name`, `title`,
TLS/CA configuration, and the Raspberry Pi block.

### Audio — real domain knowledge

Passthrough codec list is built from the device type:

- `basic` → no passthrough at all
- `spdif` → `{ac3, dts}`
- `hdmi` → `{ac3, dts, eac3, dts-hd, truehd}`

filtered by the individual `passthrough.<codec>` booleans, joined, and set as `audio-spdif`.

Three things that are only learned by shipping:

1. **`dts-hd` includes `dts`, but listing `dts` first may disable `dts-hd`** — so `dts` is removed
   from the list whenever `dts-hd` is present.
2. **Channel layout is forced to `2.0` when the device type is `spdif`**, because S/PDIF can't
   carry multichannel PCM.
3. **AC3 transcoding for S/PDIF:** when the device is `spdif` and `passthrough.ac3` is on, insert
   the audio filter `@ac3:lavcac3enc` (and remove it when the condition flips). This is how 5.1
   gets through an optical link. Only AC3 is implemented.

**Audio device hot-plug:** diff the previous and current `audio-device-list`; if the *user-selected*
device appears or disappears, wait **500ms** before reopening the audio output — change
notifications arrive in bursts, and reopening a just-reappeared device immediately fails.
Disconnected devices stay in the settings list as `[Disconnected device: X]` so the selection isn't
silently lost.

### Video

| Property | Note |
| --- | --- |
| `video-sync` | `audio` / `display-resample` / `display-adrop`. Default `audio`. |
| `hwdec` | **Default is `copy` → `auto-copy`, not `auto`.** Deliberate: hardware decode, but copied back through mpv's shader pipeline so the scaler and colour management still work. |
| `hwdec-image-format` | `uyvy422` only under macOS compatibility mode. |
| `display-fps-override` | **Critical and easy to miss.** mpv is *told* the display rate rather than guessing, re-set on every refresh-rate change and every load. Without it the `display-*` sync modes misbehave. |
| `demuxer-max-bytes` | cache setting × 1MiB, default 75MB. |

**Per-refresh-rate audio delay:** picks one of `audio_delay.{normal,24hz,25hz,50hz}` based on the
*current* display rate (matched with a 0.5Hz tolerance so 23.976 counts as 24), because some HDMI
audio paths have rate-dependent latency.

Aspect handling maps a mode onto `video-unscaled` / `video-aspect-override` / `keepaspect` /
`panscan`. `force_16_9_if_4_3` reads the decoded aspect and only overrides within 0.1 of 4:3.
`custom` deliberately touches nothing, leaving the user's own `mpv.conf` alone.

### Subtitles → mpv properties

| Setting | → mpv |
| --- | --- |
| `size` | `sub-scale = size / 32.0` (32 is "Normal") |
| `color`, `border_color` | `sub-color`, `sub-border-color` |
| `border_size` | `sub-border-size` |
| `background_color` + `background_transparency` | `sub-back-color` — **the alpha byte is inserted at index 1** of `#RRGGBB` to make `#AARRGGBB` |
| `placement` (`"x,y"`) | `sub-align-x`, plus `sub-pos` = 100 (bottom) or 10 (top) |
| `ass_scale_border_and_shadow` | `sub-ass-style-overrides=ScaledBorderAndShadow=yes/no` |
| `ass_style_override` | `sub-ass-override` |
| `font` | `sub-font` |

Note `background_transparency` is an **alpha byte, inverted relative to opacity** — preserve the
direction or the setting reads backwards.

Any user overrides in a free-text config block are applied **last**, so they always win.

### The two mpv hooks — how judder-free playback actually works

The most important non-obvious mechanism in the file:

- **`on_load`** blocks mpv *before* it opens the file. The display mode is switched, and playback
  resumes only after a configured delay (default 3s). Mode changes take time, the screen is black
  during them, and hardware decoder init can fail for "strange OS-related reasons" mid-switch.
  **You cannot do refresh-rate switching correctly without this gate.**
- **`on_preloaded`** is where streams are selected — the load command deliberately passes
  `aid=no,sid=no` so nothing is auto-selected first.

**media_kit does not expose mpv hooks.** Options: FFI to the raw handle (`NativePlayer.ctx` is
exposed, so `mpv_hook_add` / `mpv_hook_continue` are reachable), or restructure to
switch-mode → wait → `open()`, losing only the atomicity.

### A gotcha that will recur

`MpvVideoItem.cpp` carries a hard-won comment: the controller pointer is non-null immediately and
therefore **useless as a readiness check**; the real signal is a `ready` event emitted when the
render context is lazily created on first paint. Initialising before that makes `force-window=true`
fail with *"No render context set"*, and **mpv silently never retries for that session.** If
media_kit has an analogous lazy init, expect the same class of bug.

---

## 3. The input stack

> **Ported in Phase 6.** This section still describes the Qt build, which is what it is for. Five
> things the Dart port does *differently* are listed under "Deliberate divergences" at the end of
> the section — read those before concluding the code contradicts this document.

### Architecture

Every backend emits one signal — `(source, keycode, keystate)` — into a single funnel that maps
raw input to **semantic actions** (`up`, `select`, `back`, `play_pause`) via the mapping files.

### The mapping layer — copy the data, port the engine

`resources/inputmaps/*.json` are **pure data: copy verbatim.** JSONC (`//` comments allowed).

```json
{
  "name": "Xbox Controller",
  "idmatcher": "XInput.*|Microsoft.*joystick driver",
  "mapping": {
    "KEY_BUTTON_0": "enter",
    "KEY_BUTTON_1": { "short": "back", "long": "home" },
    "Space": ["space", "play_pause"],
    "KEY_NUMERIC_([0-9])": "%1"
  }
}
```

Four value forms: a plain action; a short/long press object; an **array of several actions**; and
capture-group substitution (`%1`).

**Multiple actions per keypress** is the important semantic. Every pattern that matches is appended,
so pressing `P` emits both `"P"` (from the letter rule) and `"play_pause"`. Consumers of text take
the first character and discard the rest.

Patterns are anchored (`^…$`) at load time and memoised. Bundled maps load first, then user maps
overlay them, with a filesystem watcher for hot reload — edit a JSON, remap your remote, no restart.

**Tuned constants to keep:**

| Constant | Value |
| --- | --- |
| Long-press threshold | 500ms |
| Autorepeat delay, then interval | 650ms, then 60ms |
| SDL axis → digital, on / off | 16384 / 10000 (hysteresis; naive thresholding chatters) |
| LIRC repeat decimation | every 3rd (`repeat % 3 == 0`), or the UI is unusable |

### Backends

| Backend | Notes | Flutter path |
| --- | --- | --- |
| **SDL joystick** | `SDL_INIT_JOYSTICK` only, 50ms poll, on a dedicated thread. Synthesises `KEY_BUTTON_n`, `KEY_HAT_*`, `KEY_AXIS_n_{UP,DOWN}`. `SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS` lets it read the pad unfocused. Source string is the joystick name, which is what `idmatcher` matches — hence separate maps per controller *and* per OS. | FFI to SDL2 (small, stable C surface) or the `gamepads` package. **Medium.** |
| **HDMI-CEC** | libcec on a thread. Adapter detection with a 10s re-detect timer and alert callbacks for hot-unplug — the resilience is much of the value. Maps ~32 CEC control codes. Handles Samsung's `AN_RETURN`, fakes key-press events for deck control (no up/down exists), treats vendor remote opcodes as press/release, and has a `usekeyupdown` setting because some TVs don't send releases. TV standby can suspend or power off the box. | **The hardest.** No Dart ecosystem. Cheapest: keep the C++ as a small helper binary emitting JSON over a socket. |
| **LIRC** | No library linkage at all — a unix socket to `/run/lirc/lircd` and a 4-field text protocol. | Pure Dart, ~60 lines. **Easy.** |
| **Keyboard** | The shell swallows *every* key event and reconstructs text from actions, which destroys case. A Glassfin-local fix returns the event's own text for unmodified printable keys so case and shifted symbols survive. | **Flutter gives real key events** — logical keys, characters and modifiers. Generate the same canonical strings (`"Ctrl+Shift+F"`) so `keyboard.json` works unchanged. This retires the whole text-entry workaround. |
| **Local socket** | Accepts `{client, source, keycode}` JSON so any external process can inject input. | Trivial in Dart — **and it's the natural CEC bridge.** |

### `host:` actions

Actions prefixed `host:` never reach the UI layer; they dispatch to registered native commands:
`fullscreen`, `switch` (display mode), `cycle_setting` / `set_setting`, `poweroff` / `reboot` /
`suspend`, `player` (raw mpv command), plus debug hooks.

### Deliberate divergences in the Dart port

The mapping **files** are unchanged — that is the contract, and `test/input/bundled_maps_test.dart`
holds it by reading the real `assets/inputmaps/` off disk. The **engine** differs in five places,
each because the original behaviour was a bug or an accident rather than a decision.

| | Qt build | Dart port | Why |
| --- | --- | --- | --- |
| Mapping identity | keyed on the `name` field | keyed on the **file name** | Three bundled files are all called "Xbox Controller" with different `idmatcher`s and *different axis layouts*. Keyed on the shared name they overwrite each other, so a Linux pad silently got the Windows layout. |
| `"KEY_BUTTON_8": ""` | an action named `""` | unbound, no action | Fired nothing, but did start the 60ms autorepeat timer for as long as an unbound button was held. |
| Synthetic autorepeat | ran for every source, keyboard included | **pad and remote only** | The OS already repeats a held key at the rate its owner chose. The original only avoided doubling it because Qt's repeat arrived faster than the 650ms delay and kept resetting the timer — a coincidence of two unrelated numbers. |
| Axis / hat state | keyed on axis number alone | keyed on `(joystick, axis)` | Two pads shared one state. |
| Match cache | hits only | hits and misses | Every unmapped key re-walked the whole pattern list. The list is immutable after load, so a negative cannot go stale. |

Two things in the original that look like divergences and are not. `cycle_subtitle` is a typo for
`cycle_subtitles` on the Xbox map's Y button — but that file defines `KEY_BUTTON_3` twice and the
second definition (`search`) wins in both JSON parsers, so the typo is unreachable and is left
exactly as it was. And `dualshock4-xbox-emulate.json` has its `idmatcher` line **commented out** on
purpose: a DS4 in Windows mode is indistinguishable from an Xbox pad, so its header tells you to
uncomment the line yourself. A map with no `idmatcher` is disabled, not broken, and must not warn.

**What SDL actually reports matters more than the file names suggest.** A DualShock 4 paired over
Bluetooth is `Wireless Controller` to the kernel but **`PS4 Controller` to SDL**, so
`dualshock4-usb.json` is the map that applies — and that is correct, because its button numbering is
the one SDL reports. Verified on hardware: X is `KEY_BUTTON_0`, Circle is `KEY_BUTTON_1`, the D-pad
is a hat, and the sticks are axes 0/1 and 3. When a pad does nothing, the name SDL gives it is the
first thing to check; it is logged on connect for that reason.

Still not ported, and tracked as Phase 7: **HDMI-CEC** and **LIRC**. The local socket that was the
natural bridge for both is also absent. `host:` actions are down to `fullscreen`, `minimize` and
`quit`/`close` — every other one addressed a subsystem this rebuild deleted.

---

## 4. Display mode / refresh-rate switching

### The algorithm — port verbatim, it has no platform dependency

Weighted scoring over available modes:

```
MATCH_WEIGHT_RES                        1000   // same width/height/bpp as current
MATCH_WEIGHT_REFRESH_RATE_EXACT          200   // within 0.01 Hz
MATCH_WEIGHT_REFRESH_RATE_MULTIPLE        75   // exact integer multiple
MATCH_WEIGHT_REFRESH_RATE_CLOSE           50   // within 0.5 Hz  (23.976 → 24p)
MATCH_WEIGHT_REFRESH_RATE_MULTIPLE_CLOSE  25
MATCH_WEIGHT_INTERLACE                    10
MATCH_WEIGHT_CURRENT                       5   // tiebreak toward doing nothing
```

A mode is accepted only if its score exceeds `MATCH_WEIGHT_RES` — i.e. **the resolution must match
the current mode and something about the rate must be better.** It never changes resolution behind
your back mid-playback.

The multiple test computes `factor = round(displayRate) / round(videoRate)` then checks
`|factor × videoRate − displayRate| < tolerance`, where tolerance is `0.01 × factor` for exact and
`1.0` for approximate. **This is what makes 24fps → 120Hz and 23.976 → 59.94 score as good
matches** rather than requiring a literal 24Hz mode.

`avoid_25hz_30hz` (default on) skips 25 and 30Hz candidates entirely — many displays handle 30Hz
badly.

On stop, restoring the previous mode checks `idle-active` first, so it doesn't switch back
between queued items.

### The plumbing — new work regardless

Backends exist for X11 (XRandR), Windows, macOS and Raspberry Pi. **There is no Wayland backend.**
On a Wayland session the entire subsystem is inert. Since Bazzite is the target, *this is a gap in
the old code, not an asset being lost.*

Options: FFI to `libXrandr` (plain C, no callbacks, ~300 lines) or shelling out to `xrandr` under
X11; on Wayland there is **no client-side mode-setting protocol**, so it depends on the compositor
— `wlr-output-management-unstable-v1` for wlroots, `kscreen-doctor` for KDE, or
`org.gnome.Mutter.DisplayConfig` over D-Bus for GNOME. **Identify Bazzite's compositor before
estimating.**

---

## 5. Settings

The old system parses a JSON schema (sections, defaults, possible values, help text, platform
masks) and generates a settings modal for jellyfin-web — 867 lines of C++ for a UI Glassfin already
deleted. **Keep the data, drop the machinery.**

Worth carrying over:

- the keys, defaults and possible values, as data;
- the value → mpv property mapping (§2);
- the conditional-visibility rule: when the audio device type changes, hide the irrelevant
  passthrough rows, and hide channel selection entirely for S/PDIF.

Sections: `main` (26 keys), `audio` (10), `video` (23), `subtitles` (10), `cec` (7, hidden),
`path` (2, hidden), plus small ones. The `ass_style_override` help text is a genuinely good
summary of mpv's semantics — reuse it as UI copy.

---

## 6. Everything else

| Area | What it is | Flutter path |
| --- | --- | --- |
| **MPRIS2** | Full D-Bus media control, Glassfin-authored. Service name is profile-scoped so profiles don't collide. Album art fetched through a disk cache and exposed as a data URI. | `audio_service`, or `dbus` directly. **Solved.** |
| **Screensaver inhibition** | `org.freedesktop.ScreenSaver.Inhibit` with cookie tracking, wired automatically to playback state so the UI never thinks about it. | `wakelock_plus`. **Keep the automatic wiring.** |
| **Power actions** | suspend / reboot / poweroff via `org.freedesktop.login1`, with capability probing. | `dbus`, ~40 lines. |
| **Single instance** | Named socket; a second launch tells the first to raise itself and exits. | Dart sockets, ~50 lines. |
| **Profiles and paths** | Named profiles each with data/cache/log dirs; feeds the MPRIS name, inputmap overrides and art cache. | `path_provider` + a thin layer. **Decide early whether profiles survive.** |
| **Logging** | Independent file and terminal levels, rotation, and **`CensorAuthTokens`** — elides 32 characters after `api_key=`, `X-MediaBrowser-Token=`, `ApiKey=`, `AccessToken=`, `AccessToken":"`. | `logging` package. **Copy the token pattern list.** |
| **Window management** | Fullscreen, always-on-top, cursor visibility, per-screen-configuration geometry persistence with debounced writes. | `window_manager`. |
| **Windows taskbar / SMTC, RPI JPEG decoder, OpenELEC service toggles** | Platform-specific. | Drop. |
| **EventFilter, custom URL scheme, webview.qml, CSP workaround, `getNativeShellScript`** | Exist only to serve the web-in-a-shell arrangement. | **Deleted.** |

---

## Summary — where the effort actually goes

**Free (copy):** inputmap JSON, subtitle profiles, settings keys and defaults, the log token list.

**Trivial (mechanical port, high value):** the device profile, the mapping engine and its tuned
constants, the refresh-rate scoring algorithm, the mpv property set.

**Low (packages):** MPRIS, screensaver, power, paths, window management, single instance.

**Medium:** spatial navigation, gamepad input, mpv hooks (for the display-switch gate).

**Hard — budget real time:** HDMI-CEC (no Dart ecosystem; helper process is the pragmatic answer)
and display-mode setting on Wayland (new work regardless, since no Wayland backend exists today).
