# res://CellarDoorHallway.gd
extends Node3D
class_name CellarDoorHallway

@export var world_root_path: NodePath = NodePath("../world")
@export var triggers_root_path: NodePath = NodePath("../TriggerArea")
@export var spawn_marker_path: NodePath = NodePath("../SpawnPoints/Spawn")
@export var block_scene: PackedScene

@export var block_size_m: float = 2.0
@export var y_offset_m: float = 1.0

@export var wall_height_blocks: int = 4
@export var build_ceiling: bool = true
@export var door_open_height_blocks: int = 3

@export var use_generator_as_origin: bool = true

@export var spawn_height_above_floor: float = 7.0
@export var spawn_cell_z: int = 2

@export var hall_width_cells: int = 7
@export var hall_width_cells_final: int = 9
@export var entry_len_before_doors: int = 10
@export var back_hall_len: int = 70
@export var final_room_extra_len: int = 10

@export var door_sets_total: int = 6
@export var door_x_offsets_three: Array[int] = [-2, 0, 2]
@export var door_x_offset_final: int = 0

@export var reveal_distance_cells: int = 2
@export var next_hub_start_gap_cells: int = 12

@export var door_open_seconds: float = 1.0
@export var door_slide_cells: float = 2.0
@export var door_stagger: float = 0.02

@export var door_trigger_forward_offset_m: float = 0.6
@export var reveal_trigger_height_offset_m: float = 0.8

@export var pass_threshold_forward_cells: float = 0.6

@export var wrong_door_gust_distance_cells: float = 3.0
@export var wrong_door_gust_duration: float = 0.25
@export var wrong_door_gust_steps: int = 8

@export var chase_enabled: bool = true
@export var chase_start_delay_sec: float = 1.25
@export var chase_start_behind_spawn_cells: int = 40
@export var chase_interval_sec: float = 0.40
@export var chase_max_steps: int = 0
@export var chase_drop_height_m: float = 4.0
@export var chase_slam_time_sec: float = 0.55
@export var chase_stagger_sec: float = 0.012
@export var organic_slam_enabled: bool = true
@export var organic_inset_m: float = 2.6
@export var organic_jitter_m: float = 0.22
@export var organic_extra_up_m: float = 0.9
@export var caught_grace_cells: int = 0

@export var fade_enabled: bool = true
@export var fade_in_sec: float = 0.25
@export var fade_hold_sec: float = 0.40
@export var fade_out_sec: float = 0.20
@export var restart_teleport_players_to_spawn: bool = true
@export var restart_teleport_delay_sec: float = 0.10

@export var ladder_scene: PackedScene
@export var ladder_spawn_height_blocks: int = 0
@export var ladder_spawn_forward_cells: int = 2

# =========================
# SYMBOLS (set these in inspector)
# =========================
@export var correct_symbol_scene: PackedScene
@export var wrong_symbol_scene_a: PackedScene
@export var wrong_symbol_scene_b: PackedScene

@export var symbols_root_path: NodePath = NodePath("")
@export var symbol_inside_offset_m: float = 0.35
@export var symbol_forward_extra_m: float = 0.85
@export var symbol_extra_y_offset_m: float = 0.0
@export var symbol_up_blocks: int = 0

@onready var _world_root: Node3D = get_node_or_null(world_root_path) as Node3D
@onready var _triggers_root: Node3D = get_node_or_null(triggers_root_path) as Node3D
@onready var _spawn_marker: Node3D = get_node_or_null(spawn_marker_path) as Node3D

var _symbols_root: Node3D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_origin: Vector3 = Vector3.ZERO

var _spawned: Dictionary = {}
var _base_pos: Dictionary = {}
var _base_scale: Dictionary = {}
var _phase: Dictionary = {}

var _seed: int = 0
var _built: bool = false
var _network_started: bool = false

var _cursor: Vector2i = Vector2i(0, 0)
var _forward: Vector2i = Vector2i(0, 1)

var _correct_count: int = 0
var _progress_door: int = 0
var _revealed: Array[bool] = [false, false, false]
var _reroll_nonce: int = 0

var _door_panel_blocks: Array = [[], [], []]
var _cap_blocks: Array = [[], [], []]
var _door_panel_keys: Array = [[], [], []]
var _cap_keys: Array = [[], [], []]

var _open_panel_blocks: Array[Node3D] = []
var _open_cap_blocks: Array[Node3D] = []

var _pending_delete_wall_keys: Array[String] = []
var _pending_delete_open_keys: Array[String] = []
var _pending_delete_wall_cell: Vector2i = Vector2i(0, 0)
var _pending_delete_forward: Vector2i = Vector2i(0, 1)

var _hub_id: int = 0
var _pending_delete_symbol_hub_id: int = -1

var _active_door_wall_cell: Vector2i = Vector2i(0, 0)
var _active_door_wall_forward: Vector2i = Vector2i(0, 1)
var _active_door_wall_keys: Array[String] = []

var _watch_pass_active: bool = false
var _watch_owner_id: int = -1

