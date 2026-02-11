extends Node3D
class_name CellarGenerator

# -------------------------
# Scene hooks
# -------------------------
@export var world_root_path: NodePath = NodePath("../World")
@export var trigger_areas_path: NodePath = NodePath("../TriggerAreas")

@export var block_scene: PackedScene
@export var exit_scene: PackedScene # optional (not used yet)

# Player spawn marker in the level scene (Marker3D recommended)
@export var spawn_marker_path: NodePath = NodePath("SpawnPoints/Spawn")

# -------------------------
# Grid / block settings
# -------------------------
@export var block_size_m: float = 2.0
@export var y_offset_m: float = 1.0              # 2m cube centered -> bottom touches y=0 when center at y=1
@export var wall_height_blocks: int = 2          # doorway height is exactly this (2 blocks tall)
@export var build_ceiling: bool = false
@export var use_generator_as_origin: bool = true

# -------------------------
# Generation tuning
# -------------------------
@export var initial_room_size: Vector2i = Vector2i(6, 6)
@export var min_room_size: Vector2i = Vector2i(4, 4)
@export var max_room_size: Vector2i = Vector2i(10, 10)
@export var max_rooms_total: int = 12

# Corridor behavior
@export var stub_len_cells: int = 2              # corridor length BEFORE trigger
@export var corridor_extra_min_main: int = 3     # MAIN path corridor extra length AFTER trigger
@export var corridor_extra_max_main: int = 6
@export var corridor_extra_min_side: int = 1     # SIDE path corridor extra length AFTER trigger
@export var corridor_extra_max_side: int = 3

# Side-path variety
@export var side_deadend_chance_percent: int = 60 # 0..100
@export var deadend_extra_min: int = 1
@export var deadend_extra_max: int = 2

# Keep triggers active (you have 2 triggers)
@export var desired_active_triggers: int = 2

# Avoid corners for door placements
@export var corner_inset_cells: int = 1

# Heights
@export var trigger_height_above_floor: float = 0.35
@export var spawn_height_above_floor: float = 7.0  # raise spawn marker up so player doesn't clip

# Multiplayer authority
@export var authority_only_generation: bool = true

# Debug
@export var debug_print: bool = true

# -------------------------
# Cached nodes
# -------------------------
@onready var _world_root: Node3D = get_node_or_null(world_root_path) as Node3D
@onready var _triggers_root: Node3D = get_node_or_null(trigger_areas_path) as Node3D
@onready var _spawn_marker: Node3D = get_node_or_null(spawn_marker_path) as Node3D

# -------------------------
# Internal state
# -------------------------
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_origin: Vector3 = Vector3.ZERO

# Walkable footprint cells (rooms + corridors + stubs)
var _cells: Dictionary = {} # Vector2i -> bool

# Spawned blocks (for removal / doorway carving / caps)
var _spawned: Dictionary = {} # String "x:y:z" -> Node3D

# Frontier sites:
# {
#   "door_cell": Vector2i,      # wall cell on room perimeter (where we carve doorway)
#   "dir": Vector2i,            # outward direction
#   "trigger_cell": Vector2i,   # end of stub corridor (trigger sits here)
#   "cap_cell": Vector2i,       # one cell past trigger (solid cap so you don't see void)
#   "trigger_name": StringName, # assigned trigger node name
#   "kind": StringName          # "main" or "side"
# }
var _frontier: Array[Dictionary] = []
var _room_count: int = 0

# Trigger pool
var _trigger_pool: Array[Area3D] = []

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

# ============================================================
# READY
# ============================================================
func _ready() -> void:
	_rng.randomize()

	if _world_root == null:
		push_error("[Generator] World root not found. Set world_root_path.")
		return
	if _triggers_root == null:
		push_error("[Generator] TriggerAreas root not found. Set trigger_areas_path.")
		return
	if block_scene == null:
		push_error("[Generator] block_scene is not assigned.")
		return

	_world_origin = global_position if use_generator_as_origin else Vector3.ZERO

	_cache_trigger_pool()
	call_deferred("_generate_initial")

