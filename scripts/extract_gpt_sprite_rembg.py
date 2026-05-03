"""Extract GPT-generated sprites using rembg for background removal.

Alternative to extract_gpt_sprite.py's flood-fill approach. This script
runs each cropped region through rembg (a U²-Net segmentation model)
at full source resolution BEFORE downscaling, which handles interior
holes in the silhouette that a corner-based flood-fill can't reach.

Pipeline per region (hero + 8 slots):
  1. Detect magenta frame to find region bounds.
  2. Crop the region's interior at full source resolution.
  3. rembg → transparent background.
  4. BOX-average downscale to logical W×H.
  5. Quantize RGB to the nearest TCP palette color (transparent pixels untouched).
  6. Save.

Usage:
  python3 extract_gpt_sprite_rembg.py <src.png> [W H]
"""

from __future__ import annotations

import sys
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image

# Reuse palette + magenta detection from the flood-fill sibling.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_gpt_sprite import TCP_PALETTE, PALETTE_ARR, quantize_to_palette  # noqa: E402

try:
    from rembg import remove as rembg_remove
except ImportError:
    print("rembg not installed. Run: asdf exec pip install rembg", file=sys.stderr)
    sys.exit(1)


def detect_layout(arr: np.ndarray) -> tuple[tuple[int, int, int, int], list[tuple[int, int, int, int]], tuple[int, int]]:
    """Return (hero_bbox, [slot_bbox...], (slot_top, slot_bottom)) in source coords."""
    mag = (arr[:, :, 0] > 180) & (arr[:, :, 1] < 100) & (arr[:, :, 2] > 180)
    h, w = arr.shape[:2]

    # Strong vertical runs → hero frame columns
    col_sum = mag.sum(axis=0)
    strong_cols = col_sum > h * 0.3

    def group_runs(flags):
        runs = []
        in_run = False
        start = 0
        for i, f in enumerate(flags):
            if f and not in_run:
                start = i
                in_run = True
            elif not f and in_run:
                runs.append((start, i - 1))
                in_run = False
        if in_run:
            runs.append((start, len(flags) - 1))
        return runs

    col_runs = group_runs(strong_cols)
    # Hero: two biggest vertical runs by magenta sum
    col_runs_by_vol = sorted(col_runs, key=lambda r: -col_sum[r[0]:r[1]+1].sum())
    hero_col_pair = sorted(col_runs_by_vol[:2], key=lambda r: r[0])
    hero_x0 = hero_col_pair[0][1] + 1
    hero_x1 = hero_col_pair[1][0]

    row_sum_within_hero = mag[:, hero_col_pair[0][0]:hero_col_pair[1][1]+1].sum(axis=1)
    band_w = hero_col_pair[1][1] - hero_col_pair[0][0]
    strong_rows = row_sum_within_hero > band_w * 0.3
    row_runs = group_runs(strong_rows)
    # First/second horizontal bands = hero top/bottom
    hero_y0 = row_runs[0][1] + 1
    hero_y1 = row_runs[1][0]

    # Slot row: below hero. Find the next two horizontal bands after hero bottom.
    slot_candidates = [r for r in row_runs if r[0] > hero_y1]
    slot_top = slot_candidates[0][1] + 1
    slot_bottom = slot_candidates[-1][0]

    # Vertical dividers in slot row → 9 runs for 8 slots
    slot_col_sum = mag[slot_top:slot_bottom, :].sum(axis=0)
    strong_slot_cols = slot_col_sum > (slot_bottom - slot_top) * 0.3
    slot_col_runs = group_runs(strong_slot_cols)
    if len(slot_col_runs) < 9:
        raise ValueError(f"Expected 9 slot dividers, found {len(slot_col_runs)}")

    slot_bboxes = []
    for i in range(8):
        sx0 = slot_col_runs[i][1] + 1
        sx1 = slot_col_runs[i + 1][0]
        slot_bboxes.append((sx0, slot_top, sx1, slot_bottom))

    return (hero_x0, hero_y0, hero_x1, hero_y1), slot_bboxes, (slot_top, slot_bottom)


