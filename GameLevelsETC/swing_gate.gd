extends Area3D
class_name BatSwingGate

@export var required_player_count: int = 2

@export var require_puzzle2_done: bool = true
@export var puzzle_state_group: StringName = &"puzzle_state"

@export var play_video_player: VideoStreamPlayer = null
@export var start_video_on_show: bool = true

@export var also_change_to_level_3: bool = true
@export var level_3_index: int = 3

@export var wait_for_video_finish: bool = true
@export var level_change_delay_sec: float = 3.0
@export var video_wait_timeout_sec: float = 12.0

@export var clear_inventories_on_trigger: bool = true
@export var item_manager_name: StringName = &"ItemManager"

@export var debug_enabled: bool = false
@export var debug_print_every_sec: float = 1.0

var _done: bool = false
var _level_change_queued: bool = false
var _level_change_timer: float = 0.0

var _dbg_t: float = 0.0
var _dbg_frame: int = 0

var _video_waiting: bool = false
var _video_wait_deadline: float = 0.0
var _wait_pids: Array[int] = []
var _video_done_by_pid: Dictionary = {} # int -> bool

func _enter_tree() -> void:
	if not is_in_group("bat_swing_gate"):
		add_to_group("bat_swing_gate")

func _ready() -> void:
	if play_video_player != null:
		play_video_player.visible = false

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
	else:
		set_deferred("monitoring", true)
		set_deferred("monitorable", true)

func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if _level_change_queued:
		_level_change_timer -= delta
		if _level_change_timer <= 0.0:
			_level_change_queued = false
			_call_level_change_level3()
		return

	if _video_waiting:
		_video_wait_deadline -= delta
		if _all_wait_pids_done():
			_video_waiting = false
			_call_level_change_level3()
			return
		if _video_wait_deadline <= 0.0:
			_video_waiting = false
			_call_level_change_level3()
			return
		return

	if _done:
		return

	if not _is_coordinator_gate():
		if debug_enabled:
			_dbg_t -= delta
			if _dbg_t <= 0.0:
				_dbg_t = maxf(0.05, debug_print_every_sec)
				print("GATE | not coordinator (skipping) | me:", name, " coordinator:", _coordinator_path())
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
			print("GATE BLOCKED | puzzle2_done=false")
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
		print("GATE RESULT | ok_count:", ok_count, "/", required_player_count, " ok_pids:", ok_pids)

	if ok_count < required_player_count:
		return

	_done = true

	if clear_inventories_on_trigger:
		_server_drop_and_clear_for_pids(ok_pids, do_dbg)

	rpc("_rpc_play_gate_video")

	if not also_change_to_level_3:
		return

	if wait_for_video_finish:
		_begin_video_wait_server(ok_pids, do_dbg)
	else:
		_level_change_queued = true
		_level_change_timer = maxf(0.0, level_change_delay_sec)

func _begin_video_wait_server(ok_pids: Array[int], do_dbg: bool) -> void:
	_video_waiting = true
	_video_wait_deadline = maxf(0.25, video_wait_timeout_sec)

	_wait_pids.clear()
	_video_done_by_pid.clear()

	for pid in ok_pids:
		_wait_pids.append(pid)
		_video_done_by_pid[pid] = false

	if do_dbg:
		print("GATE | begin video wait | wait_pids:", _wait_pids, " timeout:", _video_wait_deadline)

func _all_wait_pids_done() -> bool:
	for pid in _wait_pids:
		if not _video_done_by_pid.has(pid):
			return false
		if not bool(_video_done_by_pid[pid]):
			return false
	return true