# ============================================================
# INITIAL ROOM
# ============================================================
func _generate_initial() -> void:
	_clear_world()
	_cells.clear()
	_spawned.clear()
	_frontier.clear()
	_room_count = 0

	# Clients wait for server
	if authority_only_generation and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var origin := Vector2i(-int(initial_room_size.x / 2), -int(initial_room_size.y / 2))
	_add_room(origin, initial_room_size)
	_room_count = 1

	_create_frontier_for_room(origin, initial_room_size, Vector2i.ZERO)
	_assign_triggers_to_frontier()

	_place_spawn_marker(origin, initial_room_size)

	if debug_print:
		print("[Generator] Initial room generated. rooms=", _room_count, " frontier=", _frontier.size())

# ============================================================
# TRIGGERS
# ============================================================
func _cache_trigger_pool() -> void:
	_trigger_pool.clear()

	for c in _triggers_root.get_children():
		var a := c as Area3D
		if a == null:
			continue
		_trigger_pool.append(a)

		if not a.body_entered.is_connected(_on_trigger_entered):
			a.body_entered.connect(_on_trigger_entered.bind(a))

		a.set_meta("active", false)
		a.set_deferred("monitoring", false)
		a.visible = true

	if debug_print:
		print("[Generator] Trigger pool size:", _trigger_pool.size())

