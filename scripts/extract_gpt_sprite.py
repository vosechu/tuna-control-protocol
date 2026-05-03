"""Extract a clean pixel-art sprite from a GPT-Images-2 template output.

GPT's image_generation tool delivers images at its own native resolution
(commonly 1254x1254 or 1024x1024 at time of writing), regardless of the
2048x2048 template we asked for. The output is also diffusion-rendered
with anti-aliased edges, not crisp pixel blocks.

This script recovers a clean logical-pixel sprite from such an output:

  1. Locate the magenta (#FF00FF) frame of the hero box automatically.
  2. Crop the hero interior and nearest-neighbor downscale to logical
     W x H.
  3. Quantize every pixel to the closest color in the supplied TCP
     palette, collapsing diffusion slop into palette-exact pixels.
  4. Preserve alpha: transparent input -> transparent output.
  5. Optionally extract each of the 8 slots the same way and compose
     them into a shippable W*8 x H animation strip.

Outputs land next to the source PNG with suffixes:
  <src>_hero_WxH.png       — quantized hero at native logical size
  <src>_hero_WxH_16x.png   — 16x preview for inspection
  <src>_strip8.png         — 8-frame animation strip at W*8 x H
  <src>_strip8_16x.png     — 16x preview strip
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

# TCP palette (hex strings and their RGB tuples).
TCP_PALETTE = {
    "slate_void":     (0x1A, 0x1E, 0x2E),
    "cable_gray":     (0x3B, 0x41, 0x57),
    "dust_blue":      (0x5B, 0x6B, 0x8A),
    "indicator_teal": (0x4A, 0x9B, 0x9B),
    "warning_amber":  (0xC4, 0xA2, 0x4E),
    "breath_white":   (0xD4, 0xDA, 0xE8),
    "den_brown":      (0x2E, 0x20, 0x18),
    "worn_wood":      (0x6B, 0x52, 0x40),
    "sunpatch_gold":  (0xC4, 0x95, 0x48),
    "purr_orange":    (0xD4, 0x76, 0x3A),
    "moss_green":     (0x5B, 0x8B, 0x4A),
    "cream":          (0xF0, 0xE6, 0xD0),
}

PALETTE_ARR = np.array(list(TCP_PALETTE.values()), dtype=np.int32)
PALETTE_NAMES = list(TCP_PALETTE.keys())


def quantize_to_palette(rgb_pixels: np.ndarray) -> np.ndarray:
    """Snap every RGB pixel to the nearest palette color. rgb_pixels: (N,3)."""
    rgb = rgb_pixels.astype(np.int32)
    # (N, 1, 3) - (1, P, 3) -> (N, P, 3) -> (N, P)
    distances = ((rgb[:, None, :] - PALETTE_ARR[None, :, :]) ** 2).sum(axis=2)
    nearest = np.argmin(distances, axis=1)
    return PALETTE_ARR[nearest].astype(np.uint8)


def detect_magenta_frame(arr: np.ndarray, threshold: int = 180) -> tuple[int, int, int, int]:
    """Return (x0, y0, x1, y1) for the outermost magenta-bordered rectangle.

    Uses thresholded "magenta-ish" detection: R > threshold, G < 100,
    B > threshold. Tolerates diffusion drift of the magenta borders.
    """
    mag = (arr[:, :, 0] > threshold) & (arr[:, :, 1] < 100) & (arr[:, :, 2] > threshold)
    col_sum = mag.sum(axis=0)
    row_sum = mag.sum(axis=1)

    # Require columns/rows with at least 20% of their extent magenta.
    h, w = arr.shape[:2]
    strong_cols = np.where(col_sum > h * 0.2)[0]
    strong_rows = np.where(row_sum > w * 0.2)[0]
    if len(strong_cols) < 2 or len(strong_rows) < 2:
        raise ValueError("Could not locate magenta frame in source image.")

    return int(strong_cols[0]), int(strong_rows[0]), int(strong_cols[-1]), int(strong_rows[-1])


def _flood_fill_mask(rgb: np.ndarray, start_yx: tuple[int, int]) -> np.ndarray:
    """Return a boolean mask of pixels matching start's color, reachable from start via 4-connectivity."""
    h, w = rgb.shape[:2]
    y0, x0 = start_yx
    target = rgb[y0, x0]
    mask = np.zeros((h, w), dtype=bool)
    stack = [(y0, x0)]
    while stack:
        y, x = stack.pop()
        if mask[y, x]:
            continue
        if not (rgb[y, x] == target).all():
            continue
        mask[y, x] = True
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return mask