var _chase_running: bool = false
var _chase_wall_cell: Vector2i = Vector2i.ZERO
var _chase_forward: Vector2i = Vector2i(0, 1)
var _restart_in_progress: bool = false

var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

var _final_mode: bool = false
var _victory_done: bool = false

const DOOR_NAMES: Array[String] = ["Door1", "Door2", "Door3"]
const REVEAL_NAMES: Array[String] = ["Reveal1", "Reveal2", "Reveal3"]

func _ready() -> void:
	_rng.randomize()
	add_to_group("level_post_ready")
	if _world_root == null:
		return
	if _triggers_root == null:
		return
	if block_scene == null:
		return
	_world_origin = global_position if use_generator_as_origin else Vector3.ZERO
	door_open_height_blocks = clampi(door_open_height_blocks, 1, wall_height_blocks)
	next_hub_start_gap_cells = maxi(6, next_hub_start_gap_cells)
	back_hall_len = maxi(10, back_hall_len)
	final_room_extra_len = maxi(0, final_room_extra_len)
	wrong_door_gust_steps = maxi(2, wrong_door_gust_steps)
	chase_start_behind_spawn_cells = maxi(1, chase_start_behind_spawn_cells)
	chase_interval_sec = maxf(0.05, chase_interval_sec)
	chase_slam_time_sec = maxf(0.05, chase_slam_time_sec)
	chase_max_steps = maxi(0, chase_max_steps)
	caught_grace_cells = maxi(0, caught_grace_cells)
	door_sets_total = maxi(1, door_sets_total)
	_resolve_symbols_root()
	_ensure_fade_ui()
	_bind_trigger_signals()
	set_process(true)
	if not multiplayer.has_multiplayer_peer():
		_seed = int(Time.get_ticks_msec()) ^ randi()
		_build_initial(_seed)

func on_level_post_ready() -> void:
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		if _network_started:
			return
		_network_started = true
		_seed = int(Time.get_ticks_msec()) ^ randi()
		rpc("_rpc_build_initial", _seed)
	else:
		if _built:
			return
		_seed = int(Time.get_ticks_msec()) ^ randi()
		_build_initial(_seed)

