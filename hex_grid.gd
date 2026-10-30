class_name HexGrid
extends Node2D
## Hexagon grid for Godot 4: axial-coordinate storage, hex math, pathfinding, FOV and rendering.
## Based on Red Blob Games' "Hexagonal Grids". Positions are local to this node. See README.md.

signal hex_hovered(coord: Vector2i)
signal hex_clicked(coord: Vector2i, button: int)
signal cell_changed(coord: Vector2i)

enum HexOrientation { POINTY, FLAT }
enum Shape { HEXAGON, RECTANGLE, RHOMBUS, TRIANGLE }
enum OffsetType { ODD_R, EVEN_R, ODD_Q, EVEN_Q }

const SQRT3: float = 1.7320508075688772
## Sentinel meaning "no hex" (see get_hex_at_mouse, hovered, selected).
const INVALID: Vector2i = Vector2i(2147483647, 2147483647)

## Six axial neighbor offsets, counter-clockwise on screen. Index 0 is East (pointy) or South-east (flat).
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const DIAGONALS: Array[Vector2i] = [
	Vector2i(2, -1), Vector2i(1, -2), Vector2i(-1, -1),
	Vector2i(-2, 1), Vector2i(-1, 2), Vector2i(1, 1),
]

# --- Configuration ---
@export_group("Layout")
@export var orientation: HexOrientation = HexOrientation.POINTY:
	set(v):
		orientation = v
		_rebuild_geometry()
		queue_redraw()
@export_range(2.0, 256.0, 0.5) var hex_size: float = 32.0:
	set(v):
		hex_size = maxf(v, 1.0)
		_rebuild_geometry()
		queue_redraw()

@export_group("Generation")
@export var auto_generate: bool = true
@export var shape: Shape = Shape.HEXAGON
@export var radius: int = 6
@export var grid_width: int = 12
@export var grid_height: int = 8

@export_group("Look")
@export var fill_color: Color = Color(0.20, 0.24, 0.30)
@export var wall_color: Color = Color(0.08, 0.09, 0.11)
@export var line_color: Color = Color(0.55, 0.62, 0.72)
@export var hover_color: Color = Color(1.0, 1.0, 1.0, 0.25)
@export var selected_color: Color = Color(1.0, 0.85, 0.2, 0.55)
@export_range(0.5, 8.0, 0.5) var line_width: float = 1.5
@export var show_coords: bool = false:
	set(v):
		show_coords = v
		queue_redraw()
@export var interactive: bool = true

# --- Cells ---
class HexCell extends RefCounted:
	var coord: Vector2i
	var walkable: bool = true
	## Cost to enter this cell.
	var move_cost: float = 1.0
	var blocks_sight: bool = false
	## Custom fill. Alpha 0 uses the grid's default colors.
	var color: Color = Color(0, 0, 0, 0)
	var data: Dictionary = {}

	func _init(c: Vector2i) -> void:
		coord = c

var cells: Dictionary[Vector2i, HexCell] = {}
var hovered: Vector2i = INVALID
var selected: Vector2i = INVALID
var _highlights: Dictionary[Vector2i, Color] = {}

var _corners: PackedVector2Array = PackedVector2Array()
var _outline: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_rebuild_geometry()


func _ready() -> void:
	_rebuild_geometry()
	if auto_generate and cells.is_empty():
		generate()


# --- Map generation and cells ---

func generate() -> void:
	var coords: Array[Vector2i]
	match shape:
		Shape.HEXAGON: coords = hexagon_coords(radius)
		Shape.RECTANGLE: coords = rectangle_coords(grid_width, grid_height, orientation)
		Shape.RHOMBUS: coords = rhombus_coords(grid_width, grid_height)
		Shape.TRIANGLE: coords = triangle_coords(radius)
	set_cells(coords)


func set_cells(coords: Array[Vector2i]) -> void:
	cells.clear()
	_highlights.clear()
	hovered = INVALID
	selected = INVALID
	for c: Vector2i in coords:
		cells[c] = HexCell.new(c)
	queue_redraw()


func add_cell(coord: Vector2i) -> HexCell:
	if not cells.has(coord):
		cells[coord] = HexCell.new(coord)
		cell_changed.emit(coord)
		queue_redraw()
	return cells[coord]