func _on_trigger_entered(body: Node3D, area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if area == null:
		return

	# Authority-only generation
	if authority_only_generation and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not bool(area.get_meta("active", false)):
		return

	# DO NOT touch monitoring here (physics locked). Defer everything.
	area.set_meta("active", false)
	call_deferred("_handle_trigger_deferred", area)

func _handle_trigger_deferred(area: Area3D) -> void:
	if area == null or not is_instance_valid(area):
		return

	# Safe now
	area.set_deferred("monitoring", false)

	var trig_name: StringName = area.name
	var site_idx: int = _find_frontier_by_trigger(trig_name)
	if site_idx < 0:
		return

	var site: Dictionary = _frontier[site_idx]
	_frontier.remove_at(site_idx)

	var door_cell: Vector2i = site.get("door_cell", Vector2i.ZERO)
	var dir: Vector2i = site.get("dir", Vector2i.ZERO)
	var trigger_cell: Vector2i = site.get("trigger_cell", Vector2i.ZERO)
	var cap_cell: Vector2i = site.get("cap_cell", trigger_cell + dir)
	var kind: StringName = StringName(site.get("kind", StringName("side")))

	if debug_print:
		print("[Generator] Trigger hit:", trig_name, " kind=", kind, " trigger_cell=", trigger_cell, " door_cell=", door_cell, " dir=", dir)

	_expand_from_frontier(door_cell, dir, trigger_cell, cap_cell, kind)

	# Assignment toggles monitoring => defer it too (extra safe)
	call_deferred("_assign_triggers_to_frontier")

func _find_frontier_by_trigger(trig_name: StringName) -> int:
	for i in range(_frontier.size()):
		var s: Dictionary = _frontier[i]
		if StringName(s.get("trigger_name", StringName(""))) == trig_name:
			return i
	return -1

# ============================================================
# EXPANSION (VARIETY + SEAMLESS CAPS)
# ============================================================
func _expand_from_frontier(door_cell_old: Vector2i, dir: Vector2i, trigger_cell: Vector2i, cap_cell: Vector2i, kind: StringName) -> void:
	if _room_count >= max_rooms_total:
		if debug_print:
			print("[Generator] Max rooms reached; ignoring expansion.")
		return

	# Remove the cap first so player never sees "void"
	_remove_cap_wall(cap_cell)

	# SIDE: optionally dead-end
	if kind != StringName("main"):
		var roll: int = _rng.randi_range(0, 99)
		if roll < clampi(side_deadend_chance_percent, 0, 100):
			var extra_dead: int = _rng.randi_range(deadend_extra_min, deadend_extra_max)
			var end_cell: Vector2i = trigger_cell + dir * extra_dead

			_build_corridor_line(trigger_cell + dir, end_cell, dir)

			# Cap it again immediately
			_place_cap_wall(end_cell + dir)

			if debug_print:
				print("[Generator] SIDE dead-end created. end_cell=", end_cell)

			# No new room, no new frontier from this site.
			return

	# Choose corridor length by kind
	var extra_len: int = 0
	if kind == StringName("main"):
		extra_len = _rng.randi_range(corridor_extra_min_main, corridor_extra_max_main)
	else:
		extra_len = _rng.randi_range(corridor_extra_min_side, corridor_extra_max_side)

	# Extend corridor outward from trigger_cell
	var corridor_end: Vector2i = trigger_cell + dir * extra_len
	_build_corridor_line(trigger_cell + dir, corridor_end, dir)

	# New room doorway cell is one more step past corridor end
	var door_cell_new: Vector2i = corridor_end + dir

	# Pick room size
	var rw: int = _rng.randi_range(min_room_size.x, max_room_size.x)
	var rd: int = _rng.randi_range(min_room_size.y, max_room_size.y)
	var room_size := Vector2i(rw, rd)

	# Compute room origin so that door_cell_new lies on the wall facing back (-dir)
	var origin := _origin_from_door(door_cell_new, room_size, dir)

	# Reroll if overlap
	if _room_overlaps(origin, room_size):
		for _i in range(12):
			rw = _rng.randi_range(min_room_size.x, max_room_size.x)
			rd = _rng.randi_range(min_room_size.y, max_room_size.y)
			room_size = Vector2i(rw, rd)
			origin = _origin_from_door(door_cell_new, room_size, dir)
			if not _room_overlaps(origin, room_size):
				break

	# Still overlaps? cap corridor end and stop (prevents open void)
	if _room_overlaps(origin, room_size):
		_place_cap_wall(door_cell_new) # block it off
		if debug_print:
			print("[Generator] Expansion overlap -> capped at door_cell_new=", door_cell_new)
		return

	# Build room
	_add_room(origin, room_size)

	# Carve doorway columns (exactly wall_height_blocks tall) at old door and new door
	_remove_wall_column(door_cell_old)
	_remove_wall_column(door_cell_new)

	_room_count += 1

	# New frontier:
	# - If MAIN, always add new frontier sites
	# - If SIDE, add them only sometimes (keeps a directed path)
	var add_more: bool = (kind == StringName("main")) or (_rng.randi_range(0, 99) < 35)
	if add_more:
		_create_frontier_for_room(origin, room_size, dir)

	if debug_print:
		print("[Generator] Expanded. rooms=", _room_count, " kind=", kind, " new_room_origin=", origin, " size=", room_size)

func _origin_from_door(door_cell_new: Vector2i, size: Vector2i, dir: Vector2i) -> Vector2i:
	# dir = direction corridor is approaching the new room from.
	# Door must be on wall facing back (-dir).

	var ox: int
	var oz: int

	if dir == Vector2i(1, 0):
		# approaching from west -> door on WEST wall (x = origin.x)
		ox = door_cell_new.x
		oz = door_cell_new.y - int(size.y / 2)
	elif dir == Vector2i(-1, 0):
		# approaching from east -> door on EAST wall (x = origin.x + size.x - 1)
		ox = door_cell_new.x - (size.x - 1)
		oz = door_cell_new.y - int(size.y / 2)
	elif dir == Vector2i(0, 1):
		# approaching from south -> door on SOUTH wall (z = origin.y)
		oz = door_cell_new.y
		ox = door_cell_new.x - int(size.x / 2)
	else:
		# approaching from north -> door on NORTH wall (z = origin.y + size.y - 1)
		oz = door_cell_new.y - (size.y - 1)
		ox = door_cell_new.x - int(size.x / 2)

	return Vector2i(ox, oz)

func _room_overlaps(origin: Vector2i, size: Vector2i) -> bool:
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			if _cells.has(Vector2i(x, z)):
				return true
	return false

# ============================================================
# ROOM BUILD (floor + perimeter walls + optional ceiling)
# ============================================================
func _add_room(origin: Vector2i, size: Vector2i) -> void:
	# mark walkable footprint
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			_cells[Vector2i(x, z)] = true

	# floors
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			_spawn_block_at_cell(x, 0, z)

	# perimeter walls
	for x in range(origin.x, origin.x + size.x):
		for z in range(origin.y, origin.y + size.y):
			var is_perimeter: bool = (x == origin.x) or (x == origin.x + size.x - 1) or (z == origin.y) or (z == origin.y + size.y - 1)
			if not is_perimeter:
				continue
			for h in range(1, wall_height_blocks + 1):
				_spawn_block_at_cell(x, h, z)

	# ceiling
	if build_ceiling:
		var ceiling_h: int = wall_height_blocks + 1
		for x in range(origin.x, origin.x + size.x):
			for z in range(origin.y, origin.y + size.y):
				_spawn_block_at_cell(x, ceiling_h, z)

# ============================================================
# FRONTIER DOORWAYS + STUB CORRIDORS (WITH CAPS)
# ============================================================
func _create_frontier_for_room(origin: Vector2i, size: Vector2i, back_dir: Vector2i) -> void:
	var o: Vector2i = origin
	var w: int = size.x
	var d: int = size.y

	var inset: int = clampi(corner_inset_cells, 0, max(0, min(w, d) - 1))
	var mid_z: int = clampi(o.y + int(d / 2), o.y + inset, o.y + d - 1 - inset)
	var mid_x: int = clampi(o.x + int(w / 2), o.x + inset, o.x + w - 1 - inset)

	_try_add_frontier(Vector2i(o.x + w - 1, mid_z), Vector2i(1, 0), back_dir)
	_try_add_frontier(Vector2i(o.x,         mid_z), Vector2i(-1, 0), back_dir)
	_try_add_frontier(Vector2i(mid_x, o.y + d - 1), Vector2i(0, 1), back_dir)
	_try_add_frontier(Vector2i(mid_x, o.y),         Vector2i(0, -1), back_dir)

func _try_add_frontier(door_cell: Vector2i, dir: Vector2i, back_dir: Vector2i) -> void:
	# prevent immediate bounce-back into the room we came from
	if back_dir != Vector2i.ZERO and dir == -back_dir:
		return

	# outward cell must be empty
	var out: Vector2i = door_cell + dir
	if _cells.has(out):
		return

	# build a short stub corridor so trigger is reachable
	var stub_end: Vector2i = door_cell + dir * stub_len_cells

	# ensure stub path cells are empty
	for i in range(1, stub_len_cells + 1):
		var c: Vector2i = door_cell + dir * i
		if _cells.has(c):
			return

	# carve doorway in the room wall (2 blocks tall)
	_remove_wall_column(door_cell)

	# build stub corridor cells
	_build_corridor_line(door_cell + dir, stub_end, dir)

	# cap one cell past trigger so the player doesn't see void
	var cap_cell: Vector2i = stub_end + dir
	_place_cap_wall(cap_cell)

	# record frontier site
	_frontier.append({
		"door_cell": door_cell,
		"dir": dir,
		"trigger_cell": stub_end,
		"cap_cell": cap_cell,
		"trigger_name": StringName(""),
		"kind": StringName("side")
	})

	if debug_print:
		print("[Generator] Stub built. door=", door_cell, " dir=", dir, " stub_end=", stub_end, " cap=", cap_cell)

# Corridor line from start..end inclusive, along dir
func _build_corridor_line(start_cell: Vector2i, end_cell: Vector2i, dir: Vector2i) -> void:
	# perpendicular for side walls
	var perp: Vector2i = Vector2i(-dir.y, dir.x)

	# axis-aligned steps
	var steps: int = abs(end_cell.x - start_cell.x) + abs(end_cell.y - start_cell.y)

	for i in range(0, steps + 1):
		var c: Vector2i = start_cell + dir * i

		_cells[c] = true

		# corridor floor
		_spawn_block_at_cell(c.x, 0, c.y)

		# side wall columns (solid)
		var left: Vector2i = c + perp
		var right: Vector2i = c - perp

		_spawn_block_at_cell(left.x, 0, left.y)
		for h in range(1, wall_height_blocks + 1):
			_spawn_block_at_cell(left.x, h, left.y)

		_spawn_block_at_cell(right.x, 0, right.y)
		for h in range(1, wall_height_blocks + 1):
			_spawn_block_at_cell(right.x, h, right.y)

		# optional corridor ceiling
		if build_ceiling:
			var ceiling_h: int = wall_height_blocks + 1
			_spawn_block_at_cell(c.x, ceiling_h, c.y)

# ============================================================
# CAPS (SEAMLESS: NO VOID VIEWS)
# ============================================================
func _place_cap_wall(cell: Vector2i) -> void:
	# A full solid column at this cell blocks sight/void and acts like a closed door.
	_spawn_block_at_cell(cell.x, 0, cell.y)
	for h in range(1, wall_height_blocks + 1):
		_spawn_block_at_cell(cell.x, h, cell.y)
	if build_ceiling:
		var ceiling_h: int = wall_height_blocks + 1
		_spawn_block_at_cell(cell.x, ceiling_h, cell.y)

func _remove_cap_wall(cell: Vector2i) -> void:
	# Remove floor+wall+ceiling at the cap cell so corridor can continue.
	var floor_key: String = _key(cell.x, 0, cell.y)
	if _spawned.has(floor_key):
		var n0 := _spawned[floor_key] as Node
		if n0 != null and is_instance_valid(n0):
			n0.queue_free()
		_spawned.erase(floor_key)

	for h in range(1, wall_height_blocks + 1):
		var key: String = _key(cell.x, h, cell.y)
		if _spawned.has(key):
			var n := _spawned[key] as Node
			if n != null and is_instance_valid(n):
				n.queue_free()
			_spawned.erase(key)

	if build_ceiling:
		var ceiling_h: int = wall_height_blocks + 1
		var ck: String = _key(cell.x, ceiling_h, cell.y)
		if _spawned.has(ck):
			var cn := _spawned[ck] as Node
			if cn != null and is_instance_valid(cn):
				cn.queue_free()
			_spawned.erase(ck)

# ============================================================
# TRIGGER ASSIGNMENT (DEFERRED MONITORING)
# ============================================================
func _assign_triggers_to_frontier() -> void:
	if _trigger_pool.size() == 0:
		return
	if _frontier.size() == 0:
		return

	# Ensure exactly ONE "main" site exists (directed progression)
	var has_main: bool = false
	for s in _frontier:
		var sd: Dictionary = s
		if StringName(sd.get("kind", StringName("side"))) == StringName("main"):
			has_main = true
			break

	if not has_main:
		var idx_main: int = _find_unassigned_frontier()
		if idx_main >= 0:
			_frontier[idx_main]["kind"] = StringName("main")

	var trig_y: float = _floor_top_y() + trigger_height_above_floor

	# Clear bindings to triggers that are inactive
	for i in range(_frontier.size()):
		var tn: StringName = StringName(_frontier[i].get("trigger_name", StringName("")))
		if tn == StringName(""):
			continue
		var tnode := _triggers_root.get_node_or_null(String(tn)) as Area3D
		if tnode == null or not is_instance_valid(tnode) or not bool(tnode.get_meta("active", false)):
			_frontier[i]["trigger_name"] = StringName("")

	# Count current active triggers
	var active: int = 0
	for t in _trigger_pool:
		if t != null and is_instance_valid(t) and bool(t.get_meta("active", false)):
			active += 1

	# Activate triggers on unassigned frontier sites
	for t in _trigger_pool:
		if active >= desired_active_triggers:
			break
		if t == null or not is_instance_valid(t):
			continue
		if bool(t.get_meta("active", false)):
			continue

		var idx: int = _find_unassigned_frontier()
		if idx < 0:
			break

		var site: Dictionary = _frontier[idx]
		var trig_cell: Vector2i = site.get("trigger_cell", Vector2i.ZERO)

		var wp := _cell_to_world(trig_cell)
		wp.y = trig_y

		t.global_position = wp
		t.set_meta("active", true)
		t.set_deferred("monitoring", true) # IMPORTANT (no lock issues)

		_frontier[idx]["trigger_name"] = t.name
		active += 1

		if debug_print:
			print("[Generator] Trigger ", t.name, " placed at trigger_cell=", trig_cell, " kind=", site.get("kind", StringName("side")), " (door=", site.get("door_cell", Vector2i.ZERO), ")")

func _find_unassigned_frontier() -> int:
	for i in range(_frontier.size()):
		if StringName(_frontier[i].get("trigger_name", StringName(""))) == StringName(""):
			return i
	return -1

# ============================================================
# DOORWAY CARVING (2 blocks tall)
# ============================================================
func _remove_wall_column(cell: Vector2i) -> void:
	for h in range(1, wall_height_blocks + 1):
		var key: String = _key(cell.x, h, cell.y)
		if _spawned.has(key):
			var n := _spawned[key] as Node
			if n != null and is_instance_valid(n):
				n.queue_free()
			_spawned.erase(key)

# ============================================================
# SPAWN MARKER (stop spawning in the ground)
# ============================================================
func _place_spawn_marker(origin: Vector2i, size: Vector2i) -> void:
	if _spawn_marker == null or not is_instance_valid(_spawn_marker):
		return

	# Server decides spawn position; clients should receive spawn via your NetSceneManager
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var center_cell := Vector2i(origin.x + int(size.x / 2), origin.y + int(size.y / 2))
	var p := _cell_to_world(center_cell)
	p.y = _floor_top_y() + spawn_height_above_floor

	_spawn_marker.global_position = p

	if debug_print:
		print("[Generator] Spawn marker moved to center_cell=", center_cell, " pos=", p)

# ============================================================
# BLOCK SPAWNING
# ============================================================
func _spawn_block_at_cell(x: int, y_level_blocks: int, z: int) -> void:
	var key: String = _key(x, y_level_blocks, z)
	if _spawned.has(key):
		return

	var inst := block_scene.instantiate() as Node3D
	if inst == null:
		return

	_world_root.add_child(inst)

	var wp := _cell_to_world(Vector2i(x, z))
	wp.y = _world_origin.y + y_offset_m + float(y_level_blocks) * block_size_m
	inst.global_position = wp

	_spawned[key] = inst

func _cell_to_world(cell: Vector2i) -> Vector3:
	var px := (float(cell.x) + 0.5) * block_size_m
	var pz := (float(cell.y) + 0.5) * block_size_m
	return _world_origin + Vector3(px, 0.0, pz)

func _floor_top_y() -> float:
	# floor block center is y_offset_m; top is + block_size/2
	return _world_origin.y + y_offset_m + (block_size_m * 0.5)

func _key(x: int, y: int, z: int) -> String:
	return "%d:%d:%d" % [x, y, z]

func _clear_world() -> void:
	for c in _world_root.get_children():
		c.queue_free()
