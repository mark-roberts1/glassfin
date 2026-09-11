#!/usr/bin/env python3
"""Generate branding/steamgriddb/*.png from the style guide.

The mark geometry (FACETS/CUTS/SILHOUETTE) is transcribed verbatim from
glassfin_old/web/src/components/Logo.svelte, and the colours from
docs/ui-spec.md §1.2/1.3 (dark palette). Re-run this after either changes
instead of hand-editing the PNGs.

Requires: python3, rsvg-convert (librsvg), ImageMagick (`magick`). Run from
the repo root:

    python3 branding/generate_steamgriddb_art.py
"""

import os
import subprocess
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "branding", "steamgriddb")
FONT_MEDIUM = os.path.join(REPO_ROOT, "assets", "fonts", "SpaceGrotesk-Medium.ttf")

# --- geometry, transcribed verbatim from Logo.svelte -----------------------

FACETS = [
    'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 L 31.05 110.19 Z',
    'M 31.05 110.19 L 53.54 44.03 Q 66 41.02 70.69 29.1 L 43.69 108.5 Z',
    'M 43.69 108.5 L 70.69 29.1 Q 78.62 29.91 83.84 23.89 L 55.56 107.05 Z',
    'M 55.56 107.05 L 83.84 23.89 Q 88.97 27.11 94.56 24.76 L 66.96 105.94 Z',
    'M 66.96 105.94 L 94.56 24.76 Q 97.87 29.59 103.72 29.65 L 78.02 105.24 Z',
    'M 78.02 105.24 L 103.72 29.65 Q 105.85 35.53 111.88 37.16 L 88.81 105 Z',
    'M 88.81 105 L 111.88 37.16 Q 113.29 43.68 119.44 46.27 L 99.39 105.24 Z',
    'M 99.39 105.24 L 119.44 46.27 Q 120.49 53.11 126.7 56.18 L 109.79 105.94 Z',
    'M 109.79 105.94 L 126.7 56.18 Q 127.68 63.09 133.9 66.25 L 120.03 107.05 Z',
    'M 120.03 107.05 L 133.9 66.25 Q 135.05 72.98 141.22 75.91 L 130.14 108.5 Z',
    'M 130.14 108.5 L 141.22 75.91 Q 142.75 82.24 148.81 84.63 L 140.12 110.19 Z',
    'M 140.12 110.19 L 148.81 84.63 Q 151.14 90.15 157 91.41 L 150 112 Z',
]

CUTS = [
    'M 16 112 L 24.98 85.6',
    'M 31.05 110.19 L 53.54 44.03',
    'M 43.69 108.5 L 70.69 29.1',
    'M 55.56 107.05 L 83.84 23.89',
    'M 66.96 105.94 L 94.56 24.76',
    'M 78.02 105.24 L 103.72 29.65',
    'M 88.81 105 L 111.88 37.16',
    'M 99.39 105.24 L 119.44 46.27',
    'M 109.79 105.94 L 126.7 56.18',
    'M 120.03 107.05 L 133.9 66.25',
    'M 130.14 108.5 L 141.22 75.91',
    'M 140.12 110.19 L 148.81 84.63',
    'M 150 112 L 157 91.41',
]

SILHOUETTE = (
    'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 Q 66 41.02 70.69 29.1 '
    'Q 78.62 29.91 83.84 23.89 Q 88.97 27.11 94.56 24.76 Q 97.87 29.59 103.72 29.65 '
    'Q 105.85 35.53 111.88 37.16 Q 113.29 43.68 119.44 46.27 Q 120.49 53.11 126.7 56.18 '
    'Q 127.68 63.09 133.9 66.25 Q 135.05 72.98 141.22 75.91 Q 142.75 82.24 148.81 84.63 '
    'Q 151.14 90.15 157 91.41 L 150 112 L 140.12 110.19 L 130.14 108.5 L 120.03 107.05 '
    'L 109.79 105.94 L 99.39 105.24 L 88.81 105 L 78.02 105.24 L 66.96 105.94 '
    'L 55.56 107.05 L 43.69 108.5 L 31.05 110.19 L 16 112 Z'
)

# docs/ui-spec.md §1.3, dark palette (Glassfin's default theme)
FIN_DARK = ['#f4b46d', '#e0be76', '#cdc586', '#bec998', '#b4cba9', '#b1cab6',
            '#abcbbe', '#9dcec7', '#8ed0d5', '#83d0e6', '#81cdf9', '#95c7ff']
INK = '#f5f3ee'    # dark-theme --ink (Paper)
NIGHT = '#0b1114'  # dark-theme --ground / --brand-night

