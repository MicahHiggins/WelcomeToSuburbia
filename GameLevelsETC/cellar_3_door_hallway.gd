extends Node3D
class_name CellarThreeDoorHallway

@export var world_root_path: NodePath = NodePath("../world")
@export var triggers_root_path: NodePath = NodePath("../TriggerArea")
@export var spawn_marker_path: NodePath = NodePath("../SpawnPoints/Spawn")
@export var block_scene: PackedScene

@export var block_size_m: float = 2.0
@export var y_offset_m: float = 1.0
@export var wall_height_blocks: int = 2
@export var build_ceiling: bool = false
@export var use_generator_as_origin: bool = true

@export var spawn_height_above_floor: float = 7.0
@export var spawn_cell_z: int = 2

@export var hall_width_cells: int = 7
@export var entry_len_before_doors: int = 10

@export var door_x_offsets: Array[int] = [-2, 0, 2]
@export var reveal_distance_cells: int = 2

@export var required_correct_choices: int = 3
@export var turn_chance_percent: int = 50
@export var corner_len: int = 4

@export var debug_print: bool = true

@onready var _world_root: Node3D = get_node_or_null(world_root_path) as Node3D
@onready var _triggers_root: Node3D = get_node_or_null(triggers_root_path) as Node3D
@onready var _spawn_marker: Node3D = get_node_or_null(spawn_marker_path) as Node3D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_origin: Vector3 = Vector3.ZERO
var _spawned: Dictionary = {} # String -> Node3D

var _seed: int = 0
var _built: bool = false

var _cursor: Vector2i = Vector2i(0, 0)
var _forward: Vector2i = Vector2i(0, 1)

var _correct_count: int = 0
var _progress_door: int = 0
var _revealed: Array[bool] = [false, false, false]

const DOOR_NAMES: Array[String] = ["Door1", "Door2", "Door3"]
const REVEAL_NAMES: Array[String] = ["Reveal1", "Reveal2", "Reveal3"]

func _ready() -> void:
	_rng.randomize()

	if _world_root == null:
		push_error("[Cellar] world root not found. Fix world_root_path.")
		return
	if _triggers_root == null:
		push_error("[Cellar] TriggerArea root not found. Fix triggers_root_path.")
		return
	if block_scene == null:
		push_error("[Cellar] block_scene not assigned.")
		return

	_world_origin = global_position if use_generator_as_origin else Vector3.ZERO

	# keep door offsets inside hall
	_clamp_door_offsets()

	_bind_trigger_signals()

	# server picks seed, everyone builds the same
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_seed = int(Time.get_ticks_msec()) ^ randi()
			rpc("_rpc_build_initial", _seed)
	else:
		_seed = int(Time.get_ticks_msec()) ^ randi()
		_build_initial(_seed)

func _clamp_door_offsets() -> void:
	var half_w: int = int(hall_width_cells / 2)
	for i in range(min(door_x_offsets.size(), 3)):
		# keep openings away from the side wall columns
		door_x_offsets[i] = clampi(door_x_offsets[i], -half_w + 1, half_w - 1)

@rpc("any_peer", "call_local", "reliable")
func _rpc_build_initial(seed: int) -> void:
	_build_initial(seed)

func _build_initial(seed: int) -> void:
	if _built:
		return
	_built = true

	_seed = seed
	_rng.seed = seed

	_clear_world()

	_cursor = Vector2i(0, 0)
	_forward = Vector2i(0, 1)
	_correct_count = 0
	_revealed = [false, false, false]

	_build_hub_geometry()
	_move_triggers_to_hub()
	_place_spawn_marker()

	if debug_print:
		print("[Cellar] built initial. seed=", _seed)

func _pick_progress_door_for_current_hub() -> int:
	var h: int = _seed ^ (_correct_count * 7919) ^ (_cursor.x * 101) ^ (_cursor.y * 10007)
	var local_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	local_rng.seed = h
	return local_rng.randi_range(0, 2)

