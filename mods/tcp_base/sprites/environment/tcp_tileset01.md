# tcp_tileset01.png — tile cell map

Atlas: 192x96 pixels, 12 columns x 6 rows of 16x16 tiles.
Referenced by `tcp_environment.tres` (Godot TileSet) and
`engine/environment/tile_painter.gd` (via `Vector2i(col, row)` constants).

Rows are indexed 0 at the top, columns 0 at the left.

| Tile | Col 0 | Col 1 | Col 2 | Col 3 | Col 4 | Col 5 | Col 6 | Col 7 | Col 8 | Col 9 | Col 10 | Col 11 |
|------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|--------|--------|
| Row 0 | Ceiling | Wall | Wall | Wall | Cable A L | Cable A R | Cable B L | Cable B R | Cable C L | Cable C R | Cable D R | Cable E (U) |
| Row 1 | Wall | Wall | Wall | Wall | -- | -- | Cable B L bot | Cable B R bot | Cable C L bot | Cable C R bot | Cable D R bot | -- |
| Row 2 | Wall | Wall | Wall | Wall | Orange flowers | Yellow/orange flowers | Leaves | Grass | Orange blossoms | Single blossom | Little grass | -- |
| Row 3 | Baseboard A | Baseboard B | Baseboard C | Wall (lower) | Ground w/ plants | Ground w/ plants | Ground w/ plants | Ground w/ plants | Ground w/ plants | Ground w/ plants | Ground w/ plants | -- |
| Row 4 | Dark edge | -- | -- | -- | Small plants | Ground (bare) | Ground (bare) | Ground (bare) | -- | -- | -- | -- |
| Row 5 | -- | -- | -- | -- | Substrate | Substrate | Substrate | Substrate | Underfloor | Interfloor transition | -- | -- |

`--` = transparent / not registered in the TileSet.

## Purpose groups

- **Wall background:** cols 0-3, rows 0-2 (4x3 block of wall tiles, tiled behind racks)
- **Ceiling corner:** (0, 0) -- only used at the leftmost edge of bay 0
- **Wall-to-ground transition:** (3, 3) -- placed at y=19 (one row above baseboard)
- **Baseboard:** (0, 3), (1, 3), (2, 3) -- horizontal strip at y=20
- **Substrate:** (4, 5)-(7, 5) -- base ground layer, painted on every floor tile. (7, 5) is base (~80%), (4, 5)-(6, 5) are variants (~20%).
- **Surface overlay:** painted on top of substrate. (5, 4) is base edge-cap (~80%, mostly transparent). Variants: (4, 3)-(10, 3) (grass/flowers) and (4, 4) (small plants) for ~20% decoration.
- **Ground (bare):** (5, 4), (6, 4), (7, 4) -- mostly-transparent tiles with a dark top edge; (5, 4) used as the default surface overlay.
- **Hanging cables (5 variants, A-E):** cols 4-11 of row 0, some with "bottom" halves in row 1
- **Decorative plants/flowers:** scattered across row 2 for wall-level reclamation aesthetic
- **Small plants:** (4, 4) -- used on floor strip of peek bays (abandoned-looking)

## Painter usage

See `engine/environment/tile_painter.gd`:
- `ATLAS_CEILING = Vector2i(0, 0)` -- leftmost cell of bay 0's ceiling row
- `ATLAS_WALL = Vector2i(1, 0)` -- tiled across ceiling and wall fill
- `ATLAS_WALL_LOWER = Vector2i(3, 3)` -- y=19 transition row
- `ATLAS_BASEBOARD_A/B/C = Vector2i(0, 3)/(1, 3)/(2, 3)` -- y=20
- `ATLAS_SUBSTRATE_BASE = Vector2i(7, 5)` -- majority substrate tile
- `ATLAS_SUBSTRATE_VARIANTS = [(4,5), (5,5), (6,5)]` -- substrate variation (~20%)
- `ATLAS_SURFACE_BASE = Vector2i(5, 4)` -- majority edge-cap overlay
- `ATLAS_SURFACE_VARIANTS = [(4,3)..(10,3), (4,4)]` -- plants/flowers overlay (~20%)
- `ATLAS_CABLE_A_L = Vector2i(4, 0)` / `ATLAS_CABLE_A_R = Vector2i(5, 0)` -- cable A (first cable)
- `ATLAS_PLANTS_SMALL = Vector2i(4, 4)` -- abandonment decor on peek bay floors

## Updating this file

When the artist ships a new `tcp_tileset01.png`, update:
1. This markdown table to match the new tile layout
2. `tcp_environment.tres` to register the new non-transparent cells
3. `engine/environment/tile_painter.gd` constants if positions changed
