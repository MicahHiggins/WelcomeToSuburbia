extends Area3D
class_name BatSwingGate

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
	print("GATE READY | name:", name, " path:", get_path(), " mp:", multiplayer.has_multiplayer_peer(), " server:", multiplayer.is_server(), " my_uid:", multiplayer.get_unique_id())
	print("GATE MASK/LAYER | layer:", collision_layer, " mask:", collision_mask, " monitoring:", monitoring, " monitorable:", monitorable)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _server_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return -1
	if multiplayer.is_server():
		return multiplayer.get_unique_id()
	var peers := multiplayer.get_peers()
	if peers == null or peers.is_empty():
		return -1
	var best := int(peers[0])
	for p_any in peers:
		var p := int(p_any)
		if p < best:
			best = p
	return best


func _on_body_entered(body: Node) -> void:
	print("GATE ENTER RAW | body:", body, " name:", (body.name if body != null else "null"))
	if body == null:
		return

	print("GATE ENTER CHECK | is_player_group:", body.is_in_group("player"), " class:", body.get_class())
	if not body.is_in_group("player"):
		return

	if multiplayer.has_multiplayer_peer():
		var is_local := _is_my_local_player(body)
		print("GATE ENTER MP | is_local:", is_local, " auth:", int(body.get_multiplayer_authority()), " my_uid:", multiplayer.get_unique_id())
		if not is_local:
			return

		var pid := int(body.get_multiplayer_authority())
		var sid := _server_peer_id()
		print("GATE ENTER -> SERVER TARGET | sid:", sid, " pid:", pid)

		if multiplayer.is_server():
			_rpc_set_inside(pid, true)
		else:
			if sid > 0:
				rpc_id(sid, "_rpc_set_inside", pid, true)
	else:
		var pid2 := _peer_id_from_player(body)
		print("GATE ENTER SP | pid:", pid2)
		if pid2 > 0:
			_inside[pid2] = true
			print("GATE INSIDE NOW:", _inside)


func _on_body_exited(body: Node) -> void:
	print("GATE EXIT RAW | body:", body, " name:", (body.name if body != null else "null"))
	if body == null:
		return

	print("GATE EXIT CHECK | is_player_group:", body.is_in_group("player"), " class:", body.get_class())
	if not body.is_in_group("player"):
		return

	if multiplayer.has_multiplayer_peer():
		var is_local := _is_my_local_player(body)
		print("GATE EXIT MP | is_local:", is_local, " auth:", int(body.get_multiplayer_authority()), " my_uid:", multiplayer.get_unique_id())
		if not is_local:
			return

		var pid := int(body.get_multiplayer_authority())
		var sid := _server_peer_id()
		print("GATE EXIT -> SERVER TARGET | sid:", sid, " pid:", pid)

		if multiplayer.is_server():
			_rpc_set_inside(pid, false)
		else:
			if sid > 0:
				rpc_id(sid, "_rpc_set_inside", pid, false)
	else:
		var pid2 := _peer_id_from_player(body)
		print("GATE EXIT SP | pid:", pid2)
		if pid2 > 0:
			_inside.erase(pid2)
			_swung.erase(pid2)
			print("GATE INSIDE NOW:", _inside, " SWUNG NOW:", _swung)


func notify_swing(peer_id: int) -> void:
	print("GATE NOTIFY_SWING | peer_id:", peer_id, " mp:true?", multiplayer.has_multiplayer_peer(), " server:", multiplayer.is_server(), " done:", _done)

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_mark_swing(peer_id)
		else:
			var sid := _server_peer_id()
			print("GATE SWING -> SERVER TARGET | sid:", sid, " peer_id:", peer_id)
			if sid > 0:
				rpc_id(sid, "_rpc_client_swing", peer_id)
	else:
		_mark_swing_local(peer_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_inside(peer_id: int, is_inside: bool) -> void:
	print("GATE RPC_SET_INSIDE | sender:", multiplayer.get_remote_sender_id(), " peer_id:", peer_id, " inside:", is_inside, " server:", multiplayer.is_server())
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if peer_id <= 0:
		return

	if is_inside:
		_inside[peer_id] = true
	else:
		_inside.erase(peer_id)
		_swung.erase(peer_id)

	print("GATE STATE | inside:", _inside, " swung:", _swung)


@rpc("any_peer", "reliable")
func _rpc_client_swing(peer_id: int) -> void:
	print("GATE RPC_CLIENT_SWING | sender:", multiplayer.get_remote_sender_id(), " peer_id:", peer_id, " server:", multiplayer.is_server())
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_server_mark_swing(peer_id)


func _server_mark_swing(peer_id: int) -> void:
	print("GATE SERVER_MARK_SWING | peer_id:", peer_id, " inside_has:", _inside.has(peer_id), " done:", _done)

	if _done:
		return
	if peer_id <= 0:
		return
	if not _inside.has(peer_id):
		print("GATE SWING IGNORED (not inside) | peer_id:", peer_id)
		return

	_swung[peer_id] = true

	var count := 0
	for k in _swung.keys():
		if _swung.get(int(k), false) == true:
			count += 1

	print("GATE SWUNG COUNT:", count, " required:", required_player_count, " swung:", _swung)

	if count >= required_player_count:
		_done = true
		print("GATE COMPLETE -> PLAY + OPTIONAL LEVEL CHANGE")
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
	print("GATE RPC_PLAY_GATE_ANIM | local:", multiplayer.get_unique_id())
	_play_anim_local()


func _play_anim_local() -> void:
	print("GATE PLAY_ANIM_LOCAL | ap:", play_anim_player, " anim:", String(play_anim_name))
	if play_anim_player == null:
		return
	var a := String(play_anim_name)
	if a == "":
		return
	if play_anim_player.has_animation(a):
		play_anim_player.play(a)


func _call_level_change_level3() -> void:
	var lf := get_tree().get_first_node_in_group("level_flow_manager")
	print("GATE LEVEL CHANGE | lf:", lf)
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
