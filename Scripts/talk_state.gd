extends NPCState
class_name TalkState

@export var talk_detection: Area3D
@export var exit_delay_sec: float = 0.35

var _empty_time: float = 0.0

# tiny multiplayer sync
@export var net_sync_anim: bool = true

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""

# ADDED: optional check to avoid bouncing if no path exists
@export var stay_in_talk_if_no_path: bool = true


func enter(_msg := {}) -> void:
	_empty_time = 0.0
	_stop_npc()

	_last_anim = &""
	_cache_anim_player()

	if npc == null:
		return

	_play_anim_local(&"NewStanding")
	_net_broadcast_anim(&"NewStanding")


func physics_update(delta: float) -> void:
	_stop_npc()

	var npc3d := npc as NPC
	if npc3d == null:
		return

	# clients do NOT run talk logic (server is the boss)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_play_anim_local(&"NewStanding")
	_net_broadcast_anim(&"NewStanding")

	if talk_detection == null or not is_instance_valid(talk_detection):
		_empty_time = 0.0
		return

	var player_in_range := false
	for b in talk_detection.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			player_in_range = true
			break

	if player_in_range:
		_empty_time = 0.0
	else:
		_empty_time += delta
		if _empty_time >= exit_delay_sec:
			# ADDED: if no path exists, DON'T go back to Patrol (prevents ping-pong)
			if stay_in_talk_if_no_path and (npc3d.patrol_path == null or npc3d.patrol_path.get_waypoint_nodes_sorted().size() == 0):
				_empty_time = 0.0
				return

			_net_broadcast_state_change(&"PatrolState", {})
			change_state.emit(&"PatrolState")
			return
	
	if GlobalVariables.playerTalking == true:
		_net_broadcast_state_change(&"SpeakState", {})
		change_state.emit(&"SpeakState")
		return


func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0


func _cache_anim_player() -> void:
	_anim_player = null
	if npc == null:
		return

	var npc3d := npc as NPC
	if npc3d == null:
		return

	var model_node := find_descendant_in_group(npc3d, "NPC_Body")
	if model_node:
		_anim_player = find_descendant_in_group(model_node, "NPC_Animation") as AnimationPlayer


func _play_anim_local(anim_name: StringName) -> void:
	if _anim_player == null:
		_cache_anim_player()
	if _anim_player == null:
		return

	if _last_anim == anim_name and _anim_player.is_playing():
		return

	_last_anim = anim_name
	_anim_player.play(String(anim_name))


func _net_broadcast_anim(anim_name: StringName) -> void:
	if not net_sync_anim:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	if _last_anim != anim_name:
		return

	rpc("_rpc_play_anim", String(anim_name))


@rpc("any_peer", "call_local", "unreliable")
func _rpc_play_anim(anim_name: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	_play_anim_local(StringName(anim_name))


func _net_broadcast_state_change(state_name: StringName, msg: Dictionary) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	rpc("_rpc_force_state", String(state_name), msg)


@rpc("any_peer", "call_local", "reliable")
func _rpc_force_state(state_name: String, msg: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	change_state.emit(StringName(state_name), msg)


func find_descendant_in_group(node: Node, group: String) -> Node:
	if node.is_in_group(group):
		return node

	for child in node.get_children():
		var result = find_descendant_in_group(child, group)
		if result:
			return result

	return null
