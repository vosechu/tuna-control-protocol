---
description: Use Python/PIL to empirically measure sprite pixel layouts when debugging placement/alignment issues. Prevents guessing at border offsets or tile regions.
---

# Measure Sprite Pixels

## When to Use This Skill

When a sprite or tile appears mispositioned and the fix depends on knowing the exact pixel layout (border thickness, transparent padding, which row/column contains which content). Don't guess — measure.

Common triggers:
- "This looks off by a few pixels"
- Arguing about whether a sprite frame has padding
- Adding a new constant like `RACK_FRAME_PX` or a sprite offset
- Validating a tileset's cell layout against its .md documentation

## Steps

### 1. Full-tile content survey
```python
python3 -c "
from PIL import Image
img = Image.open('path/to/sprite.png')
print(f'Size: {img.size}')
# For a tile atlas, walk each cell
for row in range(HEIGHT // 16):
    for col in range(WIDTH // 16):
        x, y = col*16, row*16
        opaque = 0
        colors = set()
        for dy in range(16):
            for dx in range(16):
                px = img.load()[x+dx, y+dy]
                if px[3] != 0:
                    opaque += 1
                    colors.add((px[0]//32, px[1]//32, px[2]//32))
        if opaque:
            print(f'({col},{row}): {opaque}/256 opaque, {len(colors)} color buckets')
"
```

### 2. Per-row pixel map (find border thickness)
Produces a visual map showing which rows within a tile have opaque pixels:
```python
python3 -c "
from PIL import Image
img = Image.open('path.png')
x, y = COL*16, ROW*16
for dy in range(16):
    line = []
    for dx in range(16):
        px = img.load()[x+dx, y+dy]
        if px[3] == 0:
            line.append('.')
        elif (px[0]+px[1]+px[2]) < 30:
            line.append('K')  # near-black
        elif (px[0]+px[1]+px[2]) > 400:
            line.append('H')  # bright
        else:
            line.append('M')  # mid
    print(f'y={dy:2d}: {\"\".join(line)}')
"
```

### 3. Extract tiles to a scaled strip for visual inspection
```python
python3 -c "
from PIL import Image
img = Image.open('path.png')
tiles = [(col, row), ...]  # list of cells of interest
w = 16 * 8  # 8x scale
strip = Image.new('RGBA', (w * len(tiles), w), (40,40,60,255))
for i, (c, r) in enumerate(tiles):
    t = img.crop((c*16, r*16, c*16+16, r*16+16))
    t = t.resize((w, w), Image.NEAREST)
    strip.paste(t, (i*w, 0), t)
strip.save('/tmp/strip.png')
"
```
Then `Read /tmp/strip.png` to view.

## Common Pitfalls

- **Don't rely on the docs** (`.md` companion files can drift). Measure the actual PNG.
- **Transparent padding is invisible but counts** — a tile can have 8px of transparent pixels above its visible content, pushing the "real" border offset up. Our `RACK_FRAME_PX = 12` = 8px transparent padding + 4px visible frame.
- **Center-pixel sampling misses content.** `pixels[x+8, y+8]` reports a tile as "empty" if the content is at the edges (like (5,4) with 16 black pixels only at y=15). Always scan the full 16×16.
- **If a tile you're painting doesn't appear**, check the TileSet resource (`.tres`). Atlas coordinates must be registered (`col:row/0 = 0` line) or `set_cell` silently no-ops.