func _build_hub_geometry() -> void:
	_progress_door = _pick_progress_door_for_current_hub()
	_revealed = [false, false, false]

	_build_hall_segment(_cursor, _forward, entry_len_before_doors)

	var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors
	_build_end_wall_with_three_doors(door_wall_cell, _forward)

	# "single block doors": no corridor behind.
	# cap 1 cell behind the doorway so it looks blocked until loop shifts.
	for i in range(3):
		var open_cell: Vector2i = _door_open_cell(door_wall_cell, _forward, door_x_offsets[i])
		_place_cap_wall(open_cell)

func _bind_trigger_signals() -> void:
	for i in range(3):
		var d: Area3D = _triggers_root.get_node_or_null(DOOR_NAMES[i]) as Area3D
		if d != null:
			d.set_meta("door_index", i)
			if not d.body_entered.is_connected(_on_door_entered):
				d.body_entered.connect(_on_door_entered.bind(d))

		var r: Area3D = _triggers_root.get_node_or_null(REVEAL_NAMES[i]) as Area3D
		if r != null:
			r.set_meta("door_index", i)
			if not r.body_entered.is_connected(_on_reveal_entered):
				r.body_entered.connect(_on_reveal_entered.bind(r))

func _move_triggers_to_hub() -> void:
	var y: float = _floor_top_y() + 0.8
	var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors

	for i in range(3):
		var door_cell: Vector2i = door_wall_cell + _right_vec(_forward) * door_x_offsets[i]

		var door_area: Area3D = _triggers_root.get_node_or_null(DOOR_NAMES[i]) as Area3D
		if door_area != null:
			var p: Vector3 = _cell_to_world(door_cell)
			p.y = y
			door_area.global_position = p

		var reveal_cell: Vector2i = door_cell - _forward * reveal_distance_cells
		var reveal_area: Area3D = _triggers_root.get_node_or_null(REVEAL_NAMES[i]) as Area3D
		if reveal_area != null:
			var rp: Vector3 = _cell_to_world(reveal_cell)
			rp.y = y
			reveal_area.global_position = rp

