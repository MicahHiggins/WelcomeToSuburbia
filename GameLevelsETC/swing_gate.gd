extends Area3D
class_name BatSwingGate

@export var required_player_count: int = 2
@export var required_item_id: StringName = &"bat"

@export var play_video_player: VideoStreamPlayer = null
@export var start_video_on_show: bool = true

@export var also_change_to_level_3: bool = true
@export var level_3_index: int = 3
@export var level_change_delay_sec: float = 3.0

@export var debug_enabled: bool = true
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

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		monitoring = false
		monitorable = false
	else:
		monitoring = true
		monitorable = true

	if debug_enabled:
		print("GATE READY | name:", name, " path:", get_path(), " server:", multiplayer.is_server(), " uid:", multiplayer.get_unique_id())
		print("GATE MASK/LAYER | layer:", collision_layer, " mask:", collision_mask, " monitoring:", monitoring, " monitorable:", monitorable)

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

	if not _is_coordinator_gate():
		return

	var do_dbg: bool = false
	if debug_enabled and debug_print_every_sec > 0.0:
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = debug_print_every_sec
			_dbg_frame += 1
			do_dbg = true

	_try_complete_gate_server(do_dbg)

func _try_complete_gate_server(do_dbg: bool) -> void:
	var union: Dictionary = _collect_overlapping_union(do_dbg)

	var ok_count: int = 0
	var ok_pids: Array[int] = []

	var players: Array = get_tree().get_nodes_in_group("player")
	var want: String = String(required_item_id).to_lower()

	if do_dbg:
		print("--------------------------------------------------")
		print("GATE CHECK #", _dbg_frame, " coordinator:", name, " gates:", get_tree().get_nodes_in_group("bat_swing_gate").size())
		print("GATE UNION INSIDE PIDS:", union.keys())

	for p_any in players:
		var p: Node = p_any as Node
		if p == null:
			continue

		var pid: int = _peer_id_from_player(p)
		if pid <= 0:
			continue

		var in_any: bool = union.has(pid)
		var inv_arr: Array = _get_inventory_array(p)
		var has_item: bool = _inv_has(inv_arr, want)

		if do_dbg:
			print("GATE P | pid:", pid,
				" in_any:", in_any,
				" inv_sz:", inv_arr.size(),
				" inv:", inv_arr,
				" has_item:", has_item,
				" authority:", int(p.get_multiplayer_authority()),
				" node:", p.name
			)

		if in_any and has_item:
			ok_count += 1
			ok_pids.append(pid)

	if do_dbg:
		print("GATE RESULT | ok_count:", ok_count, "/", required_player_count, " ok_pids:", ok_pids)

	if ok_count >= required_player_count:
		_done = true
		if do_dbg:
			print("GATE TRIGGERED | playing video + scheduling level change")
		rpc("_rpc_play_gate_video")
		if also_change_to_level_3:
			_level_change_queued = true
			_level_change_timer = maxf(0.0, level_change_delay_sec)

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
			print(" - gate:", g.name, " bodies:", bodies.size(), " player_pids:", ids)

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

func _get_inventory_array(p: Node) -> Array:
	if p == null:
		return []
	var inv_any: Variant = p.get("inventory")
	if inv_any is Array:
		return inv_any as Array
	return []

func _inv_has(inv_arr: Array, want_lower: String) -> bool:
	for it in inv_arr:
		if String(it).to_lower() == want_lower:
			return true
	return false

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