def rembg_process(pil_img: Image.Image) -> Image.Image:
    """Run rembg on a PIL image, returning an RGBA PIL image with transparent background."""
    buf = BytesIO()
    pil_img.save(buf, format="PNG")
    out_bytes = rembg_remove(buf.getvalue())
    return Image.open(BytesIO(out_bytes)).convert("RGBA")


def extract_with_rembg(
    src_img: Image.Image,
    bbox: tuple[int, int, int, int],
    logical_size: tuple[int, int],
) -> Image.Image:
    """Crop → rembg → downscale (BOX) → palette-quantize opaque pixels."""
    crop = src_img.crop(bbox)
    rembg_out = rembg_process(crop)
    small = rembg_out.resize(logical_size, Image.BOX).convert("RGBA")
    arr = np.array(small)
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3]

    # Binarize alpha: >=128 → 255, else 0
    alpha_bin = np.where(alpha >= 128, 255, 0).astype(np.uint8)

    # Quantize only the opaque pixels to TCP palette
    opaque_mask = alpha_bin == 255
    if opaque_mask.any():
        rgb_flat = rgb[opaque_mask]
        quantized = quantize_to_palette(rgb_flat)
        rgb = rgb.copy()
        rgb[opaque_mask] = quantized

    # Zero RGB of transparent pixels for clean PNG
    rgb_out = rgb.copy()
    rgb_out[alpha_bin == 0] = 0

    out = np.dstack([rgb_out, alpha_bin])
    return Image.fromarray(out, mode="RGBA")


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: extract_gpt_sprite_rembg.py <src.png> [W H]", file=sys.stderr)
        sys.exit(1)
    src = Path(sys.argv[1])
    logical_w = int(sys.argv[2]) if len(sys.argv) > 2 else 23
    logical_h = int(sys.argv[3]) if len(sys.argv) > 3 else 48

    img = Image.open(src).convert("RGBA")
    arr = np.array(img)
    print(f"Source: {src.name} {img.size}")

    hero_bbox, slot_bboxes, (slot_top, slot_bottom) = detect_layout(arr)
    print(f"Hero bbox: {hero_bbox}")
    print(f"Slot row y=[{slot_top}, {slot_bottom}], 8 slots detected")

    out_base = src.parent / f"{src.stem}_rembg"

    print("\nRunning rembg + quantize on hero…")
    hero = extract_with_rembg(img, hero_bbox, (logical_w, logical_h))
    hero_path = Path(f"{out_base}_hero_{logical_w}x{logical_h}.png")
    hero.save(hero_path)
    hero.resize((logical_w * 16, logical_h * 16), Image.NEAREST).save(
        f"{out_base}_hero_{logical_w}x{logical_h}_16x.png"
    )
    print(f"  saved {hero_path.name}")

    print("\nRunning rembg + quantize on 8 slots…")
    strip = Image.new("RGBA", (logical_w * 8, logical_h), (0, 0, 0, 0))
    for i, bbox in enumerate(slot_bboxes, 1):
        slot = extract_with_rembg(img, bbox, (logical_w, logical_h))
        strip.paste(slot, ((i - 1) * logical_w, 0))
        print(f"  slot {i} done")

    strip_path = Path(f"{out_base}_strip8.png")
    strip.save(strip_path)
    strip.resize((logical_w * 8 * 16, logical_h * 16), Image.NEAREST).save(
        f"{out_base}_strip8_16x.png"
    )
    print(f"\nSaved: {strip_path.name}")

    # Summary
    hero_arr = np.array(hero)
    opaque_rgb = hero_arr[hero_arr[:, :, 3] == 255][:, :3]
    unique = np.unique(opaque_rgb, axis=0) if len(opaque_rgb) else np.array([])
    print(f"\nHero palette: {len(unique)} unique colors")
    for c in unique:
        name = next((n for n, v in TCP_PALETTE.items() if v == tuple(c)), "unknown")
        print(f"  RGB=({c[0]:3},{c[1]:3},{c[2]:3}) -> {name}")


if __name__ == "__main__":
    main()