def extract_region(
    img: Image.Image, bounds: tuple[int, int, int, int], logical_size: tuple[int, int]
) -> Image.Image:
    """Crop, nearest-neighbor downscale, quantize to palette, then flood-fill background from
    the four corners to transparent alpha. Produces a clean sprite on a transparent canvas.
    """
    crop = img.crop(bounds)
    # Area-averaging downscale (Image.BOX) preserves composition — each
    # output pixel is the mean of its source region. Nearest-neighbor
    # would sample a single random source pixel and lose the silhouette.
    # Quantization after the downscale snaps blended colors to palette.
    small = crop.resize(logical_size, Image.BOX).convert("RGBA")
    small_arr = np.array(small)
    alpha = small_arr[:, :, 3]
    rgb = small_arr[:, :, :3]

    # Quantize everything first so flood fill matches exact palette colors.
    rgb_flat = rgb.reshape(-1, 3)
    quantized = quantize_to_palette(rgb_flat)
    rgb = quantized.reshape(rgb.shape)

    # Flood fill from each corner. Any pixel reachable from a corner via
    # same-color neighbors is considered background.
    h, w = rgb.shape[:2]
    background_mask = np.zeros((h, w), dtype=bool)
    for corner in [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]:
        background_mask |= _flood_fill_mask(rgb, corner)

    # Build output alpha: background → 0, everything else → 255 (honoring input alpha if < 128).
    out_alpha = np.where(background_mask | (alpha < 128), 0, 255).astype(np.uint8)

    # For transparent pixels, zero the RGB (optional, but cleaner).
    rgb_out = rgb.copy()
    rgb_out[out_alpha == 0] = 0

    out = np.dstack([rgb_out, out_alpha])
    return Image.fromarray(out, mode="RGBA")


