extends NPCState
class_name TalkState

@export var talk_detection: Area3D
@export var exit_delay_sec: float = 0.35

var _empty_time: float = 0.0

# -------------------------------
# ADDED: tiny multiplayer sync (same idea as PatrolState)
# -------------------------------
@export var net_sync_anim: bool = true

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""


func enter(_msg := {}) -> void:
	_empty_time = 0.0
	_stop_npc()

	_last_anim = &""
	_cache_anim_player()

	if npc == null:
		return

	# ADDED: when we enter talk, make sure everyone is standing
	_play_anim_local(&"NewStanding")
	_net_broadcast_anim(&"NewStanding")


func physics_update(delta: float) -> void:
	_stop_npc()

	var npc3d := npc as NPC
	if npc3d == null:
		return

	# ADDED: clients do NOT run talk logic (server is the boss)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Find and play animations for NPC models (but don't restart every frame)
	_play_anim_local(&"NewStanding")
	_net_broadcast_anim(&"NewStanding")

	# If the area isn't set, just "stay talking" (prevents ping-pong).
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
			# ADDED: force everyone back to PatrolState at the same time
			_net_broadcast_state_change(&"PatrolState", {})
			change_state.emit(&"PatrolState")
			return

	# Your global trigger (keep it server-authoritative so everyone matches)
	if GlobalVariables.playerTalking == true:
		_net_broadcast_state_change(&"SpeakState", {})
		change_state.emit(&"SpeakState")
		return


func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0


# -------------------------------
# ADDED: animation helpers (so we don't search every frame)
# -------------------------------
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

	# don't spam play() every frame (it restarts the anim)
	if _last_anim == anim_name and _anim_player.is_playing():
		return

	_last_anim = anim_name
	_anim_player.play(String(anim_name))


# -------------------------------
# ADDED: tiny net sync for animation + state changes
# -------------------------------
func _net_broadcast_anim(anim_name: StringName) -> void:
	if not net_sync_anim:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	# only send when it changes
	if _last_anim != anim_name:
		return

	rpc("_rpc_play_anim", String(anim_name))


@rpc("any_peer", "call_local", "unreliable")
func _rpc_play_anim(anim_name: String) -> void:
	# server doesn't need its own packet
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
	# server already did it locally
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
