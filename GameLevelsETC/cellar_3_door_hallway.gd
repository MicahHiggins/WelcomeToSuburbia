extends Node3D
class_name CellarThreeDoorHallway

# -------------------------
# scene hooks
# -------------------------
@export var world_root_path: NodePath = NodePath("../world")
@export var triggers_root_path: NodePath = NodePath("../TriggerArea")
@export var spawn_marker_path: NodePath = NodePath("../SpawnPoints/Spawn")

@export var block_scene: PackedScene
@export var lever_scene: PackedScene # drag your Lever.tscn here

# -------------------------
# block/grid settings
# -------------------------
@export var block_size_m: float = 2.0
@export var y_offset_m: float = 1.0
@export var wall_height_blocks: int = 2
@export var build_ceiling: bool = false
@export var use_generator_as_origin: bool = true

# spawn (keep what worked)
@export var spawn_height_above_floor: float = 10.0
@export var spawn_cell_z: int = 2

# -------------------------
# hallway tuning
# -------------------------
@export var hall_width_cells: int = 7
@export var hall_len_before_doors: int = 18

# three doors across the wall
@export var door_x_offsets: Array[int] = [-2, 0, 2]

# doors look the same until you commit
@export var branch_same_len: int = 7        # identical hallway behind every door
@export var wrong_deadend_extra: int = 3    # wrong doors only go a little further (after the identical part)
@export var correct_continue_len: int = 16  # correct door continues to the NEXT 3-door junction

# reveal areas sit IN FRONT of each door (this is the only “tell”)
@export var reveal_offset_from_wall: int = 2 # how many cells before the door wall to place reveal triggers

# lever spawns at the NEXT junction (after you chose correct)
@export var lever_spawn_near_junction_z_offset: int = -3  # place lever a few cells before the new door wall
@export var lever_spawn_side_x: int = 2                   # put it slightly to the side

# small gate that blocks the next loop until lever pulled
@export var gate_blocks_forward_cells: int = 2 # gate is a column in the hall a couple cells before the new doors

# correct door selection
@export var forced_correct_door_index: int = -1 # -1 random, else 0..2

# multiplayer
@export var authority_only_build: bool = true
@export var debug_print: bool = true

# -------------------------
# cached nodes
# -------------------------
@onready var _world_root: Node3D = get_node_or_null(world_root_path) as Node3D
@onready var _triggers_root: Node3D = get_node_or_null(triggers_root_path) as Node3D
@onready var _spawn_marker: Node3D = get_node_or_null(spawn_marker_path) as Node3D

# -------------------------
# internal state
# -------------------------
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_origin: Vector3 = Vector3.ZERO

var _spawned: Dictionary = {} # String -> Node3D
var _built: bool = false
var _seed: int = 0

# “loop” stage
var _stage: int = 0
var _stage_base_z: int = 0
var _door_wall_z: int = 0
var _correct_door: int = 0

# after choosing correct door, we unlock the NEXT junction with a lever
var _next_junction_base_z: int = 0
var _next_junction_wall_z: int = 0
var _gate_cell: Vector2i = Vector2i.ZERO

# lever runtime
var _lever_enabled: bool = false
var _local_in_lever: bool = false
var _server_allowed_peers: Dictionary = {} # peer_id -> true
var _lever_instance: Node3D = null

const DOOR_NAMES: Array[String] = ["Door1", "Door2", "Door3"]
const REVEAL_NAMES: Array[String] = ["Reveal1", "Reveal2", "Reveal3"]

# ============================================================
# READY
# ============================================================
func _ready() -> void:
	_rng.randomize()

	if _world_root == null:
		push_error("[Cellar] World root not found. Fix world_root_path.")
		return
	if _triggers_root == null:
		push_error("[Cellar] Trigger root not found. Fix triggers_root_path.")
		return
	if block_scene == null:
		push_error("[Cellar] block_scene not assigned.")
		return
	if lever_scene == null:
		push_error("[Cellar] lever_scene not assigned (drag Lever.tscn in).")
		return

	_world_origin = global_position if use_generator_as_origin else Vector3.ZERO

	_bind_trigger_signals()

	if authority_only_build and multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			if not multiplayer.peer_connected.is_connected(_on_peer_connected):
				multiplayer.peer_connected.connect(_on_peer_connected)

			_seed = int(Time.get_ticks_msec()) ^ randi()
			_stage = 0
			_stage_base_z = 0
			_correct_door = _pick_correct_door(_stage)
			rpc("_rpc_build_stage", _seed, _stage, _stage_base_z, _correct_door)
	else:
		_seed = int(Time.get_ticks_msec()) ^ randi()
		_stage = 0
		_stage_base_z = 0
		_correct_door = _pick_correct_door(_stage)
		_build_stage(_seed, _stage, _stage_base_z, _correct_door)

