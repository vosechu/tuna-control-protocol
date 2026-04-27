"""Add a 1-logical-pixel dark outline to a transparent pixel-art sprite.

Replaces the outermost opaque pixel of each silhouette with Den Brown
(#2E2018 — TCP's palette "black"). The outline lives *inside* the
existing canvas, so slot dimensions stay fixed at W×H (important for
strip8 layouts where every frame must keep the same footprint).

A pixel becomes outline if it is currently opaque AND any 4-neighbor
(up/down/left/right) is transparent or off-canvas. Diagonal neighbors
don't count — that preserves sharper silhouette corners.

Usage:
  python3 outline_sprite.py <in.png> <out.png> [--frame-width N]

If --frame-width is given, treat the input as a horizontal strip of
frames each frame-width wide; outline each frame independently so the
outline doesn't bleed across frame boundaries.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

DEN_BROWN = (46, 32, 24)  # #2E2018


def outline_frame(rgba: np.ndarray) -> np.ndarray:
    """Return a copy of rgba (H,W,4) with outermost opaque pixels set to Den Brown."""
    h, w = rgba.shape[:2]
    alpha = rgba[:, :, 3]
    opaque = alpha >= 128

    # Neighbor-transparent masks: True where the 4-neighbor is transparent/off-canvas.
    neighbor_transparent = np.zeros_like(opaque)
    # Up
    up = np.ones_like(opaque)
    up[1:, :] = ~opaque[:-1, :]
    neighbor_transparent |= up
    # Down
    down = np.ones_like(opaque)
    down[:-1, :] = ~opaque[1:, :]
    neighbor_transparent |= down
    # Left
    left = np.ones_like(opaque)
    left[:, 1:] = ~opaque[:, :-1]
    neighbor_transparent |= left
    # Right
    right = np.ones_like(opaque)
    right[:, :-1] = ~opaque[:, 1:]
    neighbor_transparent |= right

    outline_mask = opaque & neighbor_transparent

    out = rgba.copy()
    out[outline_mask, 0] = DEN_BROWN[0]
    out[outline_mask, 1] = DEN_BROWN[1]
    out[outline_mask, 2] = DEN_BROWN[2]
    out[outline_mask, 3] = 255
    return out


def outline_image(img: Image.Image, frame_width: int | None = None) -> Image.Image:
    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]

    if frame_width is None or frame_width == w:
        out_arr = outline_frame(arr)
    else:
        if w % frame_width != 0:
            raise ValueError(f"image width {w} not divisible by frame_width {frame_width}")
        n_frames = w // frame_width
        out_arr = arr.copy()
        for i in range(n_frames):
            x0 = i * frame_width
            x1 = x0 + frame_width
            out_arr[:, x0:x1, :] = outline_frame(arr[:, x0:x1, :])

    return Image.fromarray(out_arr, mode="RGBA")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("src", type=Path)
    parser.add_argument("dst", type=Path)
    parser.add_argument("--frame-width", type=int, default=None,
                        help="Frame width for strip inputs; outline each frame independently.")
    parser.add_argument("--preview-scale", type=int, default=16,
                        help="Also save a nearest-neighbor upscaled preview at this scale (0 to skip).")
    args = parser.parse_args()

    img = Image.open(args.src)
    outlined = outline_image(img, args.frame_width)
    outlined.save(args.dst)
    print(f"Saved: {args.dst.name} ({outlined.size[0]}x{outlined.size[1]})")

    if args.preview_scale and args.preview_scale > 1:
        preview = outlined.resize(
            (outlined.size[0] * args.preview_scale, outlined.size[1] * args.preview_scale),
            Image.NEAREST,
        )
        preview_path = args.dst.with_name(
            f"{args.dst.stem}_{args.preview_scale}x{args.dst.suffix}"
        )
        preview.save(preview_path)
        print(f"Saved: {preview_path.name} ({preview.size[0]}x{preview.size[1]})")


if __name__ == "__main__":
    main()