@rpc("any_peer", "reliable")
func _rpc_client_video_done(pid: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if pid <= 0:
		return
	if _video_done_by_pid.has(pid):
		_video_done_by_pid[pid] = true
		if debug_enabled:
			print("GATE | video done ack | pid:", pid)

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_gate_video() -> void:
	_play_video_local_and_ack()

func _play_video_local_and_ack() -> void:
	var wait_sec := _estimate_video_seconds_client()

	if play_video_player != null and is_instance_valid(play_video_player):
		play_video_player.visible = true
		if start_video_on_show:
			play_video_player.stop()
			play_video_player.play()

		var t := get_tree().create_timer(maxf(0.05, wait_sec))
		await t.timeout
	else:
		var t2 := get_tree().create_timer(maxf(0.05, wait_sec))
		await t2.timeout

	var pid := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if multiplayer.has_multiplayer_peer():
		var sid := _server_peer_id()
		if sid > 0:
			rpc_id(sid, "_rpc_client_video_done", int(pid))

func _estimate_video_seconds_client() -> float:
	# If the stream length is unknown, use the server timeout (not the 3s fallback).
	var fallback := maxf(0.0, video_wait_timeout_sec)

	if play_video_player == null or not is_instance_valid(play_video_player):
		return fallback

	var s := play_video_player.stream
	if s == null:
		return fallback

	var len_sec: float = 0.0
	if s.has_method("get_length"):
		len_sec = float(s.call("get_length"))

	if len_sec <= 0.0:
		return fallback

	return len_sec + 0.15

func _server_drop_and_clear_for_pids(pids: Array[int], do_dbg: bool) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var im := _get_item_manager()
	var players := get_tree().get_nodes_in_group("player")

	for p_any in players:
		var p := p_any as Node
		if p == null:
			continue

		var pid := _peer_id_from_player(p)
		if pid <= 0 or not pids.has(pid):
			continue

		# Drop anything physically held (CarryObjectMarker child)
		if im != null and p is Node3D:
			var marker := (p as Node3D).get_node_or_null("Head/CarryObjectMarker") as Node
			if marker != null and marker.get_child_count() > 0:
				var held := marker.get_child(0) as Node
				if held != null and held.has_meta("item_key"):
					var key_str := String(held.get_meta("item_key"))
					if key_str != "" and im.has_method("server_force_drop_for_peer"):
						im.call("server_force_drop_for_peer", NodePath(key_str), pid)
						if do_dbg:
							print("GATE INV | force dropped held item for pid:", pid, " key:", key_str)

		# Safety: clear inventory array too (UI / any leftover bookkeeping)
		var inv_any: Variant = p.get("inventory")
		if inv_any is Array:
			var inv: Array = inv_any as Array
			inv.clear()
			p.set("inventory", inv)

func _get_item_manager() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var direct := scene.get_node_or_null(String(item_manager_name))
	if direct != null:
		return direct
	return scene.find_child(String(item_manager_name), true, false)

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

	for g_any in gates:
		var g := g_any as Area3D
		if g == null or not g.monitoring:
			continue

		for b_any in g.get_overlapping_bodies():
			var b := b_any as Node
			if b == null:
				continue
			if not b.is_in_group("player"):
				continue
			var pid := _peer_id_from_player(b)
			if pid > 0:
				union[pid] = true

	if do_dbg:
		print("GATE UNION PIDS:", union.keys())

	return union

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

func _server_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return -1
	if multiplayer.is_server():
		return multiplayer.get_unique_id()
	var peers: Array = multiplayer.get_peers()
	if peers.is_empty():
		return -1
	var best: int = int(peers[0])
	for p_any in peers:
		var p: int = int(p_any)
		if p < best:
			best = p
	return best

func _is_coordinator_gate() -> bool:
	var gates: Array = get_tree().get_nodes_in_group("bat_swing_gate")
	if gates.is_empty():
		return true

	var best: Node = null
	var best_path: String = ""
	for g_any in gates:
		var g: Node = g_any as Node
		if g == null:
			continue
		var p: String = String(g.get_path())
		if best == null or p < best_path:
			best = g
			best_path = p
	return best == self

func _coordinator_path() -> String:
	var gates: Array = get_tree().get_nodes_in_group("bat_swing_gate")
	var best_path: String = ""
	for g_any in gates:
		var g: Node = g_any as Node
		if g == null:
			continue
		var p: String = String(g.get_path())
		if best_path == "" or p < best_path:
			best_path = p
	return best_path