def main() -> None:
    if len(sys.argv) < 2:
        print(
            "usage: extract_gpt_sprite.py <src.png> [W H] "
            "(defaults W=23 H=48)",
            file=sys.stderr,
        )
        sys.exit(1)
    src = Path(sys.argv[1])
    logical_w = int(sys.argv[2]) if len(sys.argv) > 2 else 23
    logical_h = int(sys.argv[3]) if len(sys.argv) > 3 else 48

    img = Image.open(src).convert("RGBA")
    arr = np.array(img)
    print(f"Source: {src.name} {img.size}")

    # Find outermost magenta frame. This is the hero box (largest in the
    # template). We also want the slot row below it.
    frame_x0, frame_y0, frame_x1, frame_y1 = detect_magenta_frame(arr)
    print(f"Outermost magenta frame: ({frame_x0}, {frame_y0}) to ({frame_x1}, {frame_y1})")

    # The hero box is the biggest rectangle. To find it, look for the
    # largest rectangular region of magenta frame.
    mag = (arr[:, :, 0] > 180) & (arr[:, :, 1] < 100) & (arr[:, :, 2] > 180)
    # Detect large vertical magenta runs (hero's left and right edges)
    col_sum = mag.sum(axis=0)
    row_sum = mag.sum(axis=1)
    h, w = arr.shape[:2]

    # Hero frame: the two tallest magenta columns (the hero is taller than the slot row).
    # Find runs of consecutive columns with substantial magenta
    strong_cols = col_sum > h * 0.3
    # Group into runs
    runs = []
    in_run = False
    run_start = 0
    for i, s in enumerate(strong_cols):
        if s and not in_run:
            run_start = i
            in_run = True
        elif not s and in_run:
            runs.append((run_start, i - 1, col_sum[run_start:i].sum()))
            in_run = False
    if in_run:
        runs.append((run_start, len(strong_cols) - 1, col_sum[run_start:].sum()))

    # Sort runs by magenta volume (biggest first)
    runs.sort(key=lambda r: -r[2])
    # The two biggest runs are the hero's left+right frame pillars
    hero_runs = sorted(runs[:2], key=lambda r: r[0])
    if len(hero_runs) < 2:
        raise ValueError("Could not identify hero frame columns")
    hero_x0 = hero_runs[0][1] + 1  # inside of left border
    hero_x1 = hero_runs[1][0]       # inside of right border
    print(f"Hero frame pillars: x in {hero_runs[0]}..{hero_runs[1]}, interior x={hero_x0}..{hero_x1}")

    # Hero top/bottom: within those columns, find magenta rows
    hero_band_cols = slice(hero_runs[0][0], hero_runs[1][1] + 1)
    hero_row_mag = mag[:, hero_band_cols].sum(axis=1)
    hero_strong_rows = hero_row_mag > (hero_runs[1][1] - hero_runs[0][0]) * 0.3
    # First run above slot row
    row_runs = []
    in_run = False
    for i, s in enumerate(hero_strong_rows):
        if s and not in_run:
            run_start = i
            in_run = True
        elif not s and in_run:
            row_runs.append((run_start, i - 1))
            in_run = False
    if in_run:
        row_runs.append((run_start, len(hero_strong_rows) - 1))
    print(f"Horizontal magenta bands (within hero columns): {row_runs}")
    if len(row_runs) < 2:
        raise ValueError("Could not find hero top/bottom borders")

    hero_y0 = row_runs[0][1] + 1
    hero_y1 = row_runs[1][0]
    print(f"Hero interior: ({hero_x0},{hero_y0}) to ({hero_x1},{hero_y1}) size {hero_x1-hero_x0}x{hero_y1-hero_y0}")

    # Extract hero
    hero = extract_region(img, (hero_x0, hero_y0, hero_x1, hero_y1), (logical_w, logical_h))

    # Save hero
    out_base = src.parent / src.stem
    hero_path = Path(f"{out_base}_hero_{logical_w}x{logical_h}.png")
    hero.save(hero_path)
    hero_16x = hero.resize((logical_w * 16, logical_h * 16), Image.NEAREST)
    hero_16x.save(f"{out_base}_hero_{logical_w}x{logical_h}_16x.png")
    print(f"\nSaved: {hero_path.name} ({logical_w}x{logical_h})")

    # Extract slot row
    # Slot row is below the hero. Find the next horizontal magenta run below hero_y1.
    slot_row_candidates = [r for r in row_runs if r[0] > hero_y1]
    if len(slot_row_candidates) >= 2:
        slot_top = slot_row_candidates[0][1] + 1
        slot_bot = slot_row_candidates[-1][0]
    else:
        # Use the last two horizontal magenta bands in the image overall
        all_row_runs = row_runs
        slot_top = all_row_runs[-2][1] + 1
        slot_bot = all_row_runs[-1][0]
    print(f"\nSlot row: y={slot_top}..{slot_bot}")

    # Find vertical dividers in the slot row (9 of them for 8 slots)
    slot_col_mag = mag[slot_top:slot_bot, :].sum(axis=0)
    slot_strong_cols = slot_col_mag > (slot_bot - slot_top) * 0.3
    # Group into divider runs
    divider_runs = []
    in_run = False
    for i, s in enumerate(slot_strong_cols):
        if s and not in_run:
            run_start = i
            in_run = True
        elif not s and in_run:
            divider_runs.append((run_start, i - 1))
            in_run = False
    if in_run:
        divider_runs.append((run_start, len(slot_strong_cols) - 1))
    print(f"Slot dividers: {len(divider_runs)} found (want 9 for 8 slots)")

    if len(divider_runs) >= 9:
        # Extract 8 slots, quantize, compose into strip
        strip = Image.new("RGBA", (logical_w * 8, logical_h), (0, 0, 0, 0))
        for i in range(8):
            sx0 = divider_runs[i][1] + 1
            sx1 = divider_runs[i + 1][0]
            slot = extract_region(img, (sx0, slot_top, sx1, slot_bot), (logical_w, logical_h))
            strip.paste(slot, (i * logical_w, 0))
        strip_path = Path(f"{out_base}_strip8.png")
        strip.save(strip_path)
        # 16x preview
        big_strip = strip.resize((logical_w * 8 * 16, logical_h * 16), Image.NEAREST)
        big_strip.save(f"{out_base}_strip8_16x.png")
        print(f"Saved: {strip_path.name} ({logical_w*8}x{logical_h})")
    else:
        print("  (skipping strip extraction — slot dividers not cleanly found)")

    # Summary
    print("\nPalette check (hero):")
    hero_arr = np.array(hero)
    opaque_rgb = hero_arr[hero_arr[:, :, 3] == 255][:, :3]
    unique = np.unique(opaque_rgb, axis=0) if len(opaque_rgb) else np.array([])
    print(f"  {len(unique)} unique colors in 23x48 hero (all should be TCP palette)")
    for c in unique:
        name = next((n for n, v in TCP_PALETTE.items() if v == tuple(c)), "unknown")
        print(f"    RGB=({c[0]:3},{c[1]:3},{c[2]:3}) -> {name}")


if __name__ == "__main__":
    main()
