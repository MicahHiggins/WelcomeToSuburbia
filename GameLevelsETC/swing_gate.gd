extends Area3D
class_name BatSwingGate

@export var required_player_count: int = 2

# NEW: gate only works after puzzle 2 is completed (server-approved)
@export var require_puzzle2_done: bool = true
@export var puzzle_state_group: StringName = &"puzzle_state" # node that owns puzzle2_done

@export var play_video_player: VideoStreamPlayer = null
@export var start_video_on_show: bool = true

@export var also_change_to_level_3: bool = true
@export var level_3_index: int = 3
@export var level_change_delay_sec: float = 3.0

@export var debug_enabled: bool = false
@export var debug_print_every_sec: float = 1.0

var _done: bool = false
var _level_change_queued: bool = false
var _level_change_timer: float = 0.0
var _dbg_t: float = 0.0
var _dbg_frame: int = 0

func _enter_tree() -> void:
	if not is_in_group("bat_swing_gate"):
		add_to_group("bat_swing_gate")

func _ready() -> void:
	if play_video_player != null:
		play_video_player.visible = false

	# server-only authority
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
	else:
		set_deferred("monitoring", true)
		set_deferred("monitorable", true)

func _physics_process(delta: float) -> void:
	if _level_change_queued:
		_level_change_timer -= delta
		if _level_change_timer <= 0.0:
			_level_change_queued = false
			_call_level_change_level3()
		return

	if _done:
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# only one gate coordinates to avoid double-firing if multiple exist
	if not _is_coordinator_gate():
		return

	var do_dbg := false
	if debug_enabled and debug_print_every_sec > 0.0:
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = debug_print_every_sec
			_dbg_frame += 1
			do_dbg = true

	_try_complete_gate_server(do_dbg)

func _try_complete_gate_server(do_dbg: bool) -> void:
	if require_puzzle2_done and not _is_puzzle2_done():
		if do_dbg:
			print("GATE CHECK #", _dbg_frame, " puzzle2_done=false (blocked)")
		return

	var union: Dictionary = _collect_overlapping_union(do_dbg)

	var ok_count: int = 0
	var ok_pids: Array[int] = []

	var players: Array = get_tree().get_nodes_in_group("player")

	for p_any in players:
		var p: Node = p_any as Node
		if p == null:
			continue

		var pid: int = _peer_id_from_player(p)
		if pid <= 0:
			continue

		if union.has(pid):
			ok_count += 1
			ok_pids.append(pid)

	if do_dbg:
		print("GATE CHECK #", _dbg_frame, " puzzle2_done=", _is_puzzle2_done(), " ok_count=", ok_count, " ok_pids=", ok_pids)

	if ok_count >= required_player_count:
		_done = true
		rpc("_rpc_play_gate_video")
		if also_change_to_level_3:
			_level_change_queued = true
			_level_change_timer = maxf(0.0, level_change_delay_sec)

func _is_puzzle2_done() -> bool:
	var nodes: Array = get_tree().get_nodes_in_group(String(puzzle_state_group))
	if nodes.is_empty():
		return false
	var st: Node = nodes[0] as Node
	if st == null:
		return false
	var v: Variant = st.get("puzzle2_done")
	return (v is bool) and bool(v)

func _collect_overlapping_union(do_dbg: bool) -> Dictionary:
	var union: Dictionary = {}
	var gates: Array = get_tree().get_nodes_in_group("bat_swing_gate")

	if do_dbg:
		print("GATE OVERLAPS (per gate):")

	for g_any in gates:
		var g: Area3D = g_any as Area3D
		if g == null:
			continue
		if not g.monitoring:
			if do_dbg:
				print(" - gate:", g.name, " monitoring=false (skipped)")
			continue

		var bodies: Array = g.get_overlapping_bodies()

		if do_dbg:
			var ids: Array[int] = []
			for b_any in bodies:
				var b: Node = b_any as Node
				if b == null:
					continue
				if not b.is_in_group("player"):
					continue
				var pid: int = _peer_id_from_player(b)
				if pid > 0:
					ids.append(pid)
			print(" - gate:", g.name, " player_pids:", ids)

		for b_any in bodies:
			var b2: Node = b_any as Node
			if b2 == null:
				continue
			if not b2.is_in_group("player"):
				continue
			var pid2: int = _peer_id_from_player(b2)
			if pid2 > 0:
				union[pid2] = true

	return union

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_gate_video() -> void:
	_play_video_local()

func _play_video_local() -> void:
	if play_video_player == null:
		return
	play_video_player.visible = true
	if start_video_on_show:
		play_video_player.stop()
		play_video_player.play()

func _call_level_change_level3() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var lf: Node = get_tree().get_first_node_in_group("level_flow_manager")
	if lf == null:
		return
	if lf.has_method("request_level_change"):
		lf.call("request_level_change", level_3_index)

func _peer_id_from_player(p: Node) -> int:
	if p == null:
		return -1
	if p.has_method("get_multiplayer_authority"):
		return int(p.get_multiplayer_authority())
	var nm: String = String(p.name)
	if nm.is_valid_int():
		return int(nm)
	return -1

func _is_coordinator_gate() -> bool:
	var gates: Array = get_tree().get_nodes_in_group("bat_swing_gate")
	var best: Node = null
	var best_id: int = 2147483647
	for g_any in gates:
		var g: Node = g_any as Node
		if g == null:
			continue
		var iid: int = int(g.get_instance_id())
		if iid < best_id:
			best_id = iid
			best = g
	return best == self
