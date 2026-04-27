"""Pre-fill GPT pixel templates with the first frame of each canonical asset.

For each configured asset, generates a template at a GPT-native output size
(1024×1024, 1024×1536, etc.) and pastes frame 0 of the existing sprite
strip into both the hero box (8× scale) and slot 1 (1× scale). Slots 2-8
are left blank for GPT to fill.

Native mode is the default and the recommended mode for feeding GPT Images
2.0 — it matches GPT's native output resolution so no resampling happens
when GPT renders the template. A calibration strip at the top of each
template lets you detect whether GPT preserved pixel integrity.

HUM device has no source sprite; its template is blank save for the
calibration strip and border layout.

Output: ../game_assets/gpt_templates/{asset_name}/template_prefilled.png
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from make_gpt_pixel_template import (
    CALIB_STRIP_H,
    LABEL,
    THICK,
    THIN,
    _best_native,
    _draw_calibration_strip,
    _draw_logical_template,
)


@dataclass
class Asset:
    name: str
    source: str | None  # path to sprite strip (None = blank, e.g. HUM device)
    frame_size: tuple[int, int]  # (w, h) per logical sprite pixel
    rows: list[int]  # slot row sizes (default [8])
    native: tuple[int, int] | str  # (W, H) or "auto"


ASSETS: list[Asset] = [
    Asset(
        name="cat01_idle",
        source="mods/tcp_cats/sprites/cat01_idle_strip8.png",
        frame_size=(40, 40),
        rows=[8],
        native="auto",
    ),
    Asset(
        name="kitten01_idle",
        source="mods/tcp_cats/sprites/kitten01_idle_strip8.png",
        frame_size=(32, 32),
        rows=[8],
        native="auto",
    ),
    Asset(
        name="ferret_idle",
        source="mods/tcp_ferrets/sprites/lilotter_idle_strip8.png",
        frame_size=(32, 32),
        rows=[8],
        native="auto",
    ),
    Asset(
        name="hum_device",
        source=None,
        frame_size=(23, 48),
        rows=[8],
        native="auto",
    ),
]


def _strip_frame_count(path: Path) -> int:
    m = re.search(r"_strip(\d+)\.png$", path.name)
    return int(m.group(1)) if m else 1


@dataclass
class Layout:
    """Pixel-space positions on the native canvas."""

    native_w: int
    native_h: int
    scale_n: int
    template_offset: tuple[int, int]  # (x, y) of logical template origin
    hero_interior: tuple[int, int]  # (x, y) of hero's drawing area
    hero_interior_size: tuple[int, int]  # (w, h)
    slot1: tuple[int, int]  # (x, y) of slot 1 drawing area
    slot1_size: tuple[int, int]  # (w, h)


def _compute_layout(
    w: int, h: int, rows: list[int], native_w: int, native_h: int
) -> Layout:
    logical = _draw_logical_template(w, h, rows)
    logical_w, logical_h = logical.size

    avail_h = native_h - CALIB_STRIP_H
    scale_n = min(native_w // logical_w, avail_h // logical_h)
    if scale_n < 1:
        raise ValueError(
            f"Template {logical_w}x{logical_h} doesn't fit in "
            f"{native_w}x{native_h} native."
        )

    scaled_w = logical_w * scale_n
    scaled_h = logical_h * scale_n
    x_off = (native_w - scaled_w) // 2
    y_off = CALIB_STRIP_H + (avail_h - scaled_h) // 2

    # Hero interior (after THICK border) in logical coords: (THICK, THICK)
    hero_interior_logical = (THICK, THICK)
    hero_interior_size_logical = (8 * w, 8 * h)

    # Slot 1 in logical coords: row starts at hero_h + LABEL, slot 1 is after
    # the 2px top border and 2px left border.
    hero_h = 8 * h + 2 * THICK
    slot1_logical_y = hero_h + LABEL + THIN
    slot1_logical_x = THIN

    return Layout(
        native_w=native_w,
        native_h=native_h,
        scale_n=scale_n,
        template_offset=(x_off, y_off),
        hero_interior=(
            x_off + hero_interior_logical[0] * scale_n,
            y_off + hero_interior_logical[1] * scale_n,
        ),
        hero_interior_size=(
            hero_interior_size_logical[0] * scale_n,
            hero_interior_size_logical[1] * scale_n,
        ),
        slot1=(
            x_off + slot1_logical_x * scale_n,
            y_off + slot1_logical_y * scale_n,
        ),
        slot1_size=(w * scale_n, h * scale_n),
    )


def _build_native_canvas(
    w: int, h: int, rows: list[int], native_w: int, native_h: int
) -> tuple[Image.Image, Layout]:
    layout = _compute_layout(w, h, rows, native_w, native_h)
    logical = _draw_logical_template(w, h, rows)
    scaled = logical.resize(
        (logical.width * layout.scale_n, logical.height * layout.scale_n),
        Image.NEAREST,
    )

    canvas = Image.new("RGBA", (native_w, native_h), (255, 255, 255, 255))
    _draw_calibration_strip(canvas, layout.scale_n, CALIB_STRIP_H)
    canvas.paste(scaled, layout.template_offset)
    return canvas, layout


def prefill(asset: Asset, repo_root: Path, out_dir: Path) -> Path:
    if isinstance(asset.native, str):  # "auto"
        logical = _draw_logical_template(
            asset.frame_size[0], asset.frame_size[1], asset.rows
        )
        native, _ = _best_native(logical.width, logical.height)
    else:
        native = asset.native

    canvas, layout = _build_native_canvas(
        asset.frame_size[0],
        asset.frame_size[1],
        asset.rows,
        native[0],
        native[1],
    )

    asset_out = out_dir / asset.name
    asset_out.mkdir(parents=True, exist_ok=True)
    out_path = asset_out / "template_prefilled.png"

    if asset.source is None:
        canvas.save(out_path)
        print(
            f"{asset.name}: {native[0]}x{native[1]} blank "
            f"(N={layout.scale_n})"
        )
        return out_path

    source_path = repo_root / asset.source
    sheet = Image.open(source_path).convert("RGBA")
    fw, fh = asset.frame_size
    frames = _strip_frame_count(source_path)
    expected_w = fw * frames
    if sheet.width != expected_w or sheet.height != fh:
        raise ValueError(
            f"{source_path.name}: expected {expected_w}x{fh} "
            f"(frames={frames}, frame_size={fw}x{fh}), got "
            f"{sheet.width}x{sheet.height}"
        )

    frame0 = sheet.crop((0, 0, fw, fh))

    # Paste into hero interior at 8x scale × N.
    hero_scaled = frame0.resize(layout.hero_interior_size, Image.NEAREST)
    canvas.paste(hero_scaled, layout.hero_interior, hero_scaled)

    # Paste into slot 1 at 1x × N.
    slot1_scaled = frame0.resize(layout.slot1_size, Image.NEAREST)
    canvas.paste(slot1_scaled, layout.slot1, slot1_scaled)

    canvas.save(out_path)
    print(
        f"{asset.name}: {native[0]}x{native[1]} (N={layout.scale_n}, "
        f"frame0 embedded at hero={layout.hero_interior} "
        f"slot1={layout.slot1})"
    )
    return out_path


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    out_dir = repo_root.parent / "game_assets" / "gpt_templates"
    out_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(repo_root)

    for asset in ASSETS:
        prefill(asset, repo_root, out_dir)


if __name__ == "__main__":
    main()