ART_W, ART_H = 156, 106  # native artboard is viewBox="10 14 156 106"


def mark_svg_fragment(size, cut_mode, cut_color=None):
    """An SVG <g> for the faceted mark at pixel height `size`, translated
    and scaled so it occupies (0,0)..(size*156/106, size).

    cut_mode: 'flat'  -> cuts stroked in cut_color (art with a real background)
              'punch' -> cuts are real alpha holes (transparent art)
    """
    scale = size / ART_H
    uid = f"m{id(object())}"

    facets = "".join(
        f'<path d="{d}" fill="{FIN_DARK[i]}" />' for i, d in enumerate(FACETS)
    )
    cuts_paths = "".join(f'<path d="{d}" />' for d in CUTS)

    if cut_mode == 'flat':
        cut_group = (
            f'<g fill="none" stroke="{cut_color}" stroke-width="2.1" '
            f'stroke-linecap="round">{cuts_paths}</g>'
        )
        facet_layer = f'<g mask="url(#{uid}-fade)">{facets}</g>'
        punch_mask = ""
    elif cut_mode == 'punch':
        cut_group = ""  # the punch mask below is the gap; no visible stroke
        facet_layer = (
            f'<g mask="url(#{uid}-fade)">'
            f'<g mask="url(#{uid}-punch)">{facets}</g>'
            f'</g>'
        )
        punch_mask = (
            f'<mask id="{uid}-punch" maskUnits="userSpaceOnUse" '
            f'x="10" y="14" width="156" height="106">'
            f'<rect x="10" y="14" width="156" height="106" fill="#fff" />'
            f'<g fill="none" stroke="#000" stroke-width="2.1" '
            f'stroke-linecap="round">{cuts_paths}</g>'
            f'</mask>'
        )
    else:
        raise ValueError(cut_mode)

    defs = (
        f'<linearGradient id="{uid}-fadeGrad" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="#fff" stop-opacity="1" />'
        f'<stop offset=".58" stop-color="#fff" stop-opacity=".82" />'
        f'<stop offset="1" stop-color="#fff" stop-opacity=".2" />'
        f'</linearGradient>'
        f'<mask id="{uid}-fade" maskUnits="userSpaceOnUse" x="10" y="14" width="156" height="106">'
        f'<rect x="10" y="14" width="156" height="106" fill="url(#{uid}-fadeGrad)" />'
        f'</mask>'
        f'{punch_mask}'
    )

    # The hairline outline of the page's own ink, same as the tail's edge
    # once the fade mask has taken the colour out of it.
    hairline = (
        f'<path d="{SILHOUETTE}" fill="none" stroke="{INK}" '
        f'stroke-opacity=".32" stroke-width="{1 / scale:.4f}" stroke-linejoin="round" />'
    )

    return (
        f'<g transform="translate({-10 * scale},{-14 * scale}) scale({scale})">'
        f'<defs>{defs}</defs>'
        f'{facet_layer}'
        f'{cut_group}'
        f'{hairline}'
        f'</g>'
    )


def write_svg(path, width, height, body):
    with open(path, 'w') as f:
        f.write(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">{body}</svg>'
        )


def rsvg(svg_path, png_path, width, height):
    subprocess.run(
        ["rsvg-convert", "-w", str(width), "-h", str(height), "-o", png_path, svg_path],
        check=True,
    )


def bg_gradient_rect(w, h):
    """The app icon's background: a vertical Night gradient plus a soft
    Silver glow (assets/images/icon.svg), reused so every asset reads as
    one family."""
    return (
        '<defs>'
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#1D292F" />'
        '<stop offset="1" stop-color="#070C0E" />'
        '</linearGradient>'
        '<radialGradient id="glow" cx="50%" cy="46%" r="65%">'
        '<stop offset="0" stop-color="#a9ccbe" stop-opacity=".22" />'
        '<stop offset="1" stop-color="#a9ccbe" stop-opacity="0" />'
        '</radialGradient>'
        '</defs>'
        f'<rect x="0" y="0" width="{w}" height="{h}" fill="url(#bg)" />'
        f'<rect x="0" y="0" width="{w}" height="{h}" fill="url(#glow)" />'
    )


def draw_text(src_png, dst_png, text, pointsize, color, dx, dy, tracking_em=-0.02):
    """Composite `text` onto src_png using the real Space Grotesk Medium
    file. dx/dy offset the text's own centre from the canvas centre
    (ImageMagick gravity Center + -annotate), so callers work in plain
    layout coordinates instead of guessed font metrics."""
    kerning = tracking_em * pointsize
    subprocess.run(
        ["magick", src_png,
         "-font", FONT_MEDIUM,
         "-pointsize", str(pointsize),
         "-kerning", f"{kerning:.3f}",
         "-fill", color,
         "-gravity", "Center",
         "-annotate", f"{dx:+.1f}{dy:+.1f}", text,
         dst_png],
        check=True,
    )


