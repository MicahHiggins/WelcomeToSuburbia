extends Area3D
class_name BatSwingGate

@export var required_player_count: int = 2

@export var require_puzzle2_done: bool = true
@export var puzzle_state_group: StringName = &"puzzle_state"

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
var _printed_ready: bool = false

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

	if debug_enabled:
		_print_ready_dump()

func _physics_process(delta: float) -> void:
	if _level_change_queued:
		_level_change_timer -= delta
		if _level_change_timer <= 0.0:
			_level_change_queued = false
			if debug_enabled:
				print("GATE | level change timer hit 0 -> request level", level_3_index)
			_call_level_change_level3()
		return

	if _done:
		return

	# server-only
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if debug_enabled and not _printed_ready:
			_print_ready_dump()
		return

	# coordinator-only
	if not _is_coordinator_gate():
		if debug_enabled:
			_dbg_t -= delta
			if _dbg_t <= 0.0:
				_dbg_t = maxf(0.05, debug_print_every_sec)
				print("GATE | not coordinator (skipping) | me:", name, " iid:", int(get_instance_id()))
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
	if do_dbg:
		print("==================================================")
		print("GATE CHECK #", _dbg_frame, " name:", name, " server:", multiplayer.is_server(), " uid:", multiplayer.get_unique_id())
		print("GATE STATE | done:", _done, " queued:", _level_change_queued, " monitoring:", monitoring, " monitorable:", monitorable)
		print("GATE CONFIG | require_puzzle2_done:", require_puzzle2_done, " group:", String(puzzle_state_group), " need_players:", required_player_count)

	var p2 := _is_puzzle2_done_verbose(do_dbg)
	if require_puzzle2_done and not p2:
		if do_dbg:
			print("GATE BLOCKED | puzzle2_done=false")
		return

	var union: Dictionary = _collect_overlapping_union(do_dbg)

	var ok_count: int = 0
	var ok_pids: Array[int] = []
	var players: Array = get_tree().get_nodes_in_group("player")

	if do_dbg:
		print("GATE PLAYERS IN GROUP:", players.size())

	for p_any in players:
		var p: Node = p_any as Node
		if p == null:
			continue

		var pid: int = _peer_id_from_player(p)
		var in_any: bool = union.has(pid)

		if do_dbg:
			print(" - P | name:", p.name,
				" pid:", pid,
				" in_gate_union:", in_any,
				" authority:", int(p.get_multiplayer_authority())
			)

		if pid > 0 and in_any:
			ok_count += 1
			ok_pids.append(pid)

	if do_dbg:
		print("GATE RESULT | ok_count:", ok_count, "/", required_player_count, " ok_pids:", ok_pids)

	if ok_count >= required_player_count:
		_done = true
		if debug_enabled:
			print("GATE TRIGGERED | playing video + scheduling level change in", level_change_delay_sec, "sec")

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

func _is_puzzle2_done_verbose(do_dbg: bool) -> bool:
	var nodes: Array = get_tree().get_nodes_in_group(String(puzzle_state_group))

	if do_dbg:
		print("PUZZLE STATE NODES | group:", String(puzzle_state_group), " count:", nodes.size())

	if nodes.is_empty():
		if do_dbg:
			print("PUZZLE STATE | NONE FOUND -> puzzle2_done=false")
		return false

	if do_dbg:
		for n_any in nodes:
			var n: Node = n_any as Node
			if n == null:
				continue
			var v: Variant = n.get("puzzle2_done")
			print(" - STATE NODE | name:", n.name, " path:", n.get_path(), " puzzle2_done raw:", v, " type:", typeof(v))

	var st: Node = nodes[0] as Node
	if st == null:
		return false

	var v2: Variant = st.get("puzzle2_done")
	var ok: bool = (v2 is bool) and bool(v2)

	if do_dbg:
		print("PUZZLE STATE | using first node:", st.name, " puzzle2_done:", ok)

	return ok

func _collect_overlapping_union(do_dbg: bool) -> Dictionary:
	var union: Dictionary = {}
	var gates: Array = get_tree().get_nodes_in_group("bat_swing_gate")

	if do_dbg:
		print("GATE GROUP COUNT:", gates.size())
		print("GATE OVERLAPS (per gate):")

	for g_any in gates:
		var g: Area3D = g_any as Area3D
		if g == null:
			continue

		if do_dbg:
			print(" - gate:", g.name,
				" monitoring:", g.monitoring,
				" monitorable:", g.monitorable
			)

		if not g.monitoring:
			continue

		var bodies: Array = g.get_overlapping_bodies()

		if do_dbg:
			print("   bodies:", bodies.size())

		for b_any in bodies:
			var b2: Node = b_any as Node
			if b2 == null:
				continue

			var is_player := b2.is_in_group("player")
			var pid2 := _peer_id_from_player(b2)

			if do_dbg:
				print("   - body:", b2.name,
					" is_player:", is_player,
					" pid:", pid2,
					" class:", b2.get_class()
				)

			if not is_player:
				continue
			if pid2 > 0:
				union[pid2] = true

	if do_dbg:
		print("GATE UNION PIDS:", union.keys())

	return union

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_gate_video() -> void:
	_play_video_local()

func _play_video_local() -> void:
	if play_video_player == null:
		if debug_enabled:
			print("GATE VIDEO | play_video_player is null")
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
		if debug_enabled:
			print("GATE LEVEL CHANGE | no level_flow_manager in group")
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

func _print_ready_dump() -> void:
	_printed_ready = true
	print("GATE READY | name:", name, " path:", get_path(),
		" server:", multiplayer.is_server(),
		" has_peer:", multiplayer.has_multiplayer_peer(),
		" uid:", multiplayer.get_unique_id()
	)
	print("GATE FLAGS | monitoring:", monitoring, " monitorable:", monitorable,
		" layer:", collision_layer, " mask:", collision_mask
	)
	print("GATE GROUPS | bat_swing_gate:", get_tree().get_nodes_in_group("bat_swing_gate").size(),
		" player:", get_tree().get_nodes_in_group("player").size(),
		" puzzle_state:", get_tree().get_nodes_in_group(String(puzzle_state_group)).size()
	)
