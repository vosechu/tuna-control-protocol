---
description: Generate pixel art sprites using Python/Pillow that match TCP's canonical art style (chibi, limited palette, clean outlines)
---

# Generate Pixel Art Sprites

## When to Use This Skill

When you need placeholder sprites for TCP objects, infrastructure, or environment tiles that match the canonical art style defined in the Smudge agent file (`.claude/agents/game-artist.md`).

## Prerequisites

- Python 3 with Pillow (`pip install Pillow`)
- Read the "Canonical Art Style" section in `.claude/agents/game-artist.md` for style reference

## Technique: Silhouette Stamp Method

For clean, uniform outlines at any thickness:

1. **Draw the colored shape** on a transparent canvas with padding (outline_width px on each side)
2. **Create a black silhouette** from the alpha channel
3. **Stamp the silhouette** at all 8 directional offsets (N, S, E, W, NE, NW, SE, SW) by 1px per outline pixel
4. **Paste the colored shape** on top at the original position

```python
def stamp_outline(canvas, shape_img, ox=0, oy=0):
    alpha = shape_img.split()[3]
    black_ver = Image.new('RGBA', shape_img.size, (0, 0, 0, 255))
    black_ver.putalpha(alpha)
    for dx, dy in [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]:
        canvas.paste(black_ver, (ox+dx, oy+dy), black_ver)
    canvas.paste(shape_img, (ox, oy), shape_img)
```

**Do NOT** draw two concentric outlines (rectangle at [x,y] and [x-1,y-1]) -- this creates double-line artifacts.

## Outline Weight

- All sprites render at 1x scale (no scaling)
- **All sprites use 1px native outlines** (via stamp method)
- Add `pad = 1` pixel to canvas dimensions for outline bleed

## Palette

Use the TCP cold datacenter palette from `art-direction.md`:

```python
SLATE_VOID = (26, 30, 46, 255)       # Deepest shadows
CABLE_GRAY = (59, 65, 87, 255)       # Primary surface
DUST_BLUE = (91, 107, 138, 255)      # Secondary surface
INDICATOR_TEAL = (74, 155, 155, 255) # Active electronics
BREATH_WHITE = (212, 218, 232, 255)  # Highlights
```

## Scale Reference

At current spec (7px/U), relative to 40x40px cats:

| Object | Approximate Size | Notes |
|---|---|---|
| 2U server | 76x20 + pad | Wider than cat, much shorter |
| Cardboard box | 44x24 + pad | Cat-sized, shallow |
| Clothes pile | 44x28 + pad | Wide, low mound |
| Tuna can | 16x12 + pad | Small item |
| Rack frame | 76x294 + pad | 42U tall |
| Floor tile | 80x40 | Tileable, no outline stamp needed |

## Occupiable Objects

Split into `_back.png` and `_front.png` for z-layered occupancy:

- **Back**: What's behind the occupant (back wall of box, rear cushions of pile)
- **Front**: What's in front (front wall/flaps, front cushions)
- **Single piece**: Composite of both for unoccupied display
- Cats anchor high (rest ON TOP), ferrets anchor low (burrow IN)

## Common Issues

- Godot caches textures -- run `godot --headless --import` after replacing PNGs
- Changing sprite dimensions may require updating `.import` files
- Keep `texture_filter: 0` (Nearest) in import settings for pixel art