def text_extent(text, pointsize, tracking_em=-0.02):
    """Measure rendered text width/height via ImageMagick, so lockups can be
    laid out without guessing font metrics by hand."""
    kerning = tracking_em * pointsize
    out = subprocess.run(
        ["magick", "-font", FONT_MEDIUM, "-pointsize", str(pointsize),
         "-kerning", f"{kerning:.3f}",
         "-background", "none", "-fill", "white",
         f"label:{text}", "-format", "%w %h", "info:"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    w, h = out.split()
    return float(w), float(h)


def build_icon(scratch):
    src = os.path.join(REPO_ROOT, "assets", "images", "icon.svg")
    for size in (512, 1024):
        rsvg(src, os.path.join(OUT_DIR, f"icon_{size}.png"), size, size)


def build_logo(scratch):
    """Transparent mark + wordmark, for SteamGridDB's Logo slot (floats over
    a Hero image). The cuts are real alpha holes rather than a guessed
    background colour, since there's no fixed surface behind this one."""
    mark_h = 340
    gap = mark_h * 0.16
    mark_w = mark_h * ART_W / ART_H
    pad = 60
    pointsize = mark_h * 0.42

    text_w, _ = text_extent("glassfin", pointsize)

    canvas_w = int(pad * 2 + mark_w + gap + text_w)
    canvas_h = int(pad * 2 + mark_h)

    mark_body = f'<g transform="translate({pad},{pad})">' + \
        mark_svg_fragment(mark_h, cut_mode='punch') + '</g>'

    svg_path = os.path.join(scratch, "logo_mark.svg")
    write_svg(svg_path, canvas_w, canvas_h, mark_body)
    base_png = os.path.join(scratch, "logo_mark.png")
    rsvg(svg_path, base_png, canvas_w, canvas_h)

    text_cx = pad + mark_w + gap + text_w / 2
    dx = text_cx - canvas_w / 2
    draw_text(base_png, os.path.join(OUT_DIR, "logo.png"), "glassfin", pointsize, INK, dx, 0)


def build_scene(scratch, width, height, mark_h, filename, text_below):
    """A full background composition (a capsule or the Hero): the icon's
    gradient ground, the mark with cuts painted in Night (matching the
    darkest part of that gradient, the same approximation
    assets/images/icon.svg makes), and the wordmark laid out either under or
    beside it."""
    body = bg_gradient_rect(width, height)

    mark_w = mark_h * ART_W / ART_H
    gap = mark_h * 0.16
    pointsize = mark_h * 0.42
    text_w, text_h = text_extent("glassfin", pointsize)

    if text_below:
        block_h = mark_h + gap + text_h
        mx = (width - mark_w) / 2
        my = (height - block_h) / 2
        text_cx = width / 2
        text_cy = my + mark_h + gap + text_h / 2
    else:
        block_w = mark_w + gap + text_w
        mx = (width - block_w) / 2
        my = (height - mark_h) / 2
        text_cx = mx + mark_w + gap + text_w / 2
        text_cy = my + mark_h / 2

    body += f'<g transform="translate({mx},{my})">' + \
        mark_svg_fragment(mark_h, cut_mode='flat', cut_color=NIGHT) + '</g>'

    svg_path = os.path.join(scratch, f"{filename}.svg")
    write_svg(svg_path, width, height, body)
    base_png = os.path.join(scratch, f"{filename}_base.png")
    rsvg(svg_path, base_png, width, height)

    dx = text_cx - width / 2
    dy = text_cy - height / 2
    draw_text(base_png, os.path.join(OUT_DIR, f"{filename}.png"), "glassfin", pointsize, INK, dx, dy)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="glassfin-steamgriddb-") as scratch:
        build_icon(scratch)
        build_logo(scratch)
        # SteamGridDB "Grid" tab, portrait aspect — the default library capsule
        build_scene(scratch, 600, 900, mark_h=210, filename="capsule_portrait", text_below=True)
        # SteamGridDB "Grid" tab, landscape aspect — the legacy/Big Picture capsule
        build_scene(scratch, 460, 215, mark_h=95, filename="capsule_landscape", text_below=False)
        # SteamGridDB "Hero"
        build_scene(scratch, 3840, 1240, mark_h=460, filename="hero", text_below=False)
    print(f"wrote {OUT_DIR}")