func _on_peer_connected(peer_id: int) -> void:
	# just send the current state so late joiners see the same world
	rpc_id(peer_id, "_rpc_build_stage", _seed, _stage, _stage_base_z, _correct_door)
	# if we already spawned lever/gate for next junction, sync that too
	if _lever_enabled:
		rpc_id(peer_id, "_rpc_sync_next_junction", _next_junction_base_z, _next_junction_wall_z, _gate_cell)

# ============================================================
# RPCS
# ============================================================
@rpc("any_peer", "call_local", "reliable")
func _rpc_build_stage(seed: int, stage: int, base_z: int, correct_door: int) -> void:
	_build_stage(seed, stage, base_z, correct_door)

@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_next_junction(next_base_z: int, next_wall_z: int, gate_cell: Vector2i) -> void:
	_next_junction_base_z = next_base_z
	_next_junction_wall_z = next_wall_z
	_gate_cell = gate_cell
	_lever_enabled = true

	# spawn lever on all peers at the synced location
	var lever_cell: Vector2i = Vector2i(lever_spawn_side_x, _next_junction_wall_z + lever_spawn_near_junction_z_offset)
	_spawn_lever_at_cell(lever_cell)

@rpc("any_peer", "call_local", "reliable")
func _rpc_broadcast_message(text: String) -> void:
	print(text)

@rpc("any_peer", "call_local", "reliable")
func _rpc_open_gate(gate_cell: Vector2i) -> void:
	_remove_wall_column(gate_cell.x, gate_cell.y)

@rpc("any_peer", "call_local", "reliable")
func _rpc_disable_lever() -> void:
	_lever_enabled = false
	_local_in_lever = false
	_server_allowed_peers.clear()

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_lever_fx() -> void:
	if _lever_instance == null or not is_instance_valid(_lever_instance):
		return
	if _lever_instance.has_method("play_pull_fx"):
		_lever_instance.call("play_pull_fx")

@rpc("any_peer", "reliable")
func _rpc_request_pull_lever() -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()

	if not _lever_enabled:
		return
	if _server_allowed_peers.size() > 0 and not _server_allowed_peers.has(sender):
		return

	# fun feedback
	rpc("_rpc_play_lever_fx")
	rpc("_rpc_broadcast_message", "[Cellar] The cellar groans... the way opens.")

	# open gate on all peers
	rpc("_rpc_open_gate", _gate_cell)
	rpc("_rpc_disable_lever")

	# advance loop: next stage starts at the next junction base
	_stage += 1
	_stage_base_z = _next_junction_base_z
	_correct_door = _pick_correct_door(_stage)

	rpc("_rpc_build_stage", _seed, _stage, _stage_base_z, _correct_door)

# ============================================================
# INPUT (lever use)
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not _local_in_lever:
		return
	if not _lever_enabled:
		return

	if multiplayer.has_multiplayer_peer():
		rpc_id(1, "_rpc_request_pull_lever")
	else:
		_rpc_play_lever_fx()
		_rpc_broadcast_message("[Cellar] The cellar groans... the way opens.")
		_rpc_open_gate(_gate_cell)
		_rpc_disable_lever()
		_stage += 1
		_stage_base_z = _next_junction_base_z
		_correct_door = _pick_correct_door(_stage)
		_build_stage(_seed, _stage, _stage_base_z, _correct_door)

# ============================================================
# BUILD ONE LOOP STAGE
# ============================================================
func _build_stage(seed: int, stage: int, base_z: int, correct_door: int) -> void:
	_seed = seed
	_stage = stage
	_stage_base_z = base_z
	_correct_door = clampi(correct_door, 0, 2)

	_rng.seed = int(_seed) ^ int(_stage * 7919)

	# only clear world on very first build (keeps it loop-y and continuous)
	if not _built:
		_built = true
		_clear_world()
		_destroy_lever()
		_place_spawn_marker()

	# reset next-junction + lever state for this stage
	_lever_enabled = false
	_local_in_lever = false
	_server_allowed_peers.clear()

	# main hall for this stage
	_door_wall_z = _stage_base_z + hall_len_before_doors
	_build_main_hall(_stage_base_z, _door_wall_z)
	_build_end_wall_with_three_doors(_door_wall_z)

	# move door triggers + reveal triggers to this wall
	_position_door_triggers(_door_wall_z)
	_position_reveal_triggers(_door_wall_z)

	if debug_print:
		print("[Cellar] Stage built:", _stage, " base_z=", _stage_base_z, " wall_z=", _door_wall_z, " correct=", _correct_door)

