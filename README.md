# HexGrid for Godot 4

A single-file 2D hexagon grid for Godot **4.4 or newer**. One `Node2D` class covers map storage, coordinate math, pathfinding, field of view, rendering and mouse input. All the math is `static`, so you can also use it without a node.

The algorithms follow Red Blob Games' [*Hexagonal Grids*](https://www.redblobgames.com/grids/hexagons/): axial coordinates for storage, cube coordinates for math, offset and doubled coordinates for conversions.

## Contents

- [Features](#features)
- [Requirements and installation](#requirements-and-installation)
- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
- [Configuration](#configuration)
- [Generating maps](#generating-maps)
- [Working with cells](#working-with-cells)
- [Coordinates and pixels](#coordinates-and-pixels)
- [Neighbors, ranges and lines](#neighbors-ranges-and-lines)
- [Rotation, reflection and wraparound](#rotation-reflection-and-wraparound)
- [Pathfinding and field of view](#pathfinding-and-field-of-view)
- [Rendering, input and signals](#rendering-input-and-signals)
- [Recipes](#recipes)
- [Using the math without a node](#using-the-math-without-a-node)
- [Performance](#performance)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [API reference](#api-reference)
- [Credits](#credits)

---

## Features

| Area | What you get |
|---|---|
| Storage | Axial `Vector2i` keys in a typed `Dictionary`. Any shape, including holes and islands. |
| Orientation | Pointy-top or flat-top, switchable at runtime. |
| Shapes | Hexagon, rectangle, rhombus and triangle generators, or your own coordinate list. |
| Coordinate systems | Axial, cube, offset (odd-r, even-r, odd-q, even-q), doubled-width and doubled-height, with conversions. |
| Geometry | Neighbors, diagonals, distance, lines, ranges, range intersection, rings, spirals, rotation, reflection. |
| Pixel math | Hex to pixel, pixel to hex (cube rounding), corner polygons, map bounds. |
| Gameplay | A\* with variable move costs, Dijkstra movement range, line-of-sight field of view. |
| Cell data | `walkable`, `move_cost`, `blocks_sight`, `color` and a free-form `data` dictionary per cell. |
| Rendering | Built-in `_draw()` renderer: fills, outlines, hover, selection, highlights, coordinate labels. |
| Input | Hover and click detection as signals. |

---

## Requirements and installation

- **Godot 4.4 or newer.** The class uses typed dictionaries (`Dictionary[Vector2i, HexCell]`), which were added in 4.4.
- The code is fully statically typed, with explicit types and no `:=` inference.

Copy `hex_grid.gd` into your project (for example `res://scripts/hex_grid.gd`). It declares `class_name HexGrid`, so Godot registers it automatically. No autoload, plugin or imported resource is needed. If it doesn't show up in the *Add Node* dialog, reload the project.

---

## Quick start

### In the editor

1. **Add Node → HexGrid** (it appears under `Node2D`).
2. In the Inspector, choose a **Shape**, **Radius** (or **Grid Width/Height**) and **Hex Size**.
3. Run the scene. With `auto_generate` on (the default), the map is generated in `_ready()`.

### From code

```gdscript
extends Node2D

var grid: HexGrid


func _ready() -> void:
    grid = HexGrid.new()
    grid.shape = HexGrid.Shape.RECTANGLE
    grid.grid_width = 16
    grid.grid_height = 10
    grid.hex_size = 28.0
    grid.show_coords = true
    add_child(grid)  # generates the map in _ready()

    grid.hex_clicked.connect(_on_hex_clicked)


func _on_hex_clicked(coord: Vector2i, button: int) -> void:
    print("Clicked ", coord, ", distance from origin: ", HexGrid.distance(Vector2i.ZERO, coord))
```

### Centering the grid

Hexagon maps are already centered on the node's origin. For other shapes, use `get_bounds()`:

```gdscript
func _center_grid() -> void:
    var bounds: Rect2 = grid.get_bounds()
    grid.position = get_viewport_rect().size / 2.0 - bounds.get_center()
```

`get_bounds()` returns a conservative box (each hex counts as a `2 * hex_size` square), so it can be slightly larger than the drawn map. The center is still correct for centering.

---

## Core concepts

### Axial coordinates

Every hex is a `Vector2i(q, r)`. The third cube coordinate is derived: `s = -q - r`. Because hexes are plain vectors, you can add, subtract and scale them:

```gdscript
var a: Vector2i = Vector2i(2, -1)
var b: Vector2i = a + HexGrid.DIRECTIONS[0] * 3  # three steps in direction 0
```

### Orientation and size

`hex_size` is the distance from a hex's center to a corner.

| | Width | Height | Horizontal spacing | Vertical spacing |
|---|---|---|---|---|
| Pointy-top | √3 · size | 2 · size | √3 · size | 3/2 · size |
| Flat-top | 2 · size | √3 · size | 3/2 · size | √3 · size |

### Directions

`HexGrid.DIRECTIONS` lists the six neighbor offsets **counter-clockwise on screen** (Godot's y-axis points down). `HexGrid.DIAGONALS` lists the six distance-2 hexes in the same order.

| Index | Offset (q, r) | Pointy-top | Flat-top |
|---|---|---|---|
| 0 | (+1, 0) | East | South-east |
| 1 | (+1, -1) | North-east | North-east |
| 2 | (0, -1) | North-west | North |
| 3 | (-1, 0) | West | North-west |
| 4 | (-1, +1) | South-west | South-west |
| 5 | (0, +1) | South-east | South |

### Local space

All pixel positions are **local to the HexGrid node**. Convert global positions with `to_local()` and `to_global()`.

---

## Configuration

| Group | Property | Type | Default | Description |
|---|---|---|---|---|
| Layout | `orientation` | `HexOrientation` | `POINTY` | `POINTY` or `FLAT`. Redraws immediately. Coordinates are unchanged and the map is not regenerated. |
| Layout | `hex_size` | `float` | `32.0` | Center-to-corner distance in pixels (minimum 1). Redraws immediately. |
| Generation | `auto_generate` | `bool` | `true` | Generate in `_ready()` if no cells exist. Turn off if you call `set_cells()` yourself. |
| Generation | `shape` | `Shape` | `HEXAGON` | `HEXAGON`, `RECTANGLE`, `RHOMBUS` or `TRIANGLE`. |
| Generation | `radius` | `int` | `6` | Used by `HEXAGON` and `TRIANGLE`. |
| Generation | `grid_width`, `grid_height` | `int` | `12`, `8` | Used by `RECTANGLE` and `RHOMBUS`. |
| Look | `fill_color` | `Color` | dark blue-grey | Default fill for walkable cells. |
| Look | `wall_color` | `Color` | near-black | Default fill for non-walkable cells. |
| Look | `line_color` | `Color` | light blue-grey | Outline color. |
| Look | `hover_color` | `Color` | translucent white | Overlay on the hovered hex. |
| Look | `selected_color` | `Color` | translucent gold | Overlay and outline on the selected hex. |
| Look | `line_width` | `float` | `1.5` | Outline thickness. |
| Look | `show_coords` | `bool` | `false` | Draw `q,r` labels in every hex. |
| Look | `interactive` | `bool` | `true` | Enable mouse hover and click detection. |

Changing `shape`, `radius`, `grid_width` or `grid_height` after the map exists does **not** rebuild it. Call `generate()` again.

---

## Generating maps

### Built-in shapes

```gdscript
grid.shape = HexGrid.Shape.HEXAGON
grid.radius = 8
grid.generate()  # 1 + 3 * 8 * 9 = 217 hexes
```

| Shape | Description | Parameters |
|---|---|---|
| `HEXAGON` | Hexagon centered on (0, 0). | `radius` |
| `RECTANGLE` | Rectangular on screen. Odd-r offset for pointy-top, odd-q for flat-top. | `grid_width`, `grid_height` |
| `RHOMBUS` | `q` from 0 to width-1, `r` from 0 to height-1. | `grid_width`, `grid_height` |
| `TRIANGLE` | Right-angled triangle: `r` from 0 to `radius`, `q` from 0 to `radius - r`. | `radius` |

### Static generators and custom shapes

The generators are `static`, so you can build coordinate lists and combine them. Any set of unique axial coordinates is a valid map.

```gdscript
var coords: Array[Vector2i] = HexGrid.hexagon_coords(5)
for c: Vector2i in HexGrid.rhombus_coords(4, 4):
    coords.append(c + Vector2i(10, 0))  # a second island, shifted right
grid.set_cells(coords)

grid.remove_cell(Vector2i.ZERO)  # carve a hole afterwards
```

### From row and column data

```gdscript
var coords: Array[Vector2i] = []
for row: int in 8:
    for col: int in 12:
        coords.append(HexGrid.offset_to_axial(Vector2i(col, row), HexGrid.OffsetType.ODD_R))
grid.set_cells(coords)
```

Use `ODD_R` / `EVEN_R` for pointy-top and `ODD_Q` / `EVEN_Q` for flat-top.

---

## Working with cells

Each map position holds a `HexCell` (a `RefCounted` inner class):

| Field | Type | Default | Purpose |
|---|---|---|---|
| `coord` | `Vector2i` | set on creation | Axial coordinate. |
| `walkable` | `bool` | `true` | Whether movement can enter it. |
| `move_cost` | `float` | `1.0` | Cost to **enter** this cell. Must not be negative. |
| `blocks_sight` | `bool` | `false` | Whether it blocks line of sight. |
| `color` | `Color` | alpha 0 | Custom fill. Alpha 0 means "use the grid defaults". |
| `data` | `Dictionary` | `{}` | Anything else: terrain, owner, unit id. |

```gdscript
var cell: HexGrid.HexCell = grid.get_cell(Vector2i(2, -1))  # null if not in the map
if cell != null:
    cell.move_cost = 3.0
    cell.data["terrain"] = "forest"
    grid.set_cell_color(cell.coord, Color(0.2, 0.5, 0.2))
```

### Helper methods

| Method | Redraws | Emits `cell_changed` |
|---|---|---|
| `add_cell(coord)` (only if new) | yes | yes |
| `remove_cell(coord)` (only if it existed) | yes | yes |
| `set_walkable(coord, value)` | yes | yes |
| `set_blocks_sight(coord, value)` | yes | yes |
| `set_cell_color(coord, color)` | yes | no |
| `set_cells(coords)` | yes | no |

`has_cell(coord)` checks membership. `is_walkable(coord)` is `false` for missing **and** non-walkable cells.

> If you change `HexCell` fields directly (`cell.walkable = false`), no signal is emitted and no redraw is queued. Call `grid.queue_redraw()` or use the helpers. Likewise, add and remove cells through `add_cell()` / `remove_cell()` rather than editing `cells`, so highlights and signals stay consistent.

### Iterating

```gdscript
for coord: Vector2i in grid.cells:
    var cell: HexGrid.HexCell = grid.cells[coord]
```

---

## Coordinates and pixels

### Coordinate conversion

All conversions are `static`.

```gdscript
var axial: Vector2i = Vector2i(3, -2)
var cube: Vector3i = HexGrid.axial_to_cube(axial)  # (3, -2, -1)
var odd_r: Vector2i = HexGrid.axial_to_offset(axial, HexGrid.OffsetType.ODD_R)  # (col, row)
var back: Vector2i = HexGrid.offset_to_axial(odd_r, HexGrid.OffsetType.ODD_R)  # (3, -2)
```

| Offset type | Layout | Orientation |
|---|---|---|
| `ODD_R` | odd rows shoved right | pointy-top |
| `EVEN_R` | even rows shoved right | pointy-top |
| `ODD_Q` | odd columns shoved down | flat-top |
| `EVEN_Q` | even columns shoved down | flat-top |

Doubled-width coordinates suit pointy-top layouts and doubled-height suit flat-top. Both require `(col + row)` to be even; other values give meaningless results.

### Pixel conversion

| Function | Notes |
|---|---|
| `hex_to_pixel(hex)` | Center of a hex in local space. |
| `pixel_to_hex(pos)` | Hex containing a local position. Always returns *a* hex, even outside the map. |
| `pixel_to_hex_frac(pos)` | Fractional axial coordinates before rounding. |
| `get_hex_at_mouse()` | Hex under the mouse, or `HexGrid.INVALID` if it isn't in the map. |
| `hex_corners(hex)` | Six corner points in local space. |
| `get_bounds()` | Bounding `Rect2` of the whole map in local space. |
| `HexGrid.hex_round(q, r)` | Static. Correct cube rounding of fractional coordinates. |

```gdscript
# Global position -> hex
var hex: Vector2i = grid.pixel_to_hex(grid.to_local(global_pos))
if grid.has_cell(hex):
    pass

# Hex -> global position
var world_pos: Vector2 = grid.to_global(grid.hex_to_pixel(hex))
```

If a unit is a **child** of the grid, set `unit.position = grid.hex_to_pixel(hex)` directly.

---

## Neighbors, ranges and lines

| Function | Notes |
|---|---|
| `HexGrid.neighbor(hex, dir)` | Static. `dir` wraps modulo 6. Ignores the map. |
| `HexGrid.diagonal_neighbor(hex, dir)` | Static. Ignores the map. |
| `grid.neighbors(hex)` | Neighbors that **exist** in the map. |
| `grid.walkable_neighbors(hex)` | Neighbors that exist **and** are walkable. |
| `HexGrid.distance(a, b)` | Static. Distance in steps. |

```gdscript
var d: int = HexGrid.distance(Vector2i(0, 0), Vector2i(3, -2))  # 3
var east_ish: Vector2i = HexGrid.neighbor(Vector2i(2, 2), 0)  # (3, 2)
```

The shape functions below are static and ignore the map and obstacles.

```gdscript
var beam: Array[Vector2i] = HexGrid.line(Vector2i(0, 0), Vector2i(4, -2))  # includes both endpoints
var area: Array[Vector2i] = HexGrid.hexes_in_range(Vector2i.ZERO, 3)       # 37 hexes
var loop: Array[Vector2i] = HexGrid.ring(Vector2i.ZERO, 3)                 # 18 hexes; radius 0 gives the center
var coil: Array[Vector2i] = HexGrid.spiral(Vector2i.ZERO, 3)               # center, then rings 1..3
var total: int = HexGrid.hexagon_count(4)                                  # 61

# Hexes inside ALL of the given [center, radius] pairs
var overlap: Array[Vector2i] = HexGrid.intersect_ranges([
    [Vector2i(0, 0), 3],
    [Vector2i(2, 0), 3],
])
```

`line()` interpolates and applies cube rounding, with a tiny constant nudge so samples never land exactly on a hex edge.

### Restricting results to the map

`filter()` and `map()` return an untyped `Array`, which can't be passed to `set_cells()`. A small helper keeps the types intact:

```gdscript
func in_map(coords: Array[Vector2i]) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for h: Vector2i in coords:
        if grid.has_cell(h):
            out.append(h)
    return out
```

If you do use `filter()` / `map()`, convert with `typed_array.assign(untyped_array)`.

---

## Rotation, reflection and wraparound

### Rotation

`steps` is a multiple of 60°. Positive is clockwise on screen, negative is counter-clockwise.

```gdscript
var cw: Vector2i = HexGrid.rotate_around(hex, center, 1)
var half_turn: Vector2i = HexGrid.rotate_around(hex, center, 3)
var ccw: Vector2i = HexGrid.rotate_around(hex, center, -1)
```

Rotating a multi-hex shape around a pivot:

```gdscript
func rotate_shape(shape: Array[Vector2i], pivot: Vector2i, steps: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for h: Vector2i in shape:
        out.append(HexGrid.rotate_around(h, pivot, steps))
    return out
```

### Reflection

`axis` is `0` (q), `1` (r) or `2` (s). The center defaults to the origin.

```gdscript
var mirrored: Vector2i = HexGrid.reflect(hex, 0)
var mirrored_about: Vector2i = HexGrid.reflect(hex, 2, some_center)
```

### Wraparound

For **hexagon maps centered on (0, 0)** only:

```gdscript
var next: Vector2i = HexGrid.wrap_hexagon(hex + HexGrid.DIRECTIONS[0], radius)
```

`wrap_hexagon()` handles coordinates about one step off the edge. It is meant for movement, not for wrapping far-away coordinates. For rectangular wraparound, convert with `axial_to_offset()` and apply modulo to the column or row.

---

## Pathfinding and field of view

### Costs

- A step costs the `move_cost` of the cell being **entered**.
- Missing and non-walkable cells are never entered. Start and goal must both be walkable.
- Costs must not be negative.

### `find_path(start, goal)`

A\* search. Returns the path **including** start and goal, or an empty array if either end isn't walkable or the goal is unreachable.

```gdscript
var path: Array[Vector2i] = grid.find_path(Vector2i(0, 0), Vector2i(4, -1))
if path.is_empty():
    print("No route")
else:
    print("Steps: ", path.size() - 1, ", cost: ", grid.path_cost(path))
```

The heuristic is `distance * cheapest walkable move_cost`, so it stays admissible and paths are optimal with varied terrain. `path_cost()` excludes the start hex.

### `reachable(start, max_cost)`

Dijkstra flood fill. Returns `{ coord: total_cost }` for every hex reachable within `max_cost`, including the start at cost 0. With all costs at 1.0 it acts as an obstacle-aware, distance-limited flood fill.

```gdscript
var reach: Dictionary[Vector2i, float] = grid.reachable(unit_hex, 4.0)
grid.highlight(reach.keys(), Color(0.3, 0.6, 1.0, 0.4))
```

### `field_of_view(origin, vision_range)`

A hex in range is visible if the line from `origin` to it crosses no cell with `blocks_sight`.

- The origin is always included.
- Blocking hexes themselves are visible. You can see a wall, not through it.
- A line that crosses a gap (a missing cell) counts as blocked.
- Walkability is not considered.

```gdscript
grid.set_blocks_sight(Vector2i(2, 0), true)
var seen: Array[Vector2i] = grid.field_of_view(Vector2i(0, 0), 6)
grid.highlight(seen, Color(1, 1, 0.5, 0.3))
```

---

## Rendering, input and signals

### Draw order

For each cell: fill (highlight, then custom color, then wall color, then default fill) and outline. After all cells: hover overlay, selection overlay and outline, then optional coordinate labels.

### Highlights

```gdscript
grid.highlight(some_hexes, Color(0.9, 0.3, 0.3, 0.5))  # add or overwrite
grid.clear_highlights()
```

A highlight **replaces** the cell's fill rather than blending with it, so a semi-transparent color shows the window background through it. If several highlights hit the same hex, the last call wins. Apply them in layering order, for example movement range first and then the path.

### Hover and selection

`hovered` is updated automatically from mouse motion while `interactive` is on. `selected` is **never set by the grid**, not even on click. Set it yourself and request a redraw:

```gdscript
grid.selected = Vector2i(2, 1)
grid.queue_redraw()

grid.selected = HexGrid.INVALID  # clear
grid.queue_redraw()
```

### Signals

| Signal | Arguments | Emitted when |
|---|---|---|
| `hex_hovered` | `coord: Vector2i` | The hovered hex changed. `HexGrid.INVALID` when the mouse leaves the map. |
| `hex_clicked` | `coord: Vector2i, button: int` | Any mouse button is **pressed** on a hex in the map. |
| `cell_changed` | `coord: Vector2i` | See the table in [Working with cells](#working-with-cells). |

`hex_clicked` fires for mouse-wheel ticks too (`MOUSE_BUTTON_WHEEL_UP` / `MOUSE_BUTTON_WHEEL_DOWN`), so always check `button`:

```gdscript
grid.hex_clicked.connect(func(coord: Vector2i, button: int) -> void:
    if button == MOUSE_BUTTON_LEFT:
        grid.selected = coord
        grid.queue_redraw()
    elif button == MOUSE_BUTTON_RIGHT:
        grid.set_walkable(coord, not grid.is_walkable(coord))
)
```

### How input is received

Input uses `_unhandled_input()`:

- A `Control` that consumes the mouse event blocks the grid, which is usually what you want.
- If something else handles the click first, the grid never sees it.
- Set `interactive = false` and call `get_hex_at_mouse()` yourself for full manual control.

### Drawing on top

`HexGrid` is a `Node2D`, so child nodes (sprites, labels, your own `_draw()` nodes) draw above it. Place them with `hex_to_pixel()`.

---

## Recipes

Recipes assume a `grid: HexGrid` variable. The `in_map()` helper is defined in [Neighbors, ranges and lines](#neighbors-ranges-and-lines).

### Terrain types with different costs

```gdscript
const TERRAIN: Dictionary = {
    "grass": {"cost": 1.0, "walkable": true, "color": Color(0.25, 0.5, 0.25)},
    "forest": {"cost": 2.0, "walkable": true, "color": Color(0.1, 0.35, 0.15)},
    "water": {"cost": 1.0, "walkable": false, "color": Color(0.15, 0.3, 0.7)},
}


func set_terrain(coord: Vector2i, kind: String) -> void:
    var cell: HexGrid.HexCell = grid.get_cell(coord)
    if cell == null:
        return
    var t: Dictionary = TERRAIN[kind]
    cell.data["terrain"] = kind
    cell.move_cost = t["cost"]
    cell.walkable = t["walkable"]
    cell.color = t["color"]
    grid.queue_redraw()
```

### Click to move a unit along a path

```gdscript
@onready var grid: HexGrid = $HexGrid
@onready var unit: Node2D = $HexGrid/Unit  # a child of the grid

var unit_hex: Vector2i = Vector2i.ZERO
var _tween: Tween


func _on_hex_clicked(coord: Vector2i, button: int) -> void:
    if button != MOUSE_BUTTON_LEFT:
        return
    if _tween != null and _tween.is_running():
        return  # ignore clicks while moving
    var path: Array[Vector2i] = grid.find_path(unit_hex, coord)
    if path.size() < 2:
        return
    _tween = create_tween()
    for i: int in range(1, path.size()):
        _tween.tween_property(unit, "position", grid.hex_to_pixel(path[i]), 0.15)
    unit_hex = coord
```

### Movement range preview on hover

```gdscript
func _on_hex_hovered(coord: Vector2i) -> void:
    grid.clear_highlights()
    if coord == HexGrid.INVALID:
        return
    var reach: Dictionary[Vector2i, float] = grid.reachable(coord, 3.0)
    grid.highlight(reach.keys(), Color(0.3, 0.6, 1.0, 0.4))
```

### Fog of war

Highlights replace the cell fill, so fogged hexes show the background rather than the terrain underneath. For a fog that preserves terrain colors, use cell colors or a child overlay node instead.

```gdscript
func update_fog(origin: Vector2i, vision: int) -> void:
    var seen: Dictionary[Vector2i, bool] = {}
    for h: Vector2i in grid.field_of_view(origin, vision):
        seen[h] = true

    var hidden: Array[Vector2i] = []
    for c: Vector2i in grid.cells:
        if not seen.has(c):
            hidden.append(c)

    grid.clear_highlights()
    grid.highlight(hidden, Color(0, 0, 0, 0.75))
```

### Area-of-effect and beam attacks

```gdscript
var blast: Array[Vector2i] = in_map(HexGrid.hexes_in_range(target, 2))
var wave: Array[Vector2i] = in_map(HexGrid.ring(target, 3))

# A beam that stops at (and hits) the first opaque hex
var hit: Array[Vector2i] = []
for h: Vector2i in HexGrid.line(attacker, target):
    if h == attacker:
        continue
    hit.append(h)
    var cell: HexGrid.HexCell = grid.get_cell(h)
    if cell != null and cell.blocks_sight:
        break
```

### Saving and loading a map

```gdscript
func save_map() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for cell: HexGrid.HexCell in grid.cells.values():
        out.append({
            "q": cell.coord.x,
            "r": cell.coord.y,
            "walkable": cell.walkable,
            "cost": cell.move_cost,
            "sight": cell.blocks_sight,
            "data": cell.data,
        })
    return out


func load_map(rows: Array[Dictionary]) -> void:
    var coords: Array[Vector2i] = []
    for row: Dictionary in rows:
        coords.append(Vector2i(int(row["q"]), int(row["r"])))
    grid.set_cells(coords)

    for row: Dictionary in rows:
        var cell: HexGrid.HexCell = grid.get_cell(Vector2i(int(row["q"]), int(row["r"])))
        cell.walkable = row["walkable"]
        cell.move_cost = row["cost"]
        cell.blocks_sight = row["sight"]
        cell.data = row["data"]
    grid.queue_redraw()
```

Use `JSON.stringify()` and `FileAccess` to write it to disk. JSON turns every number into a float (hence the `int()` casts), and `Color` / `Vector2i` values inside `data` must be converted by hand.

### Switching orientation at runtime

```gdscript
grid.orientation = HexGrid.HexOrientation.FLAT
```

Coordinates stay valid and only the pixel layout changes. A `RECTANGLE` map is no longer a clean rectangle afterwards, because it was generated with the other offset type. Call `generate()` to rebuild it.

### Multiple grids

Each `HexGrid` is independent. Put several in one scene (a world map and a battle map, say) and position them like any `Node2D`.

---

## Using the math without a node

Every `static` function works with no instance and no scene tree:

```gdscript
var d: int = HexGrid.distance(a, b)
var area: Array[Vector2i] = HexGrid.hexes_in_range(c, 4)
var offset: Vector2i = HexGrid.axial_to_offset(a, HexGrid.OffsetType.EVEN_Q)
```

You can also create an instance purely for logic. `HexGrid.new()` plus `generate()` or `set_cells()` gives you pathfinding and field of view on the data. Set `hex_size` and `orientation` first if you need pixel functions. An instance that never enters the tree must be freed with `free()`, since `queue_free()` has no effect on it.

---

## Performance

- **Rendering** redraws every cell on each `queue_redraw()`. That is fine for a few thousand hexes. Much larger maps may need chunking or a `TileMapLayer` / `MultiMesh` renderer, and the data and algorithms here can still drive it. Coordinate labels (`show_coords`) are the most expensive part of drawing, so turn them off on large maps.
- **Redraw requests** within a frame are coalesced by Godot, so changing many highlights at once is fine.
- **`field_of_view`** draws a line to every hex in range, so cost grows roughly with `vision_range³`. Typical radii (up to about 12) are fine.
- **`find_path`** scans all cells for the cheapest walkable cost on every call (O(n)) before searching. On very large maps with frequent pathing, consider caching that value.
- **Lookups** by `Vector2i` key are O(1).
- Rebuild highlights on events (hover change, click), not every `_process()`.

---

## Limitations

- **Field of view** is the simple "line to each hex" method. Visibility is not guaranteed to be symmetric, and you may want shadow casting or partial-hex rules for your game.
- **Lines** can occasionally touch a hex slightly off the ideal line. This is inherent to the sampling method.
- **Wraparound** exists for hexagon-shaped maps only.
- **Rendering** is a plain `_draw()` renderer with no textures, per-hex sprites or batching. It is a foundation, not final art.
- **Costs** are per entered cell. There are no per-edge costs and no one-way movement.
- **Input** is mouse-only (no touch or gamepad). `hovered` updates only on mouse motion, so it can be stale if the grid moves under a stationary cursor.
- **Doubled coordinates** convert through axial. There is no direct doubled-to-pixel path.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Nothing is drawn | The map is empty. Check `auto_generate`, or call `generate()` / `set_cells()`. Also check `hex_size` and that the node is on screen. |
| Grid is off-screen | Hexagon maps center on the node's origin. Other shapes start at (0, 0) and extend right and down. Center with `get_bounds()`. |
| Clicks do nothing | `interactive` is off, a `Control` is eating the event, or the hex isn't in the map. |
| Clicks fire on mouse wheel | `hex_clicked` includes wheel ticks. Check `button`. |
| Click position is wrong | Convert global positions with `to_local()` before calling `pixel_to_hex()`. |
| Selection doesn't appear | `selected` doesn't redraw on its own. Call `queue_redraw()` after setting it. |
| Cell changes don't show | You edited `HexCell` fields directly. Call `queue_redraw()` or use the setter methods. |
| Rectangle looks like a parallelogram | You changed `orientation` after generating. Call `generate()` again. |
| `find_path` returns `[]` | Start or goal is missing or not walkable, or the goal is walled off. |
| `wrap_hexagon` returns the same hex | The input is more than about one step outside the map, or the map isn't a (0, 0)-centered hexagon of that radius. |
| Doubled-coordinate results look wrong | They require `(col + row)` to be even. |
| Parse error on `Dictionary[Vector2i, HexCell]` | You're on a Godot version older than 4.4. |
| Type error mentioning `Orientation` | You have an old copy of the script. The enum is named `HexOrientation` because Godot already has a global `Orientation`. |

---

## API reference

### Enums

| Enum | Values |
|---|---|
| `HexOrientation` | `POINTY`, `FLAT` |
| `Shape` | `HEXAGON`, `RECTANGLE`, `RHOMBUS`, `TRIANGLE` |
| `OffsetType` | `ODD_R`, `EVEN_R`, `ODD_Q`, `EVEN_Q` |

### Constants

| Constant | Type | Description |
|---|---|---|
| `SQRT3` | `float` | √3 |
| `INVALID` | `Vector2i` | `(2147483647, 2147483647)`, the "no hex" sentinel |
| `DIRECTIONS` | `Array[Vector2i]` | Six neighbor offsets |
| `DIAGONALS` | `Array[Vector2i]` | Six diagonal offsets |

### Signals

`hex_hovered(coord: Vector2i)`, `hex_clicked(coord: Vector2i, button: int)`, `cell_changed(coord: Vector2i)`

### Instance state

| Member | Type | Description |
|---|---|---|
| `cells` | `Dictionary[Vector2i, HexCell]` | All cells |
| `hovered` | `Vector2i` | Hovered hex, `INVALID` if none |
| `selected` | `Vector2i` | Selected hex, `INVALID` if none. Set by you, not by the grid. |

### Instance methods

| Method | Returns |
|---|---|
| `generate()` | `void` |
| `set_cells(coords: Array[Vector2i])` | `void` |
| `add_cell(coord: Vector2i)` | `HexCell` |
| `remove_cell(coord: Vector2i)` | `void` |
| `has_cell(coord: Vector2i)` | `bool` |
| `get_cell(coord: Vector2i)` | `HexCell` (`null` if missing) |
| `is_walkable(coord: Vector2i)` | `bool` |
| `set_walkable(coord: Vector2i, value: bool)` | `void` |
| `set_blocks_sight(coord: Vector2i, value: bool)` | `void` |
| `set_cell_color(coord: Vector2i, color: Color)` | `void` |
| `highlight(coords: Array, color: Color)` | `void` |
| `clear_highlights()` | `void` |
| `hex_to_pixel(h: Vector2i)` | `Vector2` |
| `pixel_to_hex(p: Vector2)` | `Vector2i` |
| `pixel_to_hex_frac(p: Vector2)` | `Vector2` |
| `get_hex_at_mouse()` | `Vector2i` (`INVALID` if none) |
| `hex_corners(h: Vector2i)` | `PackedVector2Array` |
| `get_bounds()` | `Rect2` |
| `neighbors(h: Vector2i)` | `Array[Vector2i]` |
| `walkable_neighbors(h: Vector2i)` | `Array[Vector2i]` |
| `find_path(start: Vector2i, goal: Vector2i)` | `Array[Vector2i]` |
| `path_cost(path: Array[Vector2i])` | `float` |
| `reachable(start: Vector2i, max_cost: float)` | `Dictionary[Vector2i, float]` |
| `field_of_view(origin: Vector2i, vision_range: int)` | `Array[Vector2i]` |

### Static methods

| Method | Returns |
|---|---|
| `hexagon_coords(n: int)` | `Array[Vector2i]` |
| `rectangle_coords(w: int, h: int, orient: HexOrientation = POINTY)` | `Array[Vector2i]` |
| `rhombus_coords(w: int, h: int)` | `Array[Vector2i]` |
| `triangle_coords(n: int)` | `Array[Vector2i]` |
| `axial_to_cube(a: Vector2i)` | `Vector3i` |
| `cube_to_axial(c: Vector3i)` | `Vector2i` |
| `axial_to_offset(a: Vector2i, type: OffsetType)` | `Vector2i` |
| `offset_to_axial(o: Vector2i, type: OffsetType)` | `Vector2i` |
| `axial_to_doublewidth(a: Vector2i)` / `doublewidth_to_axial(d: Vector2i)` | `Vector2i` |
| `axial_to_doubleheight(a: Vector2i)` / `doubleheight_to_axial(d: Vector2i)` | `Vector2i` |
| `hex_round(fq: float, fr: float)` | `Vector2i` |
| `neighbor(h: Vector2i, dir: int)` | `Vector2i` |
| `diagonal_neighbor(h: Vector2i, dir: int)` | `Vector2i` |
| `distance(a: Vector2i, b: Vector2i)` | `int` |
| `line(a: Vector2i, b: Vector2i)` | `Array[Vector2i]` |
| `hexes_in_range(center: Vector2i, n: int)` | `Array[Vector2i]` |
| `intersect_ranges(ranges: Array)` | `Array[Vector2i]` |
| `ring(center: Vector2i, rad: int)` | `Array[Vector2i]` |
| `spiral(center: Vector2i, rad: int)` | `Array[Vector2i]` |
| `hexagon_count(n: int)` | `int` |
| `rotate_around(h: Vector2i, center: Vector2i, steps: int)` | `Vector2i` |
| `reflect(h: Vector2i, axis: int, center: Vector2i = Vector2i.ZERO)` | `Vector2i` |
| `wrap_hexagon(h: Vector2i, rad: int)` | `Vector2i` |

### `HexCell`

`coord: Vector2i`, `walkable: bool`, `move_cost: float`, `blocks_sight: bool`, `color: Color`, `data: Dictionary`.

---

## Credits

Algorithms and coordinate systems are based on Amit Patel's *Hexagonal Grids* guide at [Red Blob Games](https://www.redblobgames.com/grids/hexagons/), which builds on the work of Charles Fu and Clark Verbrugge.
