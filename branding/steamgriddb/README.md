# SteamGridDB art

Custom artwork for Glassfin's non-Steam-game shortcut, generated from the style guide by
[`../generate_steamgriddb_art.py`](../generate_steamgriddb_art.py) — re-run that script rather
than hand-editing these PNGs if the palette or mark ever changes.

| File | Size | SteamGridDB slot |
| --- | --- | --- |
| `capsule_portrait.png` | 600×900 | Grid, portrait aspect (the default library tile) |
| `capsule_landscape.png` | 460×215 | Grid, landscape aspect (the legacy/Big Picture capsule) |
| `hero.png` | 3840×1240 | Hero (the banner behind a game's detail page) |
| `logo.png` | ~1610×460, transparent | Logo (floats over the Hero; alpha-cut, no background) |
| `icon_512.png`, `icon_1024.png` | 512² / 1024² | Icon (small square, used in list view) |

The two `capsule_*.png` files are what SteamGridDB calls "Grids" on their site and in the Manager
app — they're the game-box-shaped artwork, named here after their common shape rather than the
site's tab label.

## Applying them

1. Add Glassfin as a non-Steam shortcut first (Steam → Games → Add a Non-Steam Game), if it isn't
   one already.
2. Get the **SteamGridDB Manager** desktop app from steamgriddb.com and sign in — it auto-detects
   your Steam shortcuts.
3. On steamgriddb.com, open (or create) the Glassfin entry and upload each file above under its
   matching tab (Grids, Heroes, Logos, Icons).
4. In the Manager app, find the Glassfin shortcut, pick your uploads from each tab, and apply.
   That writes into `~/.local/share/Steam/userdata/<id>/config/grid/`, keyed by the shortcut's
   Steam-generated appid — restart Steam (or Big Picture) to see it.

`icon_512.png`/`icon_1024.png` are just the existing `assets/images/icon.svg` rasterized larger —
the app icon and the SteamGridDB icon are meant to be the same mark.
