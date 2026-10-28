# HexGrid for Godot 4

A self-contained, single-file 2D hexagon grid for Godot 4.x (4.2 or newer recommended). It combines map storage, coordinate math, pathfinding, field of view, rendering and mouse input in one `Node2D` class, and its math is also usable without any node at all.

The algorithms follow Red Blob Games' *Hexagonal Grids* guide: axial coordinates for storage, cube coordinates for the math, and offset/doubled coordinates for conversions.

---

## Table of contents

1. [Features at a glance](#1-features-at-a-glance)
2. [Installation](#2-installation)
3. [Quick start](#3-quick-start)
4. [Core concepts](#4-core-concepts)
5. [Configuration (Inspector properties)](#5-configuration-inspector-properties)
6. [Generating maps](#6-generating-maps)
7. [Working with cells](#7-working-with-cells)
8. [Coordinate conversion](#8-coordinate-conversion)
9. [Pixel / screen conversion](#9-pixel--screen-conversion)
10. [Neighbors and distance](#10-neighbors-and-distance)
11. [Lines, ranges, rings and spirals](#11-lines-ranges-rings-and-spirals)
12. [Rotation and reflection](#12-rotation-and-reflection)
13. [Wraparound maps](#13-wraparound-maps)
14. [Pathfinding, movement range and field of view](#14-pathfinding-movement-range-and-field-of-view)
15. [Highlights and rendering](#15-highlights-and-rendering)
16. [Input and signals](#16-input-and-signals)
17. [Recipes](#17-recipes)
18. [Using the math without a node](#18-using-the-math-without-a-node)
19. [Performance notes](#19-performance-notes)
20. [Troubleshooting](#20-troubleshooting)
21. [Limitations](#21-limitations)
22. [Full API reference](#22-full-api-reference)
23. [Credits](#23-credits)

---

## 1. Features at a glance

| Area | What you get |
|---|---|
| **Storage** | Axial coordinates (`Vector2i`) in a `Dictionary` (hash storage). Any map shape, including holes and irregular islands. |
| **Orientation** | Pointy-top or flat-top, switchable at runtime. |
| **Map shapes** | Hexagon, rectangle, rhombus, triangle generators, or supply your own list of coordinates. |
| **Coordinate systems** | Axial, cube, offset (odd-r, even-r, odd-q, even-q), doubled-width, doubled-height, with conversion functions between them. |
| **Geometry** | Neighbors, diagonal neighbors, distance, line drawing, ranges, range intersection, rings, spirals, rotation, reflection. |
| **Pixel math** | Hex to pixel, pixel to hex (with correct cube rounding), hex corner polygons, map bounds. |
| **Gameplay** | A\* pathfinding with variable move costs, Dijkstra movement range, line-of-sight field of view. |
| **Cell data** | Per-cell `walkable`, `move_cost`, `blocks_sight`, `color` and a free-form `data` dictionary. |
| **Rendering** | Built-in `_draw()` renderer with fills, outlines, hover/selection, overlay highlights and optional coordinate labels. |
| **Input** | Hover and click detection exposed as signals. |
| **Wraparound** | Mirror-center wrapping for hexagon-shaped maps. |

---

## 2. Installation

1. Copy `hex_grid.gd` into your project (for example `res://scripts/hex_grid.gd`).
2. The file declares `class_name HexGrid`, so Godot registers it automatically. No autoload or plugin is needed.
3. If the class does not appear in the *Add Node* dialog right away, reload the project (Project → Reload Current Project) or reopen the script once.

There are no dependencies and no scenes or resources to import.

---

## 3. Quick start

### Option A: add it in the editor

1. Open a scene and choose **Add Node → HexGrid** (it appears under `Node2D`).
2. In the Inspector, pick a **Shape**, **Radius** (or **Grid Width/Height**) and **Hex Size**.
3. Run the scene. With `auto_generate` enabled (default) the map is generated when the node enters the tree.

### Option B: create it from code

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
    add_child(grid)   # generates the map in _ready()

    grid.hex_clicked.connect(_on_hex_clicked)

func _on_hex_clicked(coord: Vector2i, button: int) -> void:
    print("Clicked ", coord, " distance from origin: ", HexGrid.distance(Vector2i.ZERO, coord))
```

### Centering the grid on screen

The grid is drawn around its own origin, so a hexagon map is already centered on the node's position. For other shapes, use `get_bounds()`:

```gdscript
func _center_grid() -> void:
    var bounds := grid.get_bounds()
    grid.position = get_viewport_rect().size / 2.0 - bounds.get_center()
```

---

## 4. Core concepts

### 4.1 Axial coordinates

Every hex is a `Vector2i(q, r)`:

- `x` is **q** (the column-like axis)
- `y` is **r** (the row-like axis)
- the third cube coordinate is derived: **s = -q - r**

Axial and cube coordinates are the same system. HexGrid stores axial and calculates `s` only where an algorithm needs it. This means normal vector math works on hexes: you can add, subtract and scale `Vector2i` values.

```gdscript
var a := Vector2i(2, -1)
var b := a + HexGrid.DIRECTIONS[0] * 3   # three steps in direction 0
```

### 4.2 Orientation and "size"

- **Pointy-top**: hexes have a vertex at the top. Rows are straight horizontal lines.
- **Flat-top**: hexes have a flat edge at the top. Columns are straight vertical lines.
- **`hex_size`** is the distance from a hex's center to a corner (the outer radius).

Resulting dimensions:

| | Width | Height | Horizontal spacing | Vertical spacing |
|---|---|---|---|---|
| Pointy-top | √3 · size | 2 · size | √3 · size | 3/2 · size |
| Flat-top | 2 · size | √3 · size | 3/2 · size | √3 · size |

### 4.3 Direction indexes

`HexGrid.DIRECTIONS` holds the six neighbor offsets, ordered **counter-clockwise on screen**, with Godot's y-axis pointing down:

| Index | Offset (q, r) | Pointy-top | Flat-top |
|---|---|---|---|
| 0 | (+1, 0) | East | South-east |
| 1 | (+1, -1) | North-east | North-east |
| 2 | (0, -1) | North-west | North |
| 3 | (-1, 0) | West | North-west |
| 4 | (-1, +1) | South-west | South-west |
| 5 | (0, +1) | South-east | South |

`HexGrid.DIAGONALS` holds the six "diagonal" hexes (distance 2) in the same style.

### 4.4 Local space

All pixel positions in this class (`hex_to_pixel`, `pixel_to_hex`, ...) are **local to the HexGrid node**. If you start from a global position, convert first with `to_local()`.

---

## 5. Configuration (Inspector properties)

### Layout

| Property | Type | Default | Description |
|---|---|---|---|
| `orientation` | `HexOrientation` | `POINTY` | `POINTY` or `FLAT`. Changing it at runtime redraws immediately. Existing coordinates stay the same (the map is not regenerated). |
| `hex_size` | `float` | `32.0` | Center-to-corner distance in pixels (minimum 1). |

### Generation

| Property | Type | Default | Description |
|---|---|---|---|
| `auto_generate` | `bool` | `true` | Generate the map in `_ready()` if no cells exist yet. Disable it if you will call `set_cells()` yourself. |
| `shape` | `Shape` | `HEXAGON` | `HEXAGON`, `RECTANGLE`, `RHOMBUS` or `TRIANGLE`. |
| `radius` | `int` | `6` | Used by `HEXAGON` (rings around center) and `TRIANGLE` (side length minus one). |
| `grid_width` / `grid_height` | `int` | `12` / `8` | Used by `RECTANGLE` and `RHOMBUS`. |

### Look

| Property | Type | Default | Description |
|---|---|---|---|
| `fill_color` | `Color` | dark blue-grey | Default fill for walkable cells. |
| `wall_color` | `Color` | near-black | Default fill for non-walkable cells. |
| `line_color` | `Color` | light blue-grey | Outline color. |
| `hover_color` | `Color` | translucent white | Overlay for the hovered hex. |
| `selected_color` | `Color` | translucent gold | Overlay and outline for the selected hex. |
| `line_width` | `float` | `1.5` | Outline thickness. |
| `show_coords` | `bool` | `false` | Draws `q,r` labels in every hex. |
| `interactive` | `bool` | `true` | Enables mouse hover and click detection. |

Changing `generate()`-related properties (`shape`, `radius`, `grid_width`, `grid_height`) after the map exists does **not** rebuild it. Call `generate()` again.

---

## 6. Generating maps

### 6.1 Built-in shapes

```gdscript
grid.shape = HexGrid.Shape.HEXAGON
grid.radius = 8
grid.generate()          # 1 + 3 * 8 * 9 = 217 hexes
```

| Shape | Description | Parameters |
|---|---|---|
| `HEXAGON` | Hexagon-shaped map centered at (0,0). | `radius` |
| `RECTANGLE` | Looks rectangular on screen. Uses odd-r offset layout for pointy-top, odd-q for flat-top. | `grid_width`, `grid_height` |
| `RHOMBUS` | `q` from 0 to width-1, `r` from 0 to height-1. | `grid_width`, `grid_height` |
| `TRIANGLE` | Right-angled triangle, `r` from 0 to radius, `q` from 0 to radius-r. | `radius` |

### 6.2 Static shape generators

Use these to build coordinate lists without touching the grid, for example to combine shapes:

```gdscript
var coords: Array[Vector2i] = HexGrid.hexagon_coords(5)
for c in HexGrid.rhombus_coords(4, 4):
    coords.append(c + Vector2i(10, 0))     # a second island, shifted right
grid.set_cells(coords)
```

### 6.3 Custom shapes

Any set of unique axial coordinates is a valid map. You can leave holes, create islands, or use data from a file.

```gdscript
var coords: Array[Vector2i] = []
for c in HexGrid.hexagon_coords(6):
    if c != Vector2i.ZERO:                # carve a hole in the center
        coords.append(c)
grid.set_cells(coords)
```

### 6.4 Rectangular maps from offset coordinates

If your level data is stored as rows and columns, convert it:

```gdscript
var coords: Array[Vector2i] = []
for row in 8:
    for col in 12:
        coords.append(HexGrid.offset_to_axial(Vector2i(col, row), HexGrid.OffsetType.ODD_R))
grid.set_cells(coords)
```

Use `ODD_R`/`EVEN_R` for pointy-top and `ODD_Q`/`EVEN_Q` for flat-top.

---

## 7. Working with cells

Each map position holds a `HexCell` (a `RefCounted` inner class):

| Field | Type | Default | Purpose |
|---|---|---|---|
| `coord` | `Vector2i` | set on creation | Axial coordinate of the cell. |
| `walkable` | `bool` | `true` | Whether pathfinding and movement can enter it. |
| `move_cost` | `float` | `1.0` | Cost to **enter** this cell. |
| `blocks_sight` | `bool` | `false` | Whether it blocks line of sight. |
| `color` | `Color` | alpha 0 | Custom fill. Alpha 0 means "use the grid defaults". |
| `data` | `Dictionary` | `{}` | Anything else: terrain type, owner, unit id, etc. |

### Reading and writing

```gdscript
var cell := grid.get_cell(Vector2i(2, -1))     # null if the hex isn't in the map
if cell:
    cell.move_cost = 3.0                       # e.g. forest
    cell.data["terrain"] = "forest"
    grid.set_cell_color(cell.coord, Color(0.2, 0.5, 0.2))
```

Helper methods (all redraw; `set_walkable`, `set_blocks_sight`, `add_cell` and `remove_cell` also emit `cell_changed`):

```gdscript
grid.set_walkable(coord, false)       # wall
grid.set_blocks_sight(coord, true)    # opaque
grid.set_cell_color(coord, Color.RED)
grid.add_cell(coord)                  # add a hex to the map
grid.remove_cell(coord)               # remove it (creates a hole)
grid.has_cell(coord)
grid.is_walkable(coord)               # false if missing OR not walkable
```

> If you modify `HexCell` fields **directly** (e.g. `cell.walkable = false`), no signal is emitted and no redraw is queued. Call `grid.queue_redraw()` yourself, or use the helper methods.

### Iterating over the map

```gdscript
for coord in grid.cells:
    var cell: HexGrid.HexCell = grid.cells[coord]
    # ...
```

---

## 8. Coordinate conversion

All conversion functions are `static`.

| Function | Converts |
|---|---|
| `axial_to_cube(Vector2i) -> Vector3i` | axial → cube `(q, r, s)` |
| `cube_to_axial(Vector3i) -> Vector2i` | cube → axial (drops `s`) |
| `axial_to_offset(Vector2i, OffsetType) -> Vector2i` | axial → `(col, row)` |
| `offset_to_axial(Vector2i, OffsetType) -> Vector2i` | `(col, row)` → axial |
| `axial_to_doublewidth` / `doublewidth_to_axial` | pointy-top doubled layout (column doubled) |
| `axial_to_doubleheight` / `doubleheight_to_axial` | flat-top doubled layout (row doubled) |

```gdscript
var axial := Vector2i(3, -2)
var cube  := HexGrid.axial_to_cube(axial)                                  # (3, -2, -1)
var odd_r := HexGrid.axial_to_offset(axial, HexGrid.OffsetType.ODD_R)      # (col, row)
var back  := HexGrid.offset_to_axial(odd_r, HexGrid.OffsetType.ODD_R)      # (3, -2)
```

Offset type reference:

| Type | Layout | Orientation |
|---|---|---|
| `ODD_R` | odd rows shoved right | pointy-top |
| `EVEN_R` | even rows shoved right | pointy-top |
| `ODD_Q` | odd columns shoved down | flat-top |
| `EVEN_Q` | even columns shoved down | flat-top |

Doubled coordinates must satisfy `(col + row) % 2 == 0`. Passing values that violate this gives meaningless results.

---

## 9. Pixel / screen conversion

| Function | Description |
|---|---|
| `hex_to_pixel(hex) -> Vector2` | Center of a hex in local space. |
| `pixel_to_hex(local_pos) -> Vector2i` | Hex containing a local position (always returns *a* hex, even outside the map). |
| `pixel_to_hex_frac(local_pos) -> Vector2` | Fractional axial coordinates before rounding. |
| `get_hex_at_mouse() -> Vector2i` | Hex under the mouse, or `HexGrid.INVALID` if it isn't part of the map. |
| `hex_corners(hex) -> PackedVector2Array` | Six corner points of a hex in local space. |
| `get_bounds() -> Rect2` | Bounding rectangle of the entire map in local space. |
| `hex_round(q, r) -> Vector2i` | Static. Rounds fractional axial coordinates correctly via cube rounding. |

```gdscript
# World/global position -> hex
var hex := grid.pixel_to_hex(grid.to_local(global_pos))

# Hex -> global position (e.g. to place a sprite)
var world_pos := grid.to_global(grid.hex_to_pixel(hex))

# Check it exists in the map
if grid.has_cell(hex):
    ...
```

If your units are **children** of the grid node, set `unit.position = grid.hex_to_pixel(hex)` directly.

---

## 10. Neighbors and distance

| Function | Description |
|---|---|
| `HexGrid.neighbor(hex, dir)` | Static. Neighbor in direction `dir` (wraps modulo 6). Ignores the map. |
| `HexGrid.diagonal_neighbor(hex, dir)` | Static. Diagonal neighbor. Ignores the map. |
| `grid.neighbors(hex)` | Neighbors that **exist** in the map. |
| `grid.walkable_neighbors(hex)` | Neighbors that exist **and** are walkable. |
| `HexGrid.distance(a, b)` | Static. Hex distance in steps. |

```gdscript
var d := HexGrid.distance(Vector2i(0, 0), Vector2i(3, -2))   # 3

for n in grid.neighbors(Vector2i(0, 0)):
    print(n)

var east_ish := HexGrid.neighbor(Vector2i(2, 2), 0)           # (3, 2)
```

---

## 11. Lines, ranges, rings and spirals

All static, all ignore map contents and obstacles unless stated otherwise.

### Line

```gdscript
var cells_on_line := HexGrid.line(Vector2i(0, 0), Vector2i(4, -2))
```

Uses linear interpolation with cube rounding. A tiny constant nudge keeps samples off hex edges so lines are stable and symmetric-looking. Returns both endpoints.

### Range

```gdscript
var area := HexGrid.hexes_in_range(Vector2i(0, 0), 3)     # 37 hexes
```

Filter against the map yourself:

```gdscript
var in_map := area.filter(func(c): return grid.has_cell(c))
```

### Intersecting ranges

Pass an array of `[center, radius]` pairs to get the hexes inside **all** of them:

```gdscript
var overlap := HexGrid.intersect_ranges([
    [Vector2i(0, 0), 3],
    [Vector2i(2, 0), 3],
])
```

### Ring and spiral

```gdscript
var ring := HexGrid.ring(Vector2i.ZERO, 3)       # 18 hexes, forming a loop
var spiral := HexGrid.spiral(Vector2i.ZERO, 3)   # center + rings 1..3, in spiral order
var count := HexGrid.hexagon_count(4)            # 61
```

`ring()` with radius 0 returns just the center.

---

## 12. Rotation and reflection

### Rotation

```gdscript
# Rotate a hex 60° clockwise (on screen) around a center
var r1 := HexGrid.rotate_around(hex, center, 1)

# 180°
var r3 := HexGrid.rotate_around(hex, center, 3)

# Counter-clockwise
var ccw := HexGrid.rotate_around(hex, center, -1)
```

`steps` is multiplied by 60°; negative values rotate the other way.

### Reflection

```gdscript
# axis: 0 = q, 1 = r, 2 = s
var mirrored := HexGrid.reflect(hex, 0)                 # across the q axis through (0,0)
var mirrored2 := HexGrid.reflect(hex, 2, some_center)   # across the s axis through some_center
```

Typical use: rotating a multi-hex structure (a building, a spell template) around a pivot:

```gdscript
func rotate_shape(shape: Array[Vector2i], pivot: Vector2i, steps: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for h in shape:
        out.append(HexGrid.rotate_around(h, pivot, steps))
    return out
```

---

## 13. Wraparound maps

For **hexagon-shaped** maps centered on `(0, 0)`:

```gdscript
var radius := 6
var next := hex + HexGrid.DIRECTIONS[0]
next = HexGrid.wrap_hexagon(next, radius)   # returns a hex on the opposite side if it left the map
```

`wrap_hexagon` handles coordinates that are about one step off the edge. It's designed for movement (neighbor steps), not for wrapping arbitrary far-away coordinates. Rectangular wraparound is easier with offset coordinates and modulo arithmetic on columns or rows; convert with `axial_to_offset` / `offset_to_axial`.

---

## 14. Pathfinding, movement range and field of view

### 14.1 How costs work

- The cost of a step is the `move_cost` of the cell being **entered**.
- Non-walkable cells and cells that don't exist are never entered.
- The start and goal must both be walkable.

### 14.2 `find_path(start, goal) -> Array[Vector2i]`

A\* search. Returns the path **including** start and goal, or an empty array if unreachable.

```gdscript
var path := grid.find_path(Vector2i(0, 0), Vector2i(4, -1))
if path.is_empty():
    print("No route")
else:
    print("Steps: ", path.size() - 1, " cost: ", grid.path_cost(path))
```

The heuristic is `distance * (cheapest walkable move_cost)`, which keeps it admissible, so paths are optimal even with varied terrain costs. Because a `Dictionary`-backed map is used, A\* works on any map shape.

### 14.3 `path_cost(path) -> float`

Total cost of a path from `find_path`, excluding the start hex.

### 14.4 `reachable(start, max_cost) -> Dictionary`

Dijkstra flood fill. Returns `{ coord: total_cost }` for every hex reachable within `max_cost`, including the start (cost 0).

```gdscript
var reach := grid.reachable(unit_hex, 4.0)
grid.highlight(reach.keys(), Color(0.3, 0.6, 1.0, 0.4))
```

With all move costs at 1.0 this behaves like a distance-limited flood fill (breadth-first search) that respects obstacles.

### 14.5 `field_of_view(origin, vision_range) -> Array[Vector2i]`

Line-of-sight FOV: a hex in range is visible if the line from `origin` to it passes through no cell with `blocks_sight`. Blocking hexes themselves are visible (you can see a wall, not through it). Hexes whose line crosses a gap in the map (missing cells) are treated as blocked.

```gdscript
grid.set_blocks_sight(Vector2i(2, 0), true)
var seen := grid.field_of_view(Vector2i(0, 0), 6)
grid.highlight(seen, Color(1, 1, 0.5, 0.3))
```

---

## 15. Highlights and rendering

### Overlay highlights

```gdscript
grid.highlight(some_hexes, Color(0.9, 0.3, 0.3, 0.5))   # add / overwrite
grid.clear_highlights()                                  # remove all
```

A highlight **replaces** the cell's fill while it is active. It is not blended with the base color, so use a color that reads well on its own (a semi-transparent color will show the window background through it). If you apply several highlights to the same hex, the last call wins, so apply them in the order you want them layered (for example movement range first, then the path).

### Draw order

For each cell: fill (highlight → custom color → wall color → default fill), then the outline. After all cells: hover overlay, selected overlay and outline, then optional coordinate labels.

### Hover and selection

```gdscript
grid.selected = Vector2i(2, 1)      # assign directly...
grid.queue_redraw()                 # ...and request a redraw

grid.selected = HexGrid.INVALID     # clear selection
```

`hovered` is updated automatically from mouse motion when `interactive` is true.

### Custom drawing on top

Because `HexGrid` is a `Node2D`, you can add child nodes (sprites, labels, your own `Node2D` with `_draw()`) and use `hex_to_pixel()` to place them. Child nodes draw above the grid.

---

## 16. Input and signals

### Signals

| Signal | Arguments | When |
|---|---|---|
| `hex_hovered` | `coord: Vector2i` | Hovered hex changed. `HexGrid.INVALID` when the mouse leaves the map. |
| `hex_clicked` | `coord: Vector2i, button: int` | A mouse button was pressed on a hex in the map. `button` is a `MOUSE_BUTTON_*` constant. |
| `cell_changed` | `coord: Vector2i` | Emitted by `add_cell`, `remove_cell`, `set_walkable`, `set_blocks_sight`. |

```gdscript
grid.hex_clicked.connect(func(coord, button):
    if button == MOUSE_BUTTON_LEFT:
        print("Select ", coord)
    elif button == MOUSE_BUTTON_RIGHT:
        grid.set_walkable(coord, not grid.is_walkable(coord))
)
```

### How input is received

Input uses `_unhandled_input()`. This means:

- UI `Control` nodes that consume the mouse event will block grid input (usually desired).
- If something else handles the click first, the grid won't see it.
- Set `interactive = false` and call `get_hex_at_mouse()` yourself if you want full manual control.

---

## 17. Recipes

### 17.1 Terrain types with different costs

```gdscript
const TERRAIN := {
    "grass":  {"cost": 1.0, "walkable": true,  "color": Color(0.25, 0.5, 0.25)},
    "forest": {"cost": 2.0, "walkable": true,  "color": Color(0.1, 0.35, 0.15)},
    "water":  {"cost": 1.0, "walkable": false, "color": Color(0.15, 0.3, 0.7)},
}

func set_terrain(coord: Vector2i, kind: String) -> void:
    var cell := grid.get_cell(coord)
    if cell == null:
        return
    var t: Dictionary = TERRAIN[kind]
    cell.data["terrain"] = kind
    cell.move_cost = t.cost
    cell.walkable = t.walkable
    cell.color = t.color
    grid.queue_redraw()
```

### 17.2 Click to move a unit along a path

```gdscript
var unit_hex := Vector2i.ZERO
@onready var unit: Node2D = $HexGrid/Unit     # a child of the grid

func _on_hex_clicked(coord: Vector2i, button: int) -> void:
    if button != MOUSE_BUTTON_LEFT:
        return
    var path := grid.find_path(unit_hex, coord)
    if path.size() < 2:
        return
    var tween := create_tween()
    for i in range(1, path.size()):
        tween.tween_property(unit, "position", grid.hex_to_pixel(path[i]), 0.15)
    unit_hex = coord
```

### 17.3 Movement range preview on hover

```gdscript
func _on_hex_hovered(coord: Vector2i) -> void:
    grid.clear_highlights()
    if coord == HexGrid.INVALID:
        return
    var reach := grid.reachable(coord, 3.0)
    grid.highlight(reach.keys(), Color(0.3, 0.6, 1.0, 0.4))
```

### 17.4 Fog of war

```gdscript
func update_fog(unit_hex: Vector2i, vision: int) -> void:
    var visible_set := {}
    for h in grid.field_of_view(unit_hex, vision):
        visible_set[h] = true
    grid.clear_highlights()
    var hidden: Array = []
    for c in grid.cells:
        if not visible_set.has(c):
            hidden.append(c)
    grid.highlight(hidden, Color(0, 0, 0, 0.75))
```

### 17.5 Area-of-effect attack

```gdscript
# Everything within 2 hexes of the target that exists on the map
var affected: Array[Vector2i] = []
for h in HexGrid.hexes_in_range(target, 2):
    if grid.has_cell(h):
        affected.append(h)

# A ring-shaped shockwave
var wave := HexGrid.ring(target, 3).filter(func(h): return grid.has_cell(h))
```

### 17.6 Cone / line attack

```gdscript
var beam := HexGrid.line(attacker, target)
for h in beam:
    if grid.get_cell(h) and grid.get_cell(h).blocks_sight:
        break   # beam stops at an opaque hex
```

### 17.7 Saving and loading a map

```gdscript
func save_map() -> Array:
    var out: Array = []
    for cell: HexGrid.HexCell in grid.cells.values():
        out.append({
            "q": cell.coord.x, "r": cell.coord.y,
            "walkable": cell.walkable,
            "cost": cell.move_cost,
            "sight": cell.blocks_sight,
            "data": cell.data,
        })
    return out

func load_map(rows: Array) -> void:
    var coords: Array[Vector2i] = []
    for row in rows:
        coords.append(Vector2i(row["q"], row["r"]))
    grid.set_cells(coords)
    for row in rows:
        var cell := grid.get_cell(Vector2i(row["q"], row["r"]))
        cell.walkable = row["walkable"]
        cell.move_cost = row["cost"]
        cell.blocks_sight = row["sight"]
        cell.data = row["data"]
    grid.queue_redraw()
```

Use `JSON.stringify()` / `FileAccess` to write the array to disk. Note that `Color` and `Vector2i` values inside `data` are not JSON-friendly; convert them yourself.

### 17.8 Rotating a structure placed on the grid

```gdscript
var building: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
var rotated := building.map(func(h): return HexGrid.rotate_around(h, Vector2i.ZERO, 2))
```

### 17.9 Switching orientation at runtime

```gdscript
grid.orientation = HexGrid.HexOrientation.FLAT
```

Coordinates remain valid; only the pixel layout changes. For `RECTANGLE` maps the visual layout will no longer be a clean rectangle in the new orientation, because the rectangle was generated using the other offset type. Call `generate()` after changing orientation to regenerate it properly.

### 17.10 Using multiple grids

Each `HexGrid` is independent. Put several in one scene (a world map and a battle map, for example) and position them as you would any `Node2D`.

---

## 18. Using the math without a node

All `static` functions work with no instance and no scene tree:

```gdscript
var d := HexGrid.distance(a, b)
var line := HexGrid.line(a, b)
var area := HexGrid.hexes_in_range(c, 4)
var offset := HexGrid.axial_to_offset(a, HexGrid.OffsetType.EVEN_Q)
```

You can also create an instance purely for logic. `HexGrid.new()` followed by `generate()` or `set_cells()` gives you pathfinding and field of view on the data. In that case free it manually when done (`grid.free()`) since it never enters the tree. The pixel functions depend on `hex_size` and `orientation`, which you can set before use.

---

## 19. Performance notes

- **Rendering** redraws every cell on each `queue_redraw()`. This is fine for a few thousand hexes. Very large maps (tens of thousands) may need chunking or a `TileMapLayer`/`MultiMesh` based renderer. The data and algorithms in this class can still drive them.
- **Highlights and hover** each trigger a redraw. Changing many highlights in one frame is fine because Godot coalesces `queue_redraw()` calls.
- **`field_of_view`** draws a line to every hex in range, so cost grows with `range² × range`. This is fine for typical radii (≤ 12) and may be slow for very large ones.
- **`find_path`** computes the minimum walkable cost by scanning all cells each call (O(n)) before searching. For very large maps with frequent pathing, you could cache that value.
- **Coordinates as dictionary keys**: `Vector2i` hashes well. Lookups are O(1).
- **Avoid per-frame full-map operations**. Rebuild highlights on events (hover change, click), not every `_process`.

---

## 20. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Nothing is drawn | The map is empty. Check `auto_generate`, or call `generate()` / `set_cells()`. Also check `hex_size` and that the node is in view. |
| Grid is off-screen | Hexagon maps center on the node's origin; other shapes start at (0,0) and extend right/down. Use `get_bounds()` to center. |
| Clicks do nothing | `interactive` is false, a `Control` is eating the mouse event, or the hex isn't in the map. |
| Click position is wrong | If you compute the hex yourself, remember to use `to_local()`. |
| `Cannot assign value of type ... Orientation` errors | You're using an old copy. The enum is named `HexOrientation` (Godot has its own global `Orientation`). |
| `set_cells()` type error | It requires `Array[Vector2i]`, not a plain `Array`. Build a typed array first (`var coords: Array[Vector2i] = []`). |
| Rectangle map looks like a parallelogram | You changed `orientation` after generating. Call `generate()` again. |
| Pathfinding returns `[]` | Start or goal is missing or not walkable, or the goal is walled off. |
| Cell changes don't show | You modified `HexCell` fields directly. Call `queue_redraw()` or use the setter methods. |
| `wrap_hexagon` returns the same hex | The input is more than about one step outside the map, or the map isn't a (0,0)-centered hexagon of that radius. |
| Doubled coordinate results look wrong | Doubled coordinates require `(col + row)` to be even. |

---

## 21. Limitations

- **Field of view** is the simple "draw a line to each hex" approach. Depending on your game, you may want a different visibility definition (partial hexes, shadow casting, symmetric vision).
- **Line drawing** can occasionally touch a hex slightly off the ideal line. This is inherent to the sampling method.
- **Wraparound** is provided for hexagon-shaped maps only.
- **Rendering** is a simple `_draw()` renderer without textures, per-hex sprites, or batching. It is intended as a clear foundation, not a final-art solution.
- **Pixel-to-hex for doubled coordinates** is done through axial. There is no direct doubled-coordinate path.
- **Costs** are per entered cell, and there is no per-edge cost or one-way movement.
- **Engine version**: typed constant arrays are used, so Godot 4.2 or newer is recommended. If you hit a version-specific error, check this first.

---

## 22. Full API reference

### Enums

| Enum | Values |
|---|---|
| `HexOrientation` | `POINTY`, `FLAT` |
| `Shape` | `HEXAGON`, `RECTANGLE`, `RHOMBUS`, `TRIANGLE` |
| `OffsetType` | `ODD_R`, `EVEN_R`, `ODD_Q`, `EVEN_Q` |

### Constants

| Constant | Description |
|---|---|
| `SQRT3` | √3 |
| `INVALID` | `Vector2i(2147483647, 2147483647)`, the "no hex" sentinel |
| `DIRECTIONS` | Six axial neighbor offsets |
| `DIAGONALS` | Six axial diagonal offsets |

### Signals

`hex_hovered(coord)`, `hex_clicked(coord, button)`, `cell_changed(coord)`

### Instance state

| Member | Description |
|---|---|
| `cells: Dictionary` | `Vector2i → HexCell` |
| `hovered: Vector2i` | Currently hovered hex (`INVALID` if none) |
| `selected: Vector2i` | Selected hex (`INVALID` if none) |

### Instance methods

| Method | Returns | Description |
|---|---|---|
| `generate()` | | Rebuild the map from `shape` and size settings. |
| `set_cells(coords: Array[Vector2i])` | | Replace the whole map; clears highlights, hover, selection. |
| `add_cell(coord)` | `HexCell` | Add a cell (returns the existing one if present). |
| `remove_cell(coord)` | | Remove a cell. |
| `has_cell(coord)` | `bool` | |
| `get_cell(coord)` | `HexCell` | `null` if missing. |
| `is_walkable(coord)` | `bool` | |
| `set_walkable(coord, value)` | | |
| `set_blocks_sight(coord, value)` | | |
| `set_cell_color(coord, color)` | | |
| `highlight(coords: Array, color)` | | Overlay colors. |
| `clear_highlights()` | | |
| `hex_to_pixel(hex)` | `Vector2` | |
| `pixel_to_hex(pos)` | `Vector2i` | |
| `pixel_to_hex_frac(pos)` | `Vector2` | |
| `get_hex_at_mouse()` | `Vector2i` | `INVALID` if none. |
| `hex_corners(hex)` | `PackedVector2Array` | |
| `get_bounds()` | `Rect2` | |
| `neighbors(hex)` | `Array[Vector2i]` | Existing neighbors. |
| `walkable_neighbors(hex)` | `Array[Vector2i]` | |
| `find_path(start, goal)` | `Array[Vector2i]` | A\*. |
| `path_cost(path)` | `float` | |
| `reachable(start, max_cost)` | `Dictionary` | `coord → cost`. |
| `field_of_view(origin, range)` | `Array[Vector2i]` | |

### Static methods

| Method | Returns | Description |
|---|---|---|
| `hexagon_coords(n)` | `Array[Vector2i]` | |
| `rectangle_coords(w, h, orient)` | `Array[Vector2i]` | |
| `rhombus_coords(w, h)` | `Array[Vector2i]` | |
| `triangle_coords(n)` | `Array[Vector2i]` | |
| `axial_to_cube(a)` / `cube_to_axial(c)` | `Vector3i` / `Vector2i` | |
| `axial_to_offset(a, type)` / `offset_to_axial(o, type)` | `Vector2i` | |
| `axial_to_doublewidth` / `doublewidth_to_axial` | `Vector2i` | |
| `axial_to_doubleheight` / `doubleheight_to_axial` | `Vector2i` | |
| `hex_round(q, r)` | `Vector2i` | |
| `neighbor(hex, dir)` | `Vector2i` | |
| `diagonal_neighbor(hex, dir)` | `Vector2i` | |
| `distance(a, b)` | `int` | |
| `line(a, b)` | `Array[Vector2i]` | |
| `hexes_in_range(center, n)` | `Array[Vector2i]` | |
| `intersect_ranges(ranges)` | `Array[Vector2i]` | |
| `ring(center, radius)` | `Array[Vector2i]` | |
| `spiral(center, radius)` | `Array[Vector2i]` | |
| `hexagon_count(n)` | `int` | |
| `rotate_around(hex, center, steps)` | `Vector2i` | |
| `reflect(hex, axis, center)` | `Vector2i` | |
| `wrap_hexagon(hex, radius)` | `Vector2i` | |

### `HexCell`

Fields: `coord`, `walkable`, `move_cost`, `blocks_sight`, `color`, `data`.

---

## 23. Credits

The algorithms and coordinate systems are based on Amit Patel's *Hexagonal Grids* guide at Red Blob Games (https://www.redblobgames.com/grids/hexagons/), which in turn builds on the work of Charles Fu and Clark Verbrugge.