# -------------------------
# Reveal + door entered
# -------------------------
func _on_reveal_entered(body: Node3D, area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if area == null:
		return

	var idx: int = int(area.get_meta("door_index", -1))
	if idx < 0 or idx > 2:
		return

	# ✅ FIX: if we are the server, call directly (don’t rpc to ourselves)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_like_reveal(idx)
		else:
			rpc_id(1, "_rpc_request_reveal", idx)
	else:
		_server_like_reveal(idx)

func _on_door_entered(body: Node3D, door_area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if door_area == null:
		return

	var idx: int = int(door_area.get_meta("door_index", -1))
	if idx < 0 or idx > 2:
		return

	var owner_id: int = body.get_multiplayer_authority()

	# ✅ FIX: if we are the server, call directly (don’t rpc to ourselves)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_like_enter_door(idx, owner_id)
		else:
			rpc_id(1, "_rpc_request_enter_door", idx, owner_id)
	else:
		_server_like_enter_door(idx, owner_id)

@rpc("any_peer", "reliable")
func _rpc_request_reveal(door_idx: int) -> void:
	if not multiplayer.is_server():
		return
	_server_like_reveal(door_idx)

func _server_like_reveal(door_idx: int) -> void:
	if door_idx < 0 or door_idx > 2:
		return
	if _revealed[door_idx]:
		return

	_revealed[door_idx] = true

	if door_idx == _progress_door:
		rpc("_rpc_broadcast_message", "[Cellar] ...this one feels warmer. like the air is moving.")
	else:
		rpc("_rpc_broadcast_message", "[Cellar] ...dead quiet. like it doesn’t want you in there.")

@rpc("any_peer", "reliable")
func _rpc_request_enter_door(door_idx: int, player_owner_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_like_enter_door(door_idx, player_owner_id)

func _server_like_enter_door(door_idx: int, player_owner_id: int) -> void:
	if door_idx < 0 or door_idx > 2:
		return

	# must reveal first (they look identical until you check)
	if not _revealed[door_idx]:
		rpc("_rpc_broadcast_message", "[Cellar] all three look the same. get closer first.")
		return

	if _correct_count >= required_correct_choices:
		rpc("_rpc_broadcast_message", "[Cellar] you already cleared it.")
		return

	var was_progress: bool = (door_idx == _progress_door)

	if was_progress:
		_correct_count += 1
		rpc("_rpc_broadcast_message", "[Cellar] click. it lets you through.")
	else:
		rpc("_rpc_broadcast_message", "[Cellar] wrong. it loops back on itself.")

	var turn_dir: int = 0
	if was_progress:
		var roll: int = _rng.randi_range(0, 99)
		if roll < clampi(turn_chance_percent, 0, 100):
			turn_dir = (-1 if _rng.randi_range(0, 1) == 0 else 1)

	rpc("_rpc_apply_choice_and_extend", was_progress, turn_dir)

	if _correct_count >= required_correct_choices:
		rpc("_rpc_broadcast_message", "[Cellar] you made it. (end goes here later)")
		return

	# push chooser forward so they don’t backtrack
	var safe_cell: Vector2i = _cursor + _forward * 2
	_rpc_teleport_owner(player_owner_id, safe_cell)

@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_choice_and_extend(was_progress: bool, turn_dir: int) -> void:
	if was_progress and turn_dir != 0:
		var old_f: Vector2i = _forward
		var new_f: Vector2i = _turn_90(_forward, turn_dir)

		var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors
		var corner_start: Vector2i = door_wall_cell + _forward
		_build_corner(corner_start, old_f, new_f, corner_len)

		_forward = new_f
		_cursor = corner_start + _forward * corner_len
	else:
		var door_wall_cell2: Vector2i = _cursor + _forward * entry_len_before_doors
		_cursor = door_wall_cell2 + _forward * 2

	_build_hub_geometry()
	_move_triggers_to_hub()

	if debug_print:
		print("[Cellar] extended. progress=", was_progress, " turn_dir=", turn_dir, " cursor=", _cursor, " forward=", _forward, " correct_count=", _correct_count)

func _rpc_teleport_owner(owner_id: int, cell: Vector2i) -> void:
	var pos: Vector3 = _cell_to_world(cell)
	pos.y = _floor_top_y() + 1.0

	var players: Array = get_tree().get_nodes_in_group("player")
	for n in players:
		var p := n as Node3D
		if p != null and p.get_multiplayer_authority() == owner_id:
			if p.has_method("net_teleport"):
				p.rpc_id(owner_id, "net_teleport", pos)
			else:
				p.global_position = pos
			break

@rpc("any_peer", "call_local", "reliable")
func _rpc_broadcast_message(text: String) -> void:
	print(text)

# -------------------------
# Geometry
# -------------------------
func _build_hall_segment(start: Vector2i, forward: Vector2i, length: int) -> void:
	var half_w: int = int(hall_width_cells / 2)
	var right: Vector2i = _right_vec(forward)

	for i in range(0, length + 1):
		var base: Vector2i = start + forward * i

		for w in range(-half_w, half_w + 1):
			var c: Vector2i = base + right * w
			_spawn_block(c.x, 0, c.y)

		var left_edge: Vector2i = base + right * (-half_w)
		var right_edge: Vector2i = base + right * (half_w)
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(left_edge.x, h, left_edge.y)
			_spawn_block(right_edge.x, h, right_edge.y)

		if build_ceiling:
			var ch: int = wall_height_blocks + 1
			for w2 in range(-half_w, half_w + 1):
				var c2: Vector2i = base + right * w2
				_spawn_block(c2.x, ch, c2.y)

func _build_end_wall_with_three_doors(door_wall_cell: Vector2i, forward: Vector2i) -> void:
	var half_w: int = int(hall_width_cells / 2)
	var right: Vector2i = _right_vec(forward)

	for w in range(-half_w, half_w + 1):
		var c: Vector2i = door_wall_cell + right * w
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(c.x, h, c.y)

	for off in door_x_offsets:
		var door_cell: Vector2i = door_wall_cell + right * off
		_remove_wall_column(door_cell.x, door_cell.y)

func _door_open_cell(door_wall_cell: Vector2i, forward: Vector2i, door_offset: int) -> Vector2i:
	var door_cell: Vector2i = door_wall_cell + _right_vec(forward) * door_offset
	return door_cell + forward

func _place_cap_wall(cell: Vector2i) -> void:
	_spawn_block(cell.x, 0, cell.y)
	for h in range(1, wall_height_blocks + 1):
		_spawn_block(cell.x, h, cell.y)
	if build_ceiling:
		var ch: int = wall_height_blocks + 1
		_spawn_block(cell.x, ch, cell.y)

func _build_corner(start_cell: Vector2i, forward_a: Vector2i, forward_b: Vector2i, len_b: int) -> void:
	_build_one_wide_corridor(start_cell, forward_a, 1)
	_build_one_wide_corridor(start_cell + forward_a, forward_b, len_b)

func _build_one_wide_corridor(start_cell: Vector2i, forward: Vector2i, length: int) -> void:
	var right: Vector2i = _right_vec(forward)

	for i in range(0, length):
		var c: Vector2i = start_cell + forward * i
		_spawn_block(c.x, 0, c.y)

		for h in range(1, wall_height_blocks + 1):
			var l: Vector2i = c + right
			var r: Vector2i = c - right
			_spawn_block(l.x, h, l.y)
			_spawn_block(r.x, h, r.y)

		if build_ceiling:
			var ch: int = wall_height_blocks + 1
			_spawn_block(c.x, ch, c.y)

# -------------------------
# Spawn marker
# -------------------------
func _place_spawn_marker() -> void:
	if _spawn_marker == null or not is_instance_valid(_spawn_marker):
		return

	var c: Vector2i = Vector2i(0, spawn_cell_z)
	var p: Vector3 = _cell_to_world(c)
	p.y = _floor_top_y() + spawn_height_above_floor
	_spawn_marker.global_position = p

# -------------------------
# Helpers
# -------------------------
func _right_vec(forward: Vector2i) -> Vector2i:
	return Vector2i(forward.y, -forward.x)

func _turn_90(dir: Vector2i, turn_dir: int) -> Vector2i:
	if turn_dir < 0:
		return Vector2i(-dir.y, dir.x)
	return Vector2i(dir.y, -dir.x)

func _spawn_block(x: int, y_level_blocks: int, z: int) -> void:
	var k: String = _key(x, y_level_blocks, z)
	if _spawned.has(k):
		return

	var inst: Node3D = block_scene.instantiate() as Node3D
	if inst == null:
		return

	_world_root.add_child(inst)

	var wp: Vector3 = _cell_to_world(Vector2i(x, z))
	wp.y = _world_origin.y + y_offset_m + float(y_level_blocks) * block_size_m
	inst.global_position = wp

	_spawned[k] = inst

func _remove_wall_column(x: int, z: int) -> void:
	for h in range(1, wall_height_blocks + 1):
		var k: String = _key(x, h, z)
		if _spawned.has(k):
			var n := _spawned[k] as Node
			if n != null and is_instance_valid(n):
				n.queue_free()
			_spawned.erase(k)

func _cell_to_world(cell: Vector2i) -> Vector3:
	var px: float = (float(cell.x) + 0.5) * block_size_m
	var pz: float = (float(cell.y) + 0.5) * block_size_m
	return _world_origin + Vector3(px, 0.0, pz)

func _floor_top_y() -> float:
	return _world_origin.y + y_offset_m + (block_size_m * 0.5)

func _key(x: int, y: int, z: int) -> String:
	return "%d:%d:%d" % [x, y, z]

func _clear_world() -> void:
	for c in _world_root.get_children():
		c.queue_free()
	_spawned.clear()