func remove_cell(coord: Vector2i) -> void:
	if cells.erase(coord):
		_highlights.erase(coord)
		cell_changed.emit(coord)
		queue_redraw()


func has_cell(coord: Vector2i) -> bool:
	return cells.has(coord)


func get_cell(coord: Vector2i) -> HexCell:
	return cells.get(coord)


func is_walkable(coord: Vector2i) -> bool:
	var c: HexCell = cells.get(coord)
	return c != null and c.walkable


func set_walkable(coord: Vector2i, value: bool) -> void:
	var c: HexCell = cells.get(coord)
	if c:
		c.walkable = value
		cell_changed.emit(coord)
		queue_redraw()


func set_blocks_sight(coord: Vector2i, value: bool) -> void:
	var c: HexCell = cells.get(coord)
	if c:
		c.blocks_sight = value
		cell_changed.emit(coord)
		queue_redraw()


func set_cell_color(coord: Vector2i, color: Color) -> void:
	var c: HexCell = cells.get(coord)
	if c:
		c.color = color
		queue_redraw()


func highlight(coords: Array, color: Color) -> void:
	for c: Vector2i in coords:
		_highlights[c] = color
	queue_redraw()


func clear_highlights() -> void:
	_highlights.clear()
	queue_redraw()


# --- Shape generators (static) ---