# ============================================================
# DOOR + REVEAL SIGNALS
# ============================================================
func _bind_trigger_signals() -> void:
	# Door triggers (Area3D nodes under TriggerArea)
	for i in range(3):
		var a: Area3D = _triggers_root.get_node_or_null(DOOR_NAMES[i]) as Area3D
		if a == null:
			continue
		a.set_meta("door_index", i)
		if not a.body_entered.is_connected(_on_door_entered):
			a.body_entered.connect(_on_door_entered.bind(a))

	# Reveal triggers (optional, same structure)
	for i in range(3):
		var r: Area3D = _triggers_root.get_node_or_null(REVEAL_NAMES[i]) as Area3D
		if r == null:
			continue
		r.set_meta("door_index", i)
		if not r.body_entered.is_connected(_on_reveal_entered):
			r.body_entered.connect(_on_reveal_entered.bind(r))

func _on_reveal_entered(body: Node3D, reveal_area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if reveal_area == null:
		return

	# server decides the “truth”
	if multiplayer.has_multiplayer_peer() and authority_only_build and not multiplayer.is_server():
		return

	var idx: int = int(reveal_area.get_meta("door_index", -1))
	if idx < 0:
		return

	# ONLY this zone exposes it
	if idx == _correct_door:
		rpc("_rpc_broadcast_message", "[Cellar] Something feels *right* here.")
	else:
		rpc("_rpc_broadcast_message", "[Cellar] Your skin crawls. Bad door.")

func _on_door_entered(body: Node3D, door_area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if door_area == null:
		return

	# server decides geometry effects
	if multiplayer.has_multiplayer_peer() and authority_only_build and not multiplayer.is_server():
		return

	var idx: int = int(door_area.get_meta("door_index", -1))
	if idx < 0:
		return

	var door_x: int = door_x_offsets[idx]
	var door_start_z: int = _door_wall_z + 1

	# build identical hallway behind every door first
	_build_branch_identical(door_x, door_start_z, branch_same_len)

	# then diverge after that identical part
	var after_same_z: int = door_start_z + branch_same_len

	if idx == _correct_door:
		# correct continues to next junction
		_build_branch_corridor(door_x, after_same_z, correct_continue_len)

		# next junction will start at the end of this continuation
		_next_junction_base_z = after_same_z + correct_continue_len
		_next_junction_wall_z = _next_junction_base_z + hall_len_before_doors

		# put a gate in the hall before the next wall (blocks progress until lever)
		_gate_cell = Vector2i(0, _next_junction_wall_z - gate_blocks_forward_cells)
		_place_gate_column(_gate_cell)

		# spawn lever near that next junction (not in the main line)
		var lever_cell: Vector2i = Vector2i(lever_spawn_side_x, _next_junction_wall_z + lever_spawn_near_junction_z_offset)

		# tell everyone to sync that next junction + lever state
		rpc("_rpc_sync_next_junction", _next_junction_base_z, _next_junction_wall_z, _gate_cell)
		rpc("_rpc_broadcast_message", "[Cellar] The hallway keeps going... but something blocks it.")

	else:
		# wrong branch dead-ends a bit later (after identical part)
		_build_branch_corridor(door_x, after_same_z, wrong_deadend_extra)
		_cap_dead_end(door_x, after_same_z + wrong_deadend_extra)

# ============================================================
# LEVER AREA ENTER/EXIT
# ============================================================
func _on_lever_body_entered(body: Node3D, _lever_area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if not _lever_enabled:
		return

	_local_in_lever = true

	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_broadcast_message", "[Cellar] Press Interact to pull the lever.")
	else:
		print("[Cellar] Press Interact to pull the lever.")

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var peer_id: int = body.get_multiplayer_authority()
		_server_allowed_peers[peer_id] = true

func _on_lever_body_exited(body: Node3D, _lever_area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return

	_local_in_lever = false

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var peer_id: int = body.get_multiplayer_authority()
		if _server_allowed_peers.has(peer_id):
			_server_allowed_peers.erase(peer_id)

# ============================================================
# TRIGGER POSITIONING
# ============================================================
func _position_door_triggers(door_wall_z: int) -> void:
	var trig_y: float = _floor_top_y() + 0.8
	for i in range(3):
		var a: Area3D = _triggers_root.get_node_or_null(DOOR_NAMES[i]) as Area3D
		if a == null:
			continue
		var cell: Vector2i = Vector2i(door_x_offsets[i], door_wall_z)
		var p: Vector3 = _cell_to_world(cell)
		p.y = trig_y
		a.global_position = p

func _position_reveal_triggers(door_wall_z: int) -> void:
	var trig_y: float = _floor_top_y() + 0.8
	for i in range(3):
		var r: Area3D = _triggers_root.get_node_or_null(REVEAL_NAMES[i]) as Area3D
		if r == null:
			continue
		# reveal is in front of the door on the hall floor
		var cell: Vector2i = Vector2i(door_x_offsets[i], door_wall_z - reveal_offset_from_wall)
		var p: Vector3 = _cell_to_world(cell)
		p.y = trig_y
		r.global_position = p

# ============================================================
# GEOMETRY
# ============================================================
func _build_main_hall(z_start: int, z_end: int) -> void:
	var half_w: int = int(hall_width_cells / 2)

	for z in range(z_start, z_end + 1):
		for x in range(-half_w, half_w + 1):
			_spawn_block(x, 0, z)

		var left_x: int = -half_w
		var right_x: int = half_w
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(left_x, h, z)
			_spawn_block(right_x, h, z)

		if build_ceiling:
			var ch: int = wall_height_blocks + 1
			for x2 in range(-half_w, half_w + 1):
				_spawn_block(x2, ch, z)

func _build_end_wall_with_three_doors(door_z: int) -> void:
	var half_w: int = int(hall_width_cells / 2)

	# wall
	for x in range(-half_w, half_w + 1):
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(x, h, door_z)

	# carve the 3 door holes
	for xoff in door_x_offsets:
		_remove_wall_column(xoff, door_z)

func _build_branch_identical(door_x: int, start_z: int, length: int) -> void:
	# 1-wide corridor with walls on both sides
	for i in range(0, length):
		var z: int = start_z + i
		_spawn_block(door_x, 0, z)
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(door_x - 1, h, z)
			_spawn_block(door_x + 1, h, z)
		if build_ceiling:
			var ch: int = wall_height_blocks + 1
			_spawn_block(door_x, ch, z)

func _build_branch_corridor(door_x: int, start_z: int, length: int) -> void:
	for i in range(0, length):
		var z: int = start_z + i
		_spawn_block(door_x, 0, z)
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(door_x - 1, h, z)
			_spawn_block(door_x + 1, h, z)
		if build_ceiling:
			var ch: int = wall_height_blocks + 1
			_spawn_block(door_x, ch, z)

func _cap_dead_end(x: int, z: int) -> void:
	for h in range(1, wall_height_blocks + 1):
		_spawn_block(x, h, z)

func _place_gate_column(cell: Vector2i) -> void:
	# full column blocks the main line until lever
	for h in range(1, wall_height_blocks + 1):
		_spawn_block(cell.x, h, cell.y)

# ============================================================
# LEVER SPAWN (scene instance)
# ============================================================
func _spawn_lever_at_cell(cell: Vector2i) -> void:
	_destroy_lever()

	_lever_instance = lever_scene.instantiate() as Node3D
	if _lever_instance == null:
		push_error("[Cellar] Lever scene did not instantiate.")
		return

	_triggers_root.add_child(_lever_instance)

	var p: Vector3 = _cell_to_world(cell)
	p.y = _floor_top_y() + 0.8
	_lever_instance.global_position = p
	_lever_instance.visible = true

	var lever_area: Area3D = _lever_instance.get_node_or_null("Area3D") as Area3D
	if lever_area == null:
		push_error("[Cellar] Lever.tscn needs an Area3D child named 'Area3D'.")
		return

	lever_area.monitoring = true

	if not lever_area.body_entered.is_connected(_on_lever_body_entered):
		lever_area.body_entered.connect(_on_lever_body_entered.bind(lever_area))
	if not lever_area.body_exited.is_connected(_on_lever_body_exited):
		lever_area.body_exited.connect(_on_lever_body_exited.bind(lever_area))

func _destroy_lever() -> void:
	if _lever_instance != null and is_instance_valid(_lever_instance):
		_lever_instance.queue_free()
	_lever_instance = null

# ============================================================
# SPAWN MARKER
# ============================================================
func _place_spawn_marker() -> void:
	if _spawn_marker == null or not is_instance_valid(_spawn_marker):
		return

	var c: Vector2i = Vector2i(0, spawn_cell_z)
	var p: Vector3 = _cell_to_world(c)
	p.y = _floor_top_y() + spawn_height_above_floor
	_spawn_marker.global_position = p

# ============================================================
# HELPERS
# ============================================================
func _pick_correct_door(stage: int) -> int:
	if forced_correct_door_index >= 0 and forced_correct_door_index <= 2:
		return forced_correct_door_index

	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = int(_seed) ^ int(stage * 1337) ^ 0xCAFE
	return r.randi_range(0, 2)

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
			var n: Node = _spawned[k] as Node
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
