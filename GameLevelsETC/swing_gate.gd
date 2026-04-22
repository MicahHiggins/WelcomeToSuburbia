extends Area3D
class_name BatSwingGate

@export var required_player_count: int = 2
@export var required_item_id: StringName = &"bat"

@export var play_video_player: VideoStreamPlayer = null
@export var start_video_on_show: bool = true

@export var also_change_to_level_3: bool = true
@export var level_3_index: int = 3
@export var level_change_delay_sec: float = 3.0

var _inside: Dictionary = {}
var _done: bool = false
var _level_change_queued: bool = false
var _level_change_timer: float = 0.0


func _enter_tree() -> void:
	if not is_in_group("bat_swing_gate"):
		add_to_group("bat_swing_gate")


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	if play_video_player != null:
		play_video_player.visible = false

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		monitoring = false
		monitorable = false


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

	_try_complete_gate_server()


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return

	var pid := _peer_id_from_player(body)
	if pid <= 0:
		return

	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		_inside[pid] = true
	else:
		_inside[pid] = true


func _on_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return

	var pid := _peer_id_from_player(body)
	if pid <= 0:
		return

	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		_inside.erase(pid)
	else:
		_inside.erase(pid)


func _try_complete_gate_server() -> void:
	var count_ok := 0
	var players := get_tree().get_nodes_in_group("player")
	for p_any in players:
		var p := p_any as Node
		if p == null:
			continue

		var pid := _peer_id_from_player(p)
		if pid <= 0:
			continue
		if not _inside.has(pid):
			continue
		if not _player_has_required_item(p):
			continue

		count_ok += 1
		if count_ok >= required_player_count:
			break

	if count_ok >= required_player_count:
		_done = true
		rpc("_rpc_play_gate_video")
		if also_change_to_level_3:
			_level_change_queued = true
			_level_change_timer = maxf(0.0, level_change_delay_sec)


func _player_has_required_item(p: Node) -> bool:
	if p == null:
		return false

	if p.has_variable("inventory"):
		var inv = p.get("inventory")
		if inv is Array:
			for it in inv:
				if StringName(str(it)) == required_item_id:
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