static func hexagon_coords(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in range(-n, n + 1):
		for r: int in range(maxi(-n, -q - n), mini(n, -q + n) + 1):
			out.append(Vector2i(q, r))
	return out


static func rectangle_coords(w: int, h: int, orient: HexOrientation = HexOrientation.POINTY) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t: OffsetType = OffsetType.ODD_R if orient == HexOrientation.POINTY else OffsetType.ODD_Q
	for row: int in range(h):
		for col: int in range(w):
			out.append(offset_to_axial(Vector2i(col, row), t))
	return out


static func rhombus_coords(w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: int in range(h):
		for q: int in range(w):
			out.append(Vector2i(q, r))
	return out


static func triangle_coords(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: int in range(n + 1):
		for q: int in range(n + 1 - r):
			out.append(Vector2i(q, r))
	return out


# --- Coordinate conversion ---

static func axial_to_cube(a: Vector2i) -> Vector3i:
	return Vector3i(a.x, a.y, -a.x - a.y)


static func cube_to_axial(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.y)


static func axial_to_offset(a: Vector2i, type: OffsetType) -> Vector2i:
	var q: int = a.x
	var r: int = a.y
	match type:
		OffsetType.ODD_R:  return Vector2i(q + ((r - (r & 1)) >> 1), r)
		OffsetType.EVEN_R: return Vector2i(q + ((r + (r & 1)) >> 1), r)
		OffsetType.ODD_Q:  return Vector2i(q, r + ((q - (q & 1)) >> 1))
		_:                 return Vector2i(q, r + ((q + (q & 1)) >> 1))


static func offset_to_axial(o: Vector2i, type: OffsetType) -> Vector2i:
	var col: int = o.x
	var row: int = o.y
	match type:
		OffsetType.ODD_R:  return Vector2i(col - ((row - (row & 1)) >> 1), row)
		OffsetType.EVEN_R: return Vector2i(col - ((row + (row & 1)) >> 1), row)
		OffsetType.ODD_Q:  return Vector2i(col, row - ((col - (col & 1)) >> 1))
		_:                 return Vector2i(col, row - ((col + (col & 1)) >> 1))


## Doubled coordinates need (col + row) to be even.
static func axial_to_doublewidth(a: Vector2i) -> Vector2i:
	return Vector2i(2 * a.x + a.y, a.y)


static func doublewidth_to_axial(d: Vector2i) -> Vector2i:
	return Vector2i((d.x - d.y) >> 1, d.y)


static func axial_to_doubleheight(a: Vector2i) -> Vector2i:
	return Vector2i(a.x, 2 * a.y + a.x)


static func doubleheight_to_axial(d: Vector2i) -> Vector2i:
	return Vector2i(d.x, (d.y - d.x) >> 1)


# --- Pixel conversion (positions are local to this node) ---

func hex_to_pixel(h: Vector2i) -> Vector2:
	return _axial_to_pixel(float(h.x), float(h.y))


func _axial_to_pixel(q: float, r: float) -> Vector2:
	if orientation == HexOrientation.POINTY:
		return Vector2(SQRT3 * q + SQRT3 / 2.0 * r, 1.5 * r) * hex_size
	return Vector2(1.5 * q, SQRT3 / 2.0 * q + SQRT3 * r) * hex_size


func pixel_to_hex_frac(p: Vector2) -> Vector2:
	var x: float = p.x / hex_size
	var y: float = p.y / hex_size
	if orientation == HexOrientation.POINTY:
		return Vector2(SQRT3 / 3.0 * x - y / 3.0, 2.0 / 3.0 * y)
	return Vector2(2.0 / 3.0 * x, -x / 3.0 + SQRT3 / 3.0 * y)


func pixel_to_hex(p: Vector2) -> Vector2i:
	var f: Vector2 = pixel_to_hex_frac(p)
	return hex_round(f.x, f.y)


func get_hex_at_mouse() -> Vector2i:
	var h: Vector2i = pixel_to_hex(get_local_mouse_position())
	return h if cells.has(h) else INVALID


func hex_corners(h: Vector2i) -> PackedVector2Array:
	var center: Vector2 = hex_to_pixel(h)
	var out: PackedVector2Array = PackedVector2Array()
	for c: Vector2 in _corners:
		out.append(center + c)
	return out


func get_bounds() -> Rect2:
	if cells.is_empty():
		return Rect2()
	var first: bool = true
	var r: Rect2 = Rect2()
	for coord: Vector2i in cells:
		var center: Vector2 = hex_to_pixel(coord)
		var hex_rect: Rect2 = Rect2(center - Vector2(hex_size, hex_size), Vector2(hex_size, hex_size) * 2.0)
		r = hex_rect if first else r.merge(hex_rect)
		first = false
	return r


static func hex_round(fq: float, fr: float) -> Vector2i:
	var fs: float = -fq - fr
	var q: float = roundf(fq)
	var r: float = roundf(fr)
	var s: float = roundf(fs)
	var dq: float = absf(q - fq)
	var dr: float = absf(r - fr)
	var ds: float = absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	# else: s = -q - r (implicit, we only return q, r)
	return Vector2i(int(q), int(r))


# --- Neighbors and distance ---

static func neighbor(h: Vector2i, dir: int) -> Vector2i:
	return h + DIRECTIONS[posmod(dir, 6)]


static func diagonal_neighbor(h: Vector2i, dir: int) -> Vector2i:
	return h + DIAGONALS[posmod(dir, 6)]


func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRECTIONS:
		var n: Vector2i = h + d
		if cells.has(n):
			out.append(n)
	return out


func walkable_neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRECTIONS:
		var n: Vector2i = h + d
		if is_walkable(n):
			out.append(n)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) >> 1


# --- Lines, ranges, rings and spirals ---

static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n: int = distance(a, b)
	if n == 0:
		out.append(a)
		return out
	# Tiny nudge so samples never land exactly on hex edges (keeps lines consistent).
	var nudge: Vector2 = Vector2(1e-6, 2e-6)
	var fa: Vector2 = Vector2(a) + nudge
	var fb: Vector2 = Vector2(b) + nudge
	for i: int in range(n + 1):
		var p: Vector2 = fa.lerp(fb, float(i) / float(n))
		out.append(hex_round(p.x, p.y))
	return out


static func hexes_in_range(center: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in range(-n, n + 1):
		for r: int in range(maxi(-n, -q - n), mini(n, -q + n) + 1):
			out.append(center + Vector2i(q, r))
	return out


static func intersect_ranges(ranges: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if ranges.is_empty():
		return out
	var qmin: int = -2147483647
	var qmax: int = 2147483647
	var rmin: int = qmin
	var rmax: int = qmax
	var smin: int = qmin
	var smax: int = qmax
	for rg: Array in ranges:
		var c: Vector2i = rg[0]
		var n: int = rg[1]
		var s: int = -c.x - c.y
		qmin = maxi(qmin, c.x - n)
		qmax = mini(qmax, c.x + n)
		rmin = maxi(rmin, c.y - n)
		rmax = mini(rmax, c.y + n)
		smin = maxi(smin, s - n)
		smax = mini(smax, s + n)
	for q: int in range(qmin, qmax + 1):
		for r: int in range(maxi(rmin, -q - smax), mini(rmax, -q - smin) + 1):
			out.append(Vector2i(q, r))
	return out


static func ring(center: Vector2i, rad: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rad <= 0:
		out.append(center)
		return out
	var h: Vector2i = center + DIRECTIONS[4] * rad
	for i: int in range(6):
		for _j: int in range(rad):
			out.append(h)
			h += DIRECTIONS[i]
	return out


static func spiral(center: Vector2i, rad: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	for k: int in range(1, rad + 1):
		out.append_array(ring(center, k))
	return out


static func hexagon_count(n: int) -> int:
	return 1 + 3 * n * (n + 1)


# --- Rotation and reflection ---

## Rotates `h` around `center` by steps * 60° (positive = clockwise on screen).
static func rotate_around(h: Vector2i, center: Vector2i, steps: int) -> Vector2i:
	var v: Vector3i = axial_to_cube(h - center)
	for _i: int in range(posmod(steps, 6)):
		v = Vector3i(-v.y, -v.z, -v.x)
	return center + cube_to_axial(v)


## Reflects across the q (0), r (1) or s (2) axis through `center`.
static func reflect(h: Vector2i, axis: int, center: Vector2i = Vector2i.ZERO) -> Vector2i:
	var v: Vector3i = axial_to_cube(h - center)
	match axis:
		0: v = Vector3i(v.x, v.z, v.y)
		1: v = Vector3i(v.z, v.y, v.x)
		_: v = Vector3i(v.y, v.x, v.z)
	return center + cube_to_axial(v)


# --- Wraparound (hexagon maps centered on 0,0) ---

## For hexagon maps of radius `rad` centered on (0, 0): returns the matching hex on the opposite
## side if `h` is about one step off the map.
static func wrap_hexagon(h: Vector2i, rad: int) -> Vector2i:
	if distance(h, Vector2i.ZERO) <= rad:
		return h
	var mirror_center: Vector2i = Vector2i(2 * rad + 1, -rad)
	for i: int in range(6):
		var m: Vector2i = rotate_around(mirror_center, Vector2i.ZERO, i)
		var candidate: Vector2i = h - m
		if distance(candidate, Vector2i.ZERO) <= rad:
			return candidate
	return h


# --- Pathfinding, movement range and field of view ---

## Returns the path including start and goal, or [] if either isn't walkable or the goal is unreachable.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal):
		return path
	if start == goal:
		path.append(start)
		return path

	# Scale the heuristic by the cheapest walkable cost so it stays admissible.
	var min_cost: float = INF
	for c: HexCell in cells.values():
		if c.walkable:
			min_cost = minf(min_cost, c.move_cost)
	if min_cost == INF:
		return path

	var open: _MinHeap = _MinHeap.new()
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var g: Dictionary[Vector2i, float] = {start: 0.0}
	var closed: Dictionary[Vector2i, bool] = {}
	open.push(0.0, start)

	while not open.is_empty():
		var cur: Vector2i = open.pop()
		if cur == goal:
			break
		if closed.has(cur):
			continue
		closed[cur] = true
		for n: Vector2i in walkable_neighbors(cur):
			if closed.has(n):
				continue
			var ng: float = g[cur] + cells[n].move_cost
			if ng < g.get(n, INF):
				g[n] = ng
				came_from[n] = cur
				open.push(ng + distance(n, goal) * min_cost, n)

	if not came_from.has(goal):
		return path
	var step: Vector2i = goal
	while step != start:
		path.append(step)
		step = came_from[step]
	path.append(start)
	path.reverse()
	return path


func path_cost(path: Array[Vector2i]) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += cells[path[i]].move_cost
	return total


func reachable(start: Vector2i, max_cost: float) -> Dictionary[Vector2i, float]:
	var cost: Dictionary[Vector2i, float] = {}
	if not is_walkable(start):
		return cost
	var open: _MinHeap = _MinHeap.new()
	cost[start] = 0.0
	open.push(0.0, start)
	while not open.is_empty():
		var cur: Vector2i = open.pop()
		if open.last_priority > cost[cur]:
			continue
		for n: Vector2i in walkable_neighbors(cur):
			var nc: float = cost[cur] + cells[n].move_cost
			if nc <= max_cost and nc < cost.get(n, INF):
				cost[n] = nc
				open.push(nc, n)
	return cost


func field_of_view(origin: Vector2i, vision_range: int) -> Array[Vector2i]:
	var seen: Array[Vector2i] = []
	if not cells.has(origin):
		return seen
	for target: Vector2i in hexes_in_range(origin, vision_range):
		if not cells.has(target):
			continue
		var blocked: bool = false
		var l: Array[Vector2i] = line(origin, target)
		for i: int in range(1, l.size() - 1):
			var mid: HexCell = cells.get(l[i])
			if mid == null or mid.blocks_sight:
				blocked = true
				break
		if not blocked:
			seen.append(target)
	return seen


class _MinHeap extends RefCounted:
	var _pri: Array[float] = []
	var _val: Array[Vector2i] = []
	var last_priority: float = 0.0

	func is_empty() -> bool:
		return _val.is_empty()

	func push(p: float, v: Vector2i) -> void:
		_pri.append(p)
		_val.append(v)
		var i: int = _val.size() - 1
		while i > 0:
			var parent: int = (i - 1) >> 1
			if _pri[parent] <= _pri[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector2i:
		var top: Vector2i = _val[0]
		last_priority = _pri[0]
		var lp: float = _pri.pop_back()
		var lv: Vector2i = _val.pop_back()
		if not _val.is_empty():
			_pri[0] = lp
			_val[0] = lv
			var i: int = 0
			var n: int = _val.size()
			while true:
				var l: int = 2 * i + 1
				var r: int = l + 1
				var m: int = i
				if l < n and _pri[l] < _pri[m]:
					m = l
				if r < n and _pri[r] < _pri[m]:
					m = r
				if m == i:
					break
				_swap(i, m)
				i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tp: float = _pri[a]
		_pri[a] = _pri[b]
		_pri[b] = tp
		var tv: Vector2i = _val[a]
		_val[a] = _val[b]
		_val[b] = tv


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var h: Vector2i = get_hex_at_mouse()
		if h != hovered:
			hovered = h
			queue_redraw()
			hex_hovered.emit(h)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		var h: Vector2i = get_hex_at_mouse()
		if h != INVALID:
			hex_clicked.emit(h, mb.button_index)


# --- Rendering ---

func _rebuild_geometry() -> void:
	_corners = PackedVector2Array()
	var offset_deg: float = -30.0 if orientation == HexOrientation.POINTY else 0.0
	for i: int in range(6):
		var a: float = deg_to_rad(60.0 * i + offset_deg)
		_corners.append(Vector2(cos(a), sin(a)) * hex_size)
	_outline = _corners.duplicate()
	_outline.append(_corners[0])


## Fill priority: highlight, custom cell color, wall color, default. Then hover, selection and labels.
func _draw() -> void:
	if _corners.is_empty():
		return

	for coord: Vector2i in cells:
		var cell: HexCell = cells[coord]
		var col: Color
		if _highlights.has(coord):
			col = _highlights[coord]
		elif cell.color.a > 0.0:
			col = cell.color
		elif not cell.walkable:
			col = wall_color
		else:
			col = fill_color
		draw_set_transform(hex_to_pixel(coord), 0.0, Vector2.ONE)
		draw_colored_polygon(_corners, col)
		draw_polyline(_outline, line_color, line_width, true)

	if cells.has(hovered):
		draw_set_transform(hex_to_pixel(hovered), 0.0, Vector2.ONE)
		draw_colored_polygon(_corners, hover_color)
	if cells.has(selected):
		draw_set_transform(hex_to_pixel(selected), 0.0, Vector2.ONE)
		draw_colored_polygon(_corners, selected_color)
		draw_polyline(_outline, selected_color.lightened(0.4), line_width * 2.0, true)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if show_coords:
		var font: Font = ThemeDB.fallback_font
		var fsize: int = maxi(int(hex_size * 0.32), 6)
		for coord: Vector2i in cells:
			var c: Vector2 = hex_to_pixel(coord)
			draw_string(font, c + Vector2(-hex_size, fsize * 0.35), "%d,%d" % [coord.x, coord.y],
					HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, fsize, Color(1, 1, 1, 0.7))