func _process(_dt: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if not _watch_pass_active:
		return
	if _watch_owner_id <= 0:
		return
	var p: Node3D = _player_for_owner(_watch_owner_id)
	if p == null:
		return
	var wall_center: Vector3 = _cell_to_world(_pending_delete_wall_cell)
	var fwd_world: Vector3 = Vector3(float(_pending_delete_forward.x), 0.0, float(_pending_delete_forward.y)).normalized()
	var threshold: Vector3 = wall_center + fwd_world * (block_size_m * pass_threshold_forward_cells)
	var d_now: float = (p.global_position - wall_center).dot(fwd_world)
	var d_thr: float = (threshold - wall_center).dot(fwd_world)
	if d_now >= d_thr:
		_watch_pass_active = false
		var keys_to_delete: Array[String] = []
		for k in _pending_delete_wall_keys:
			keys_to_delete.append(k)
		for k2 in _pending_delete_open_keys:
			keys_to_delete.append(k2)
		var seen: Dictionary = {}
		var uniq: Array[String] = []
		for kk in keys_to_delete:
			if not seen.has(kk):
				seen[kk] = true
				uniq.append(kk)
		rpc("_rpc_delete_many", uniq)
		if _pending_delete_symbol_hub_id >= 0:
			rpc("_rpc_delete_symbols_by_hub", _pending_delete_symbol_hub_id)
			_pending_delete_symbol_hub_id = -1

func _hall_width_now() -> int:
	return hall_width_cells_final if _final_mode else hall_width_cells

func _door_offsets() -> Array[int]:
	if _final_mode:
		return [door_x_offset_final]
	return door_x_offsets_three

func _clamp_door_offsets() -> void:
	var half_w: int = int(_hall_width_now() / 2)
	for i in range(door_x_offsets_three.size()):
		door_x_offsets_three[i] = clampi(door_x_offsets_three[i], -half_w + 1, half_w - 1)
	door_x_offset_final = clampi(door_x_offset_final, -half_w + 1, half_w - 1)

@rpc("any_peer", "call_local", "reliable")
func _rpc_build_initial(seed: int) -> void:
	_built = false
	_build_initial(seed)

func _build_initial(seed: int) -> void:
	if _built:
		return
	_built = true
	_seed = seed
	_rng.seed = seed
	_chase_running = false
	_restart_in_progress = false
	_final_mode = false
	_victory_done = false
	_clear_world()
	_clear_all_symbols()
	_cursor = Vector2i(0, 0)
	_forward = Vector2i(0, 1)
	_correct_count = 0
	_reroll_nonce = 0
	_hub_id = 0
	_pending_delete_symbol_hub_id = -1
	_build_hub_geometry()
	_move_triggers_to_hub()
	_place_spawn_marker()
	_start_chase_if_needed()

func _pick_progress_door_for_current_hub() -> int:
	var h: int = _seed ^ (_correct_count * 7919) ^ (_cursor.x * 101) ^ (_cursor.y * 10007) ^ (_reroll_nonce * 15485863)
	var local_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	local_rng.seed = h
	return local_rng.randi_range(0, 2)

func _place_solid_column(cell: Vector2i) -> void:
	_spawn_block(cell.x, 0, cell.y)
	if build_ceiling:
		_spawn_block(cell.x, wall_height_blocks + 1, cell.y)
	for h in range(1, wall_height_blocks + 1):
		_spawn_block(cell.x, h, cell.y)

func _build_hub_geometry() -> void:
	_clamp_door_offsets()
	_hub_id += 1
	_pending_delete_symbol_hub_id = -1
	_revealed = [false, false, false]
	_progress_door = _pick_progress_door_for_current_hub()
	_door_panel_blocks = [[], [], []]
	_cap_blocks = [[], [], []]
	_door_panel_keys = [[], [], []]
	_cap_keys = [[], [], []]

	var bw: int = max(0, back_hall_len)
	var total_len: int = bw + entry_len_before_doors
	if _final_mode:
		total_len += final_room_extra_len

	var back_start: Vector2i = _cursor - _forward * bw
	_build_hall_segment(back_start, _forward, total_len)
	_place_end_wall_full(back_start - _forward, _forward)

	var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors
	_build_end_wall_with_doors(door_wall_cell, _forward)

	_place_door_panels_behind_openings(door_wall_cell, _forward)

	var offs: Array[int] = _door_offsets()

	# final hub: cap wall must be at the same depth as ladder (and 3-wide to stop side holes)
	if _final_mode:
		var open_cell_f: Vector2i = _door_open_cell(door_wall_cell, _forward, door_x_offset_final)
		var cap_center: Vector2i = open_cell_f + _forward * ladder_spawn_forward_cells
		var right: Vector2i = _right_vec(_forward)

		_place_cap_wall_record(cap_center, 0)
		_place_solid_column(cap_center + right)
		_place_solid_column(cap_center - right)
	else:
		for i in range(offs.size()):
			var open_cell: Vector2i = _door_open_cell(door_wall_cell, _forward, int(offs[i]))
			var cap_cell: Vector2i = open_cell + _forward
			_place_cap_wall_record(cap_cell, i)

	_active_door_wall_cell = door_wall_cell
	_active_door_wall_forward = _forward
	_active_door_wall_keys = _collect_door_wall_keys(door_wall_cell, _forward)

	if not _final_mode:
		_spawn_symbols_for_current_hub(door_wall_cell, _forward, _hub_id)

func _collect_door_wall_keys(door_wall_cell: Vector2i, forward: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var half_w: int = int(_hall_width_now() / 2)
	var right: Vector2i = _right_vec(forward)
	for w in range(-half_w + 1, half_w):
		var c: Vector2i = door_wall_cell + right * w
		for h in range(1, wall_height_blocks + 1):
			out.append(_key(c.x, h, c.y))
	return out

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
	if _final_mode:
		for i in range(3):
			var door_area: Area3D = _triggers_root.get_node_or_null(DOOR_NAMES[i]) as Area3D
			var reveal_area: Area3D = _triggers_root.get_node_or_null(REVEAL_NAMES[i]) as Area3D
			if door_area != null:
				door_area.monitoring = false
				door_area.monitorable = false
				door_area.global_position = Vector3(0.0, -10000.0, 0.0)
			if reveal_area != null:
				reveal_area.monitoring = false
				reveal_area.monitorable = false
				reveal_area.global_position = Vector3(0.0, -10000.0, 0.0)
		return

	var base_y: float = _floor_top_y() + reveal_trigger_height_offset_m
	var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors
	var fwd_world: Vector3 = Vector3(float(_forward.x), 0.0, float(_forward.y)).normalized()
	var offs: Array[int] = _door_offsets()

	for i in range(3):
		var active: bool = i < offs.size()
		var door_area2: Area3D = _triggers_root.get_node_or_null(DOOR_NAMES[i]) as Area3D
		var reveal_area2: Area3D = _triggers_root.get_node_or_null(REVEAL_NAMES[i]) as Area3D

		if not active:
			if door_area2 != null:
				door_area2.monitoring = false
				door_area2.monitorable = false
				door_area2.global_position = Vector3(0.0, -10000.0, 0.0)
			if reveal_area2 != null:
				reveal_area2.monitoring = false
				reveal_area2.monitorable = false
				reveal_area2.global_position = Vector3(0.0, -10000.0, 0.0)
			continue

		var open_cell: Vector2i = _door_open_cell(door_wall_cell, _forward, int(offs[i]))

		if door_area2 != null:
			door_area2.monitoring = true
			door_area2.monitorable = true
			var p: Vector3 = _cell_to_world(open_cell)
			p.y = base_y
			p -= fwd_world * (block_size_m * 1.0)
			door_area2.global_position = p

		if reveal_area2 != null:
			reveal_area2.monitoring = true
			reveal_area2.monitorable = true
			var reveal_cell: Vector2i = open_cell - _forward * reveal_distance_cells
			var rp: Vector3 = _cell_to_world(reveal_cell)
			rp.y = base_y
			reveal_area2.global_position = rp

func _on_reveal_entered(body: Node3D, area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if area == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var idx: int = int(area.get_meta("door_index", -1))
	if idx < 0 or idx > 2:
		return
	if _revealed[idx]:
		return
	_revealed[idx] = true

func _on_door_entered(body: Node3D, door_area: Area3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if door_area == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var idx: int = int(door_area.get_meta("door_index", -1))
	if idx < 0 or idx > 2:
		return
	var owner_id: int = int(body.get_multiplayer_authority())
	if owner_id <= 0:
		return
	_server_like_enter_door(idx, owner_id)

func _server_like_enter_door(door_idx: int, player_owner_id: int) -> void:
	if door_idx < 0 or door_idx > 2:
		return
	if not _revealed[door_idx]:
		return
	if _final_mode:
		return

	if door_idx == _progress_door:
		_correct_count += 1
		_pending_delete_wall_cell = _active_door_wall_cell
		_pending_delete_forward = _active_door_wall_forward
		_pending_delete_wall_keys = _active_door_wall_keys.duplicate()
		_pending_delete_symbol_hub_id = _hub_id
		rpc("_rpc_cache_open_blocks", door_idx)

		if _correct_count >= door_sets_total:
			_final_mode = true
			_stop_chase_server()

			var new_cursor_f: Vector2i = _active_door_wall_cell + _forward * next_hub_start_gap_cells
			rpc("_rpc_build_final_at_cursor", new_cursor_f, _forward, _seed, _correct_count, _reroll_nonce)

			rpc("_rpc_open_door_anim_cached")

			_watch_pass_active = true
			_watch_owner_id = player_owner_id
			return

		var new_cursor: Vector2i = _active_door_wall_cell + _forward * next_hub_start_gap_cells
		rpc("_rpc_build_next_hub_at_cursor", new_cursor, _forward, _seed, _correct_count, _reroll_nonce)
		rpc("_rpc_open_door_anim_cached")
		_watch_pass_active = true
		_watch_owner_id = player_owner_id
		return

	_reroll_nonce += 1
	_revealed = [false, false, false]
	_progress_door = _pick_progress_door_for_current_hub()
	rpc("_rpc_respawn_symbols_for_current_hub", _hub_id)
	call_deferred("_deferred_wrong_gust", player_owner_id)

func _stop_chase_server() -> void:
	chase_enabled = false
	_chase_running = false

func _deferred_wrong_gust(player_owner_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var p: Node3D = _player_for_owner(player_owner_id)
	if p == null:
		return
	var fwd_world: Vector3 = Vector3(float(_forward.x), 0.0, float(_forward.y)).normalized()
	var start_pos: Vector3 = p.global_position
	var end_pos: Vector3 = start_pos - fwd_world * (wrong_door_gust_distance_cells * block_size_m)
	var steps: int = maxi(2, wrong_door_gust_steps)
	var dt: float = wrong_door_gust_duration / float(steps)
	for i in range(1, steps + 1):
		var a: float = float(i) / float(steps)
		var tt: float = 1.0 - pow(1.0 - a, 2.0)
		var pos: Vector3 = start_pos.lerp(end_pos, tt)
		_move_owner_to_pos(player_owner_id, pos)
		var timer: SceneTreeTimer = get_tree().create_timer(dt)
		await timer.timeout

func _move_owner_to_pos(owner_id: int, pos: Vector3) -> void:
	var p: Node3D = _player_for_owner(owner_id)
	if p == null:
		return
	if p.has_method("net_teleport"):
		p.rpc_id(owner_id, "net_teleport", pos)
	else:
		p.global_position = pos

@rpc("any_peer", "call_local", "reliable")
func _rpc_build_next_hub_at_cursor(new_cursor: Vector2i, new_forward: Vector2i, seed_passthrough: int, correct_count_passthrough: int, reroll_passthrough: int) -> void:
	_cursor = new_cursor
	_forward = new_forward
	_seed = seed_passthrough
	_correct_count = correct_count_passthrough
	_reroll_nonce = reroll_passthrough
	_rng.seed = seed_passthrough
	_final_mode = false
	_build_hub_geometry()
	_move_triggers_to_hub()

@rpc("any_peer", "call_local", "reliable")
func _rpc_build_final_at_cursor(new_cursor: Vector2i, new_forward: Vector2i, seed_passthrough: int, correct_count_passthrough: int, reroll_passthrough: int) -> void:
	_cursor = new_cursor
	_forward = new_forward
	_seed = seed_passthrough
	_correct_count = correct_count_passthrough
	_reroll_nonce = reroll_passthrough
	_rng.seed = seed_passthrough
	_final_mode = true
	_build_hub_geometry()
	_move_triggers_to_hub()
	_rpc_spawn_ladder_at_final()

@rpc("any_peer", "call_local", "reliable")
func _rpc_cache_open_blocks(door_idx: int) -> void:
	_open_panel_blocks.clear()
	_open_cap_blocks.clear()
	_pending_delete_open_keys.clear()
	var panel_keys_any: Array = _door_panel_keys[door_idx] as Array
	for k in panel_keys_any:
		_pending_delete_open_keys.append(String(k))
	var cap_keys_any: Array = _cap_keys[door_idx] as Array
	for k2 in cap_keys_any:
		_pending_delete_open_keys.append(String(k2))
	for b in (_door_panel_blocks[door_idx] as Array):
		var n := b as Node3D
		if n != null and is_instance_valid(n):
			_open_panel_blocks.append(n)
	for b2 in (_cap_blocks[door_idx] as Array):
		var n2 := b2 as Node3D
		if n2 != null and is_instance_valid(n2):
			_open_cap_blocks.append(n2)

@rpc("any_peer", "call_local", "reliable")
func _rpc_open_door_anim_cached() -> void:
	var right2: Vector2i = _right_vec(_pending_delete_forward)
	var slide_vec: Vector3 = Vector3(
		float(right2.x) * block_size_m * door_slide_cells,
		0.0,
		float(right2.y) * block_size_m * door_slide_cells
	)
	var blocks: Array[Node3D] = []
	for n in _open_panel_blocks:
		if n != null and is_instance_valid(n):
			blocks.append(n)
	for n2 in _open_cap_blocks:
		if n2 != null and is_instance_valid(n2):
			blocks.append(n2)
	var i: int = 0
	for blk in blocks:
		var end_p: Vector3 = blk.global_position + slide_vec
		var tw: Tween = create_tween()
		tw.tween_interval(float(i) * door_stagger)
		tw.tween_property(blk, "global_position", end_p, door_open_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		i += 1

@rpc("any_peer", "call_local", "reliable")
func _rpc_delete_many(keys: Array[String]) -> void:
	for k in keys:
		if not _spawned.has(k):
			continue
		var n: Node = _spawned[k] as Node
		if n != null and is_instance_valid(n):
			n.queue_free()
		_spawned.erase(k)
		_base_pos.erase(k)
		_base_scale.erase(k)
		_phase.erase(k)

@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_ladder_at_final() -> void:
	if ladder_scene == null:
		return

	for ch_any in _world_root.get_children():
		var ch := ch_any as Node
		if ch != null and ch.name == "FinalLadder":
			ch.queue_free()

	var inst := ladder_scene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "FinalLadder"

	var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors
	var open_cell: Vector2i = _door_open_cell(door_wall_cell, _forward, door_x_offset_final)

	var fwd_world: Vector3 = Vector3(float(_forward.x), 0.0, float(_forward.y)).normalized()

	var wp: Vector3 = _cell_to_world(open_cell)
	wp -= fwd_world * (block_size_m * 1.0)
	wp += fwd_world * (block_size_m * float(ladder_spawn_forward_cells))

	wp.y = _world_origin.y + y_offset_m + float(ladder_spawn_height_blocks) * block_size_m

	inst.global_position = wp
	_world_root.add_child(inst)

func _start_chase_if_needed() -> void:
	if not chase_enabled:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _chase_running:
		return
	_chase_running = true
	_restart_in_progress = false
	_chase_forward = Vector2i(0, 1)
	var behind: int = clampi(chase_start_behind_spawn_cells, 1, maxi(1, back_hall_len - 1))
	_chase_wall_cell = Vector2i(0, spawn_cell_z - behind)
	call_deferred("_deferred_run_chase")

func _deferred_run_chase() -> void:
	_run_chase_async()

func _run_chase_async() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var t0 := get_tree().create_timer(maxf(0.0, chase_start_delay_sec))
	await t0.timeout
	var steps_left: int = chase_max_steps
	var safety_loops: int = 0
	while true:
		if not _chase_running or _restart_in_progress:
			return
		if chase_max_steps > 0:
			steps_left -= 1
			if steps_left < 0:
				_chase_running = false
				return
		if _is_any_player_caught(_chase_wall_cell, _chase_forward):
			_chase_running = false
			await _server_restart_with_fade()
			return
		rpc("_rpc_slam_wall_face", _chase_wall_cell, _chase_forward, chase_drop_height_m, chase_slam_time_sec, chase_stagger_sec)
		_chase_wall_cell += _chase_forward
		safety_loops += 1
		if safety_loops > 200000:
			_chase_running = false
			return
		var tmr := get_tree().create_timer(chase_interval_sec)
		await tmr.timeout

func _is_any_player_caught(wall_cell: Vector2i, forward: Vector2i) -> bool:
	var wall_prog: int = wall_cell.x * forward.x + wall_cell.y * forward.y
	wall_prog -= caught_grace_cells
	var players: Array = get_tree().get_nodes_in_group("player")
	for n_any in players:
		var p: Node3D = n_any as Node3D
		if p == null:
			continue
		var pc: Vector2i = _world_to_cell(p.global_position)
		var p_prog: int = pc.x * forward.x + pc.y * forward.y
		if p_prog <= wall_prog:
			return true
	return false

func _world_to_cell(pos: Vector3) -> Vector2i:
	var local: Vector3 = pos - _world_origin
	var cx: int = int(floor(local.x / block_size_m))
	var cz: int = int(floor(local.z / block_size_m))
	return Vector2i(cx, cz)

func _server_restart_with_fade() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _restart_in_progress:
		return
	_restart_in_progress = true
	_chase_running = false
	if fade_enabled:
		rpc("_rpc_fade_black", fade_in_sec, fade_hold_sec, fade_out_sec)
		var t := get_tree().create_timer(maxf(0.0, fade_in_sec + fade_hold_sec))
		await t.timeout
	var new_seed: int = int(Time.get_ticks_msec()) ^ randi()
	_seed = new_seed
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_build_initial", new_seed)
	else:
		_rpc_build_initial(new_seed)
	if restart_teleport_players_to_spawn:
		var t2 := get_tree().create_timer(maxf(0.0, restart_teleport_delay_sec))
		await t2.timeout
		_teleport_all_players_to_spawn_server()
	_restart_in_progress = false

func _teleport_all_players_to_spawn_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var spawn_pos: Vector3
	if _spawn_marker != null and is_instance_valid(_spawn_marker):
		spawn_pos = _spawn_marker.global_position
	else:
		var c := Vector2i(0, spawn_cell_z)
		spawn_pos = _cell_to_world(c)
		spawn_pos.y = _floor_top_y() + spawn_height_above_floor
	var players: Array = get_tree().get_nodes_in_group("player")
	for n_any in players:
		var p: Node3D = n_any as Node3D
		if p == null:
			continue
		var owner_id := int(p.get_multiplayer_authority())
		if owner_id <= 0:
			continue
		if p.has_method("net_teleport"):
			p.rpc_id(owner_id, "net_teleport", spawn_pos)
		else:
			p.global_position = spawn_pos

@rpc("any_peer", "call_local", "reliable")
func _rpc_fade_black(in_sec: float, hold_sec: float, out_sec: float) -> void:
	_ensure_fade_ui()
	if _fade_rect == null:
		return
	var tw: Tween = create_tween()
	_fade_rect.visible = true
	var c: Color = _fade_rect.color
	c.a = 0.0
	_fade_rect.color = c
	tw.tween_property(_fade_rect, "color:a", 1.0, maxf(0.01, in_sec)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(maxf(0.0, hold_sec))
	tw.tween_property(_fade_rect, "color:a", 0.0, maxf(0.01, out_sec)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		if _fade_rect != null:
			_fade_rect.visible = false
	)

func _ensure_fade_ui() -> void:
	if _fade_layer != null and is_instance_valid(_fade_layer):
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 999
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.anchor_left = 0.0
	_fade_rect.anchor_top = 0.0
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.offset_left = 0.0
	_fade_rect.offset_top = 0.0
	_fade_rect.offset_right = 0.0
	_fade_rect.offset_bottom = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)

@rpc("any_peer", "call_local", "reliable")
func _rpc_slam_wall_face(wall_cell: Vector2i, forward: Vector2i, drop_h: float, slam_t: float, stagger: float) -> void:
	var half_w: int = int(_hall_width_now() / 2)
	var right: Vector2i = _right_vec(forward)
	var right_world: Vector3 = Vector3(float(right.x), 0.0, float(right.y)).normalized()
	var blocks: Array[Dictionary] = []
	for w in range(-half_w + 1, half_w):
		var c: Vector2i = wall_cell + right * w
		for h in range(1, wall_height_blocks + 1):
			var b: Node3D = _spawn_block(c.x, h, c.y)
			if b != null:
				blocks.append({"node": b, "w": w, "h": h})
	var i: int = 0
	for info_any in blocks:
		var info: Dictionary = info_any
		var blk: Node3D = info.get("node") as Node3D
		if blk == null or not is_instance_valid(blk):
			continue
		var w_i: int = int(info.get("w", 0))
		var h_i: int = int(info.get("h", 1))
		var dest: Vector3 = blk.global_position
		var sign_side: float = 0.0
		if w_i > 0:
			sign_side = 1.0
		elif w_i < 0:
			sign_side = -1.0
		var hh: int = int(("%d:%d:%d" % [int(dest.x * 100.0), int(dest.y * 100.0), int(dest.z * 100.0)]).hash())
		var jx: float = (float((hh >> 0) & 1023) / 1023.0) * 2.0 - 1.0
		var jz: float = (float((hh >> 10) & 1023) / 1023.0) * 2.0 - 1.0
		var jy: float = (float((hh >> 20) & 1023) / 1023.0) * 2.0 - 1.0
		var jitter: Vector3 = Vector3(jx, jy, jz) * organic_jitter_m
		var inward: Vector3 = (-right_world * sign_side) * (organic_inset_m if organic_slam_enabled else 0.0)
		var up_extra: float = (organic_extra_up_m if organic_slam_enabled else 0.0) * (float(h_i) / float(maxi(1, wall_height_blocks)))
		var start_pos: Vector3 = dest + inward + Vector3(0.0, drop_h + up_extra, 0.0) + jitter
		blk.global_position = start_pos
		var tw := create_tween()
		tw.tween_interval(float(i) * stagger)
		tw.tween_property(blk, "global_position", dest, maxf(0.01, slam_t)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		i += 1

func _build_hall_segment(start: Vector2i, forward: Vector2i, length: int) -> void:
	var half_w: int = int(_hall_width_now() / 2)
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

func _place_end_wall_full(wall_cell: Vector2i, forward: Vector2i) -> void:
	var half_w: int = int(_hall_width_now() / 2)
	var right: Vector2i = _right_vec(forward)
	for w in range(-half_w, half_w + 1):
		var c: Vector2i = wall_cell + right * w
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(c.x, h, c.y)
		if build_ceiling:
			_spawn_block(c.x, wall_height_blocks + 1, c.y)

func _build_end_wall_with_doors(door_wall_cell: Vector2i, forward: Vector2i) -> void:
	var half_w: int = int(_hall_width_now() / 2)
	var right: Vector2i = _right_vec(forward)
	for w in range(-half_w, half_w + 1):
		var c: Vector2i = door_wall_cell + right * w
		for h in range(1, wall_height_blocks + 1):
			_spawn_block(c.x, h, c.y)
		if build_ceiling:
			_spawn_block(c.x, wall_height_blocks + 1, c.y)
	var offs: Array[int] = _door_offsets()
	for off_any in offs:
		var off: int = int(off_any)
		var door_cell: Vector2i = door_wall_cell + right * off
		_remove_wall_column_height(door_cell.x, door_cell.y, door_open_height_blocks)

func _door_open_cell(door_wall_cell: Vector2i, forward: Vector2i, door_offset: int) -> Vector2i:
	var door_cell: Vector2i = door_wall_cell + _right_vec(forward) * door_offset
	return door_cell + forward

func _place_door_panels_behind_openings(door_wall_cell: Vector2i, forward: Vector2i) -> void:
	# CHANGED: final mode door should be "already open" (no blocking panels)
	if _final_mode:
		for i in range(3):
			(_door_panel_blocks[i] as Array).clear()
			(_door_panel_keys[i] as Array).clear()
		return

	var right: Vector2i = _right_vec(forward)
	var offs: Array[int] = _door_offsets()
	for i in range(offs.size()):
		(_door_panel_blocks[i] as Array).clear()
		(_door_panel_keys[i] as Array).clear()
		var door_cell_in_wall: Vector2i = door_wall_cell + right * int(offs[i])
		var panel_cell: Vector2i = door_cell_in_wall + forward
		for h in range(1, door_open_height_blocks + 1):
			var inst: Node3D = _spawn_block(panel_cell.x, h, panel_cell.y)
			if inst != null:
				(_door_panel_blocks[i] as Array).append(inst)
				(_door_panel_keys[i] as Array).append(_key(panel_cell.x, h, panel_cell.y))

func _place_cap_wall_record(cell: Vector2i, door_idx: int) -> void:
	(_cap_blocks[door_idx] as Array).clear()
	(_cap_keys[door_idx] as Array).clear()
	_spawn_block(cell.x, 0, cell.y)
	if build_ceiling:
		_spawn_block(cell.x, wall_height_blocks + 1, cell.y)
	for h in range(1, wall_height_blocks + 1):
		var bh: Node3D = _spawn_block(cell.x, h, cell.y)
		if bh != null:
			(_cap_blocks[door_idx] as Array).append(bh)
			(_cap_keys[door_idx] as Array).append(_key(cell.x, h, cell.y))

func _place_spawn_marker() -> void:
	if _spawn_marker == null or not is_instance_valid(_spawn_marker):
		return
	var c: Vector2i = Vector2i(0, spawn_cell_z)
	var p: Vector3 = _cell_to_world(c)
	p.y = _floor_top_y() + spawn_height_above_floor
	_spawn_marker.global_position = p

func _right_vec(forward: Vector2i) -> Vector2i:
	return Vector2i(forward.y, -forward.x)

func _spawn_block(x: int, y_level_blocks: int, z: int) -> Node3D:
	var k: String = _key(x, y_level_blocks, z)
	if _spawned.has(k):
		return _spawned[k] as Node3D
	var inst: Node3D = block_scene.instantiate() as Node3D
	if inst == null:
		return null
	_world_root.add_child(inst)
	var wp: Vector3 = _cell_to_world(Vector2i(x, z))
	wp.y = _world_origin.y + y_offset_m + float(y_level_blocks) * block_size_m
	inst.global_position = wp
	_spawned[k] = inst
	if not _phase.has(k):
		var hh: int = int(k.hash())
		_phase[k] = float(hh % 628) / 100.0
		_base_pos[k] = inst.global_position
		_base_scale[k] = inst.scale
	return inst

func _remove_wall_column_height(x: int, z: int, height_blocks: int) -> void:
	var hmax: int = clampi(height_blocks, 1, wall_height_blocks)
	for h in range(1, hmax + 1):
		var k: String = _key(x, h, z)
		if _spawned.has(k):
			var n: Node = _spawned[k] as Node
			if n != null and is_instance_valid(n):
				n.queue_free()
			_spawned.erase(k)
			_base_pos.erase(k)
			_base_scale.erase(k)
			_phase.erase(k)

func _cell_to_world(cell: Vector2i) -> Vector3:
	var px: float = (float(cell.x) + 0.5) * block_size_m
	var pz: float = (float(cell.y) + 0.5) * block_size_m
	return _world_origin + Vector3(px, 0.0, pz)

func _floor_top_y() -> float:
	return _world_origin.y + y_offset_m + (block_size_m * 0.5)

func _key(x: int, y: int, z: int) -> String:
	return "%d:%d:%d" % [x, y, z]

func _clear_world() -> void:
	var kids: Array = _world_root.get_children()
	for c_any in kids:
		var n: Node = c_any as Node
		if n != null:
			n.queue_free()
	_spawned.clear()
	_base_pos.clear()
	_base_scale.clear()
	_phase.clear()

func _player_for_owner(owner_id: int) -> Node3D:
	var players: Array = get_tree().get_nodes_in_group("player")
	for n_any in players:
		var p: Node3D = n_any as Node3D
		if p != null and int(p.get_multiplayer_authority()) == owner_id:
			return p
	return null

# =========================
# SYMBOLS
# =========================
func _resolve_symbols_root() -> void:
	if symbols_root_path != NodePath(""):
		_symbols_root = get_node_or_null(symbols_root_path) as Node3D
	if _symbols_root == null:
		_symbols_root = get_node_or_null("Symbols") as Node3D
	if _symbols_root == null:
		_symbols_root = Node3D.new()
		_symbols_root.name = "Symbols"
		add_child(_symbols_root)

func _spawn_symbols_for_current_hub(door_wall_cell: Vector2i, forward: Vector2i, hub_id: int) -> void:
	if _symbols_root == null:
		return
	if correct_symbol_scene == null or wrong_symbol_scene_a == null:
		return
	for ch_any in _symbols_root.get_children():
		var ch: Node = ch_any as Node
		if ch != null and ch.has_meta("hub_id") and int(ch.get_meta("hub_id")) == hub_id:
			ch.queue_free()
	var right: Vector2i = _right_vec(forward)
	var fwd_world: Vector3 = Vector3(float(forward.x), 0.0, float(forward.y)).normalized()
	var wrong_scene_2: PackedScene = (wrong_symbol_scene_b if wrong_symbol_scene_b != null else wrong_symbol_scene_a)
	var wrong_a_door: int = (_progress_door + 1) % 3
	var wrong_b_door: int = (_progress_door + 2) % 3
	for door_i in range(3):
		var ps: PackedScene = null
		if door_i == _progress_door:
			ps = correct_symbol_scene
		elif door_i == wrong_a_door:
			ps = wrong_symbol_scene_a
		else:
			ps = wrong_scene_2
		if ps == null:
			continue
		var inst_any := ps.instantiate()
		var inst := inst_any as Node3D
		if inst == null:
			_symbols_root.add_child(inst_any)
			continue
		inst.set_meta("hub_id", hub_id)
		inst.set_meta("door_index", door_i)
		inst.name = "DoorSymbol_%d_%d" % [hub_id, door_i]
		_symbols_root.add_child(inst)
		var door_cell: Vector2i = door_wall_cell + right * door_x_offsets_three[door_i]
		var base: Vector3 = _cell_to_world(door_cell)
		var y_top: float = _floor_top_y() + (float(door_open_height_blocks) * block_size_m) + symbol_extra_y_offset_m
		y_top += float(symbol_up_blocks) * block_size_m
		var push_fwd: float = symbol_inside_offset_m + symbol_forward_extra_m
		var pos: Vector3 = base - fwd_world * push_fwd
		pos.y = y_top
		inst.global_position = pos

@rpc("any_peer", "call_local", "reliable")
func _rpc_respawn_symbols_for_current_hub(hub_id: int) -> void:
	if _symbols_root == null:
		return
	for ch_any in _symbols_root.get_children():
		var ch: Node = ch_any as Node
		if ch != null and ch.has_meta("hub_id") and int(ch.get_meta("hub_id")) == hub_id:
			ch.queue_free()
	var door_wall_cell: Vector2i = _cursor + _forward * entry_len_before_doors
	_spawn_symbols_for_current_hub(door_wall_cell, _forward, hub_id)

@rpc("any_peer", "call_local", "reliable")
func _rpc_delete_symbols_by_hub(hub_id: int) -> void:
	if _symbols_root == null:
		return
	for ch_any in _symbols_root.get_children():
		var ch: Node = ch_any as Node
		if ch != null and ch.has_meta("hub_id") and int(ch.get_meta("hub_id")) == hub_id:
			ch.queue_free()

func _clear_all_symbols() -> void:
	if _symbols_root == null:
		return
	for ch_any in _symbols_root.get_children():
		var ch: Node = ch_any as Node
		if ch != null:
			ch.queue_free()
