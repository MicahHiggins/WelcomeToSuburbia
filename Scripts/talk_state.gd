extends NPCState
class_name TalkState

const SERVER_ID: int = 1 # host is peer 1

@export var talk_detection: Area3D
@export var exit_delay_sec: float = 0.35

# ADDED: turn this on so server controls the state for multiplayer
@export var net_sync_enabled: bool = true

var _empty_time: float = 0.0


func enter(_msg := {}) -> void:
	_empty_time = 0.0
	_stop_npc()

	if npc == null:
		return


func physics_update(delta: float) -> void:
	_stop_npc()

	var npc3d := npc as NPC
	if npc3d == null:
		return

	# Find and play animations for NPC models
	var model_node = find_descendant_in_group(npc3d, "NPC_Body")
	if model_node:
		var anim_player = find_descendant_in_group(model_node, "NPC_Animation")
		if anim_player:
			anim_player.play("NewStanding")

	# If the area isn't set, just stay talking
	if talk_detection == null or not is_instance_valid(talk_detection):
		_empty_time = 0.0
		return

	# Check if ANY player is still inside the area
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
			# ADDED: server tells everyone to go back to PatrolState
			_net_broadcast_state_change(&"PatrolState", {})
			change_state.emit(&"PatrolState")

	# -----------------------------------------
	# ADDED: this is the important multiplayer fix
	# - clients can't just flip SpeakState locally
	# - they ask the server to do it
	# -----------------------------------------
	if GlobalVariables.playerTalking == true:
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			rpc_id(SERVER_ID, "_rpc_request_speak", multiplayer.get_unique_id())
			return

		# server/singleplayer can switch directly
		_net_broadcast_state_change(&"SpeakState", {"speaker": multiplayer.get_unique_id()})
		change_state.emit(&"SpeakState", {"speaker": multiplayer.get_unique_id()})


func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0


# ADDED: client -> server “I started talking”
@rpc("any_peer", "reliable")
func _rpc_request_speak(speaker_peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# server forces the SpeakState for everyone, and tags who started it
	_net_broadcast_state_change(&"SpeakState", {"speaker": speaker_peer_id})
	change_state.emit(&"SpeakState", {"speaker": speaker_peer_id})


# ADDED: tiny helper so state switches match on all peers
func _net_broadcast_state_change(state_name: StringName, msg: Dictionary) -> void:
	if not net_sync_enabled:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	rpc("_rpc_force_state", String(state_name), msg)


@rpc("any_peer", "call_local", "reliable")
func _rpc_force_state(state_name: String, msg: Dictionary) -> void:
	# server already changed locally
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	change_state.emit(StringName(state_name), msg)


# For finding nodes within nodes using groups
func find_descendant_in_group(node: Node, group: String) -> Node:
	if node.is_in_group(group):
		return node

	for child in node.get_children():
		var result = find_descendant_in_group(child, group)
		if result:
			return result

	return null
