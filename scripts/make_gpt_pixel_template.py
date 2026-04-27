"""Generate constraint templates for GPT Images 2.0 pixel-art generation.

Two modes:

  small  (default) — tiny physical template matching the sprite pixel count.
                     Good for in-repo reference / schematics. NOT recommended
                     for feeding to GPT: the tool will rescale the canvas at
                     render time, destroying pixel-grid integrity.

  native (--native) — template canvas is sized to match one of GPT's native
                      output resolutions (1024x1024, 1024x1536, 1536x1024,
                      2048x2048, ...). Each logical sprite pixel is
                      represented by an N×N block of real pixels, where N
                      is the largest integer that fits. Includes a
                      calibration strip at the top (1px checker, resolution
                      gauge, N-px checker) for detecting any resampling or
                      smoothing in GPT's output.

Layout (magenta borders on white, transparent background NOT used — AI
needs opaque drawing areas):

    +=============+  <- calibration strip (native mode only, 24 real px tall)
    +==========================+  <- 9px thick magenta border
    |                          |
    |   8W x 8H drawing area   |
    |   (hero reference, 8x)   |
    |                          |
    +==========================+
    |                          |  <- 20px label band
    +--+-----+-----+---...-----+  <- 2px borders, N1 slots of WxH
    |  |     |     |   ...     |
    +--+-----+-----+---...-----+
    ...

CLI:
  python make_gpt_pixel_template.py                              # small canonical set
  python make_gpt_pixel_template.py W H N1 [N2 ...]              # small custom
  python make_gpt_pixel_template.py --native 1024x1024           # native canonical
  python make_gpt_pixel_template.py --native 1024x1024 W H N1    # native custom
  python make_gpt_pixel_template.py --native auto                # native, auto-pick
  python make_gpt_pixel_template.py --native auto W H N1         # native auto, custom

Auto native sizing picks the native resolution that gives the largest
integer scale N for the given logical template.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

MAGENTA = (255, 0, 255, 255)
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)

THICK = 9   # hero box border, logical px
THIN = 2    # slot borders, logical px
LABEL = 20  # label band height, logical px
CALIB_STRIP_H = 24  # calibration strip height, real px (native mode only)

# GPT native output sizes for auto-pick.
#
# Defaults prefer 2048×2048 (gpt-image-2's 2K native, available via Codex
# on ChatGPT Plus and above). 1024-class sizes are kept in the list as
# fallbacks for assets where 2K doesn't fit well, AND are the right target
# if you're generating via the ChatGPT web/mobile UI (still on gpt-image-1
# as of April 2026). Pass --native 1024x1024 (or 1024x1536, 1536x1024)
# explicitly to target the ChatGPT web path.
NATIVE_CANDIDATES: list[tuple[int, int]] = [
    (2048, 2048),
    (1024, 1024),
    (1024, 1536),
    (1536, 1024),
]


def _row_width(n: int, w: int) -> int:
    return n * (w + THIN) + THIN


def _draw_logical_template(w: int, h: int, rows: list[int]) -> Image.Image:
    """Draw the magenta-bordered template at logical (sprite-pixel) dimensions."""
    hero_w = 8 * w + 2 * THICK
    hero_h = 8 * h + 2 * THICK
    row_h = h + 2 * THIN

    max_row_w = max(_row_width(n, w) for n in rows)
    total_w = max(hero_w, max_row_w)
    total_h = hero_h + len(rows) * (LABEL + row_h)

    img = Image.new("RGBA", (total_w, total_h), WHITE)
    draw = ImageDraw.Draw(img)

    # Hero frame (left-aligned)
    draw.rectangle([0, 0, hero_w - 1, THICK - 1], fill=MAGENTA)
    draw.rectangle(
        [0, hero_h - THICK, hero_w - 1, hero_h - 1], fill=MAGENTA
    )
    draw.rectangle([0, 0, THICK - 1, hero_h - 1], fill=MAGENTA)
    draw.rectangle(
        [hero_w - THICK, 0, hero_w - 1, hero_h - 1], fill=MAGENTA
    )

    # Rows
    for i, n in enumerate(rows):
        row_top = hero_h + i * (LABEL + row_h) + LABEL
        row_bottom = row_top + row_h
        row_w_i = _row_width(n, w)

        draw.rectangle(
            [0, row_top, row_w_i - 1, row_top + THIN - 1], fill=MAGENTA
        )
        draw.rectangle(
            [0, row_bottom - THIN, row_w_i - 1, row_bottom - 1], fill=MAGENTA
        )
        for j in range(n + 1):
            x = j * (w + THIN)
            draw.rectangle(
                [x, row_top, x + THIN - 1, row_bottom - 1], fill=MAGENTA
            )

    return img


def _draw_checkerboard(
    draw: ImageDraw.ImageDraw,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    block: int,
) -> None:
    """Checkerboard pattern in [x0, x1) × [y0, y1) with block×block cells."""
    for y in range(y0, y1, block):
        for x in range(x0, x1, block):
            parity = ((x - x0) // block + (y - y0) // block) % 2
            color = BLACK if parity == 0 else WHITE
            draw.rectangle(
                [x, y, min(x + block - 1, x1 - 1), min(y + block - 1, y1 - 1)],
                fill=color,
            )


def _draw_resolution_gauge(
    draw: ImageDraw.ImageDraw,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
) -> None:
    """Horizontal stripes at increasing pixel widths, stacked top to bottom."""
    widths = [1, 2, 3, 4, 6, 8]
    gauge_h = y1 - y0
    stripe_h = max(1, gauge_h // len(widths))

    # Fit as many stripe rows as we can.
    cur_y = y0
    for w_stripe in widths:
        if cur_y + stripe_h > y1:
            break
        for x in range(x0, x1, w_stripe):
            parity = ((x - x0) // w_stripe) % 2
            color = BLACK if parity == 0 else WHITE
            draw.rectangle(
                [x, cur_y, min(x + w_stripe - 1, x1 - 1), cur_y + stripe_h - 1],
                fill=color,
            )
        cur_y += stripe_h


def _draw_calibration_strip(
    canvas: Image.Image, scale_n: int, strip_h: int
) -> None:
    """Draw a 3-patch calibration strip across the top of the canvas.

    Left third:   1-real-pixel checkerboard — detects ANY resampling.
    Middle third: resolution gauge at widths 1, 2, 3, 4, 6, 8 px.
    Right third:  N-real-pixel checkerboard — tests chosen logical-pixel grid.
    """
    draw = ImageDraw.Draw(canvas)
    total_w = canvas.width
    patch_w = total_w // 3

    _draw_checkerboard(draw, 0, 0, patch_w, strip_h, 1)
    _draw_resolution_gauge(draw, patch_w, 0, 2 * patch_w, strip_h)
    _draw_checkerboard(draw, 2 * patch_w, 0, total_w, strip_h, scale_n)

    # 1-px black separator at the bottom of the strip.
    draw.rectangle(
        [0, strip_h - 1, total_w - 1, strip_h - 1], fill=BLACK
    )


def _best_native(
    logical_w: int, logical_h: int
) -> tuple[tuple[int, int], int]:
    """Pick the native size giving the largest integer scale N that fits."""
    best: tuple[int, int] | None = None
    best_n = 0
    for nw, nh in NATIVE_CANDIDATES:
        avail_h = nh - CALIB_STRIP_H
        if logical_w > nw or logical_h > avail_h:
            continue
        n = min(nw // logical_w, avail_h // logical_h)
        if n > best_n:
            best_n = n
            best = (nw, nh)
    if best is None:
        raise ValueError(
            f"Logical template {logical_w}x{logical_h} doesn't fit in any "
            f"candidate native size: {NATIVE_CANDIDATES}"
        )
    return best, best_n


def make_small_template(
    w: int, h: int, rows: list[int], out_path: Path
) -> None:
    img = _draw_logical_template(w, h, rows)
    img.save(out_path)
    print(f"{out_path.name}: {img.width}x{img.height}")


def make_native_template(
    w: int,
    h: int,
    rows: list[int],
    native_w: int,
    native_h: int,
    out_path: Path,
) -> int:
    """Create a GPT-native-sized template. Returns the scale factor N used."""
    logical = _draw_logical_template(w, h, rows)
    logical_w, logical_h = logical.size

    avail_h = native_h - CALIB_STRIP_H
    n_w = native_w // logical_w
    n_h = avail_h // logical_h
    scale_n = min(n_w, n_h)

    if scale_n < 1:
        raise ValueError(
            f"Logical template {logical_w}x{logical_h} + {CALIB_STRIP_H}px "
            f"calibration strip doesn't fit in native {native_w}x{native_h}. "
            f"Try a larger native size (e.g. 2048x2048) or --native auto."
        )

    scaled_w = logical_w * scale_n
    scaled_h = logical_h * scale_n
    scaled = logical.resize((scaled_w, scaled_h), Image.NEAREST)

    canvas = Image.new("RGBA", (native_w, native_h), WHITE)
    _draw_calibration_strip(canvas, scale_n, CALIB_STRIP_H)

    x_off = (native_w - scaled_w) // 2
    y_off = CALIB_STRIP_H + (avail_h - scaled_h) // 2
    canvas.paste(scaled, (x_off, y_off))

    canvas.save(out_path)
    print(
        f"{out_path.name}: {native_w}x{native_h} "
        f"(logical {logical_w}x{logical_h}, N={scale_n}, "
        f"offset ({x_off},{y_off}))"
    )
    return scale_n


def _filename(
    w: int,
    h: int,
    rows: list[int],
    native: tuple[int, int] | None,
) -> str:
    base = f"gpt_pixel_template_{w}x{h}"
    if rows != [8]:
        base += "_" + "-".join(str(n) for n in rows)
    if native:
        base += f"_native{native[0]}x{native[1]}"
    return base + ".png"


def _parse_native(s: str) -> tuple[int, int] | str:
    if s == "auto":
        return "auto"
    try:
        a, b = s.lower().split("x")
        return int(a), int(b)
    except Exception:
        raise argparse.ArgumentTypeError(
            f"--native must be WxH or 'auto', got {s!r}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate GPT Images 2.0 pixel-art constraint templates."
    )
    parser.add_argument(
        "--native",
        type=_parse_native,
        default=None,
        help="Native GPT output size (e.g. 1024x1024 or 'auto').",
    )
    parser.add_argument(
        "args", nargs="*", help="Custom template: W H N1 [N2 ...]"
    )
    parsed = parser.parse_args()

    out_dir = Path(__file__).resolve().parent.parent.parent / "game_assets"
    out_dir.mkdir(exist_ok=True)

    def _emit(w: int, h: int, rows: list[int]) -> None:
        if parsed.native is None:
            out_path = out_dir / _filename(w, h, rows, None)
            make_small_template(w, h, rows, out_path)
            return

        if parsed.native == "auto":
            logical = _draw_logical_template(w, h, rows)
            native, _ = _best_native(logical.width, logical.height)
        else:
            native = parsed.native  # type: ignore[assignment]

        out_path = out_dir / _filename(w, h, rows, native)
        make_native_template(w, h, rows, native[0], native[1], out_path)

    if parsed.args:
        if len(parsed.args) < 3:
            print(
                "usage: make_gpt_pixel_template.py [--native WxH|auto] W H N1 [N2 ...]",
                file=sys.stderr,
            )
            sys.exit(1)
        w = int(parsed.args[0])
        h = int(parsed.args[1])
        rows = [int(n) for n in parsed.args[2:]]
        _emit(w, h, rows)
        return

    canonical: list[tuple[int, int, list[int]]] = [
        (32, 32, [8]),
        (40, 40, [8]),
        (23, 8, [8]),
        (23, 48, [8]),
    ]
    for w, h, rows in canonical:
        _emit(w, h, rows)


if __name__ == "__main__":
    main()
