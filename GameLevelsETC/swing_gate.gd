extends Area3D
class_name BatSwingGate

const SERVER_ID: int = 1

@export var required_player_count: int = 2
@export var play_anim_player: AnimationPlayer = null
@export var play_anim_name: StringName = &""
@export var also_change_to_level_3: bool = true
@export var level_3_index: int = 3

var _inside: Dictionary = {}
var _swung: Dictionary = {}
var _done: bool = false


func _enter_tree() -> void:
	if not is_in_group("bat_swing_gate"):
		add_to_group("bat_swing_gate")


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return

	if multiplayer.has_multiplayer_peer():
		if not _is_my_local_player(body):
			return
		var pid := int((body as Node).get_multiplayer_authority())

		if multiplayer.is_server():
			_rpc_set_inside(pid, true)
		else:
			rpc_id(SERVER_ID, "_rpc_set_inside", pid, true)
	else:
		var pid2 := _peer_id_from_player(body)
		if pid2 > 0:
			_inside[pid2] = true


func _on_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return

	if multiplayer.has_multiplayer_peer():
		if not _is_my_local_player(body):
			return
		var pid := int((body as Node).get_multiplayer_authority())

		if multiplayer.is_server():
			_rpc_set_inside(pid, false)
		else:
			rpc_id(SERVER_ID, "_rpc_set_inside", pid, false)
	else:
		var pid2 := _peer_id_from_player(body)
		if pid2 > 0:
			_inside.erase(pid2)
			_swung.erase(pid2)


func notify_swing(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_mark_swing(peer_id)
		else:
			rpc_id(SERVER_ID, "_rpc_client_swing", peer_id)
	else:
		_mark_swing_local(peer_id)


@rpc("any_peer", "reliable")
func _rpc_set_inside(peer_id: int, is_inside: bool) -> void:
	if not multiplayer.is_server():
		return
	if peer_id <= 0:
		return

	if is_inside:
		_inside[peer_id] = true
	else:
		_inside.erase(peer_id)
		_swung.erase(peer_id)


@rpc("any_peer", "reliable")
func _rpc_client_swing(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_mark_swing(peer_id)


func _server_mark_swing(peer_id: int) -> void:
	if _done:
		return
	if peer_id <= 0:
		return
	if not _inside.has(peer_id):
		return

	_swung[peer_id] = true

	var count := 0
	for k in _swung.keys():
		if _swung.get(int(k), false) == true:
			count += 1

	if count >= required_player_count:
		_done = true
		rpc("_rpc_play_gate_anim")
		if also_change_to_level_3:
			_call_level_change_level3()


func _mark_swing_local(peer_id: int) -> void:
	if _done:
		return
	if peer_id <= 0:
		return

	_swung[peer_id] = true

	var count := 0
	for k in _swung.keys():
		if _swung.get(int(k), false) == true:
			count += 1

	if count >= required_player_count:
		_done = true
		_play_anim_local()


@rpc("any_peer", "call_local", "reliable")
func _rpc_play_gate_anim() -> void:
	_play_anim_local()


func _play_anim_local() -> void:
	if play_anim_player == null:
		return
	var a := String(play_anim_name)
	if a == "":
		return
	if play_anim_player.has_animation(a):
		play_anim_player.play(a)


func _call_level_change_level3() -> void:
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


func _is_my_local_player(body: Node) -> bool:
	if body == null:
		return false
	if not body.has_method("is_multiplayer_authority"):
		return false
	return (body as Node).is_multiplayer_authority()
