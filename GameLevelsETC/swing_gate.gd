extends Area3D
class_name BatSwingGate

@export var required_player_count: int = 2
@export var required_item_id: StringName = &"bat"

@export var play_video_player: VideoStreamPlayer = null
@export var start_video_on_show: bool = true

@export var also_change_to_level_3: bool = true
@export var level_3_index: int = 3
@export var level_change_delay_sec: float = 3.0

var _done := false
var _level_change_queued := false
var _level_change_timer := 0.0
var _debug_tick := 0.0

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

	print("GATE READY | path:", get_path(), " server:", multiplayer.is_server(), " uid:", multiplayer.get_unique_id())
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

	_debug_tick -= delta
	var do_debug := false
	if _debug_tick <= 0.0:
		_debug_tick = 0.50
		do_debug = true

	_try_complete_gate_server(do_debug)

func _try_complete_gate_server(do_debug: bool) -> void:
	var inside_any := _collect_overlapping_union()

	var ok_count := 0
	var ok_pids: Array[int] = []

	var players := get_tree().get_nodes_in_group("player")
	for p_any in players:
		var p := p_any as Node
		if p == null:
			continue

		var pid := _peer_id_from_player(p)
		if pid <= 0:
			continue

		var in_any := inside_any.has(pid)
		var has_item := _player_has_required_item(p)

		if do_debug:
			var inv = p.get("inventory")
			print("GATE DEBUG | pid:", pid, " in_any:", in_any, " has_item:", has_item, " inv:", inv, " inside_any:", inside_any.keys())

		if not in_any:
			continue
		if not has_item:
			continue

		ok_count += 1
		ok_pids.append(pid)
		if ok_count >= required_player_count:
			break

	if do_debug:
		print("GATE DEBUG | ok_count:", ok_count, " required:", required_player_count, " ok_pids:", ok_pids)

	if ok_count >= required_player_count:
		_done = true
		rpc("_rpc_play_gate_video")
		if also_change_to_level_3:
			_level_change_queued = true
			_level_change_timer = maxf(0.0, level_change_delay_sec)

func _collect_overlapping_union() -> Dictionary:
	var union: Dictionary = {}
	var gates := get_tree().get_nodes_in_group("bat_swing_gate")

	for g_any in gates:
		var g := g_any as Area3D
		if g == null:
			continue
		if not g.monitoring:
			continue

		var bodies := g.get_overlapping_bodies()
		for b_any in bodies:
			var b := b_any as Node
			if b == null:
				continue
			if not b.is_in_group("player"):
				continue
			var pid := _peer_id_from_player(b)
			if pid > 0:
				union[pid] = true

	return union

func _player_has_required_item(p: Node) -> bool:
	var want := String(required_item_id).to_lower()

	var inv = p.get("inventory")
	if inv is Array:
		for it in inv:
			if String(it).to_lower() == want:
				return true

	if p.has_method("has_item_id"):
		return bool(p.call("has_item_id", required_item_id))

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
	var lf := get_tree().get_first_node_in_group("level_flow_manager")
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
	var nm := String(p.name)
	if nm.is_valid_int():
		return int(nm)
	return -1

func _is_coordinator_gate() -> bool:
	var gates := get_tree().get_nodes_in_group("bat_swing_gate")
	var best: Node = null
	var best_id := 9223372036854775807
	for g_any in gates:
		var g := g_any as Node
		if g == null:
			continue
		var iid := int(g.get_instance_id())
		if iid < best_id:
			best_id = iid
			best = g
	return best == self
