extends NPCState
class_name SpeakState

@export var talk_detection: Area3D

var _empty_time: float = 0.0

# -------------------------------
# ADDED: tiny multiplayer sync
# - server runs SpeakState logic
# - clients just apply anim + look direction
# -------------------------------
@export var net_sync_enabled: bool = true

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""

# ADDED: clients will apply this look target when server sends it
var _net_look_target: Vector3 = Vector3.ZERO
var _net_has_look_target: bool = false


func enter(_msg := {}) -> void:
	_empty_time = 0.0
	_stop_npc()
	_last_anim = &""
	_cache_anim_player()

	if npc == null:
		return

	# ADDED: when we enter, make sure everyone starts the talking anim
	_play_anim_local(&"NewTalking")
	_net_broadcast_anim(&"NewTalking")


func physics_update(delta: float) -> void:
	_stop_npc()

	var npc3d := npc as NPC
	if npc3d == null:
		return

	# ADDED: clients don't run the logic, they just apply what the server sends
	if _is_net_client():
		_apply_net_anim()
		_apply_net_look(npc3d)
		return

	# ------------------------------------------------
	# SERVER / SINGLEPLAYER: normal SpeakState behavior
	# ------------------------------------------------

	# play talking anim while playerTalking is true
	if GlobalVariables.playerTalking == true:
		_play_anim_local(&"NewTalking")
		_net_broadcast_anim(&"NewTalking")
	else:
		# ADDED: make the state change match for everyone
		_net_broadcast_state_change(&"TalkState", {})
		change_state.emit(&"TalkState")
		return

	# look at a player in the talk area (first one we find)
	if talk_detection != null and is_instance_valid(talk_detection):
		for b in talk_detection.get_overlapping_bodies():
			if b != null and b.is_in_group("player"):
				var target := b.global_position
				var look_target := target
				look_target.y += 1.5
				npc3d.look_at(look_target)

				# ADDED: send look target so clients see the same facing direction
				_net_broadcast_look_target(look_target)
				break


func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0


# -------------------------------
# ADDED: animation helpers (cache once, don't restart every frame)
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

	if _last_anim == anim_name and _anim_player.is_playing():
		return

	_last_anim = anim_name
	_anim_player.play(String(anim_name))


func _apply_net_anim() -> void:
	if _last_anim == &"":
		return
	_play_anim_local(_last_anim)


# -------------------------------
# ADDED: multiplayer helpers
# -------------------------------
func _is_net_client() -> bool:
	if not net_sync_enabled:
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	return not multiplayer.is_server()


func _net_broadcast_anim(anim_name: StringName) -> void:
	if not net_sync_enabled:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	# only send the anim name (super small)
	rpc("_rpc_play_anim", String(anim_name))


@rpc("any_peer", "call_local", "unreliable")
func _rpc_play_anim(anim_name: String) -> void:
	# server ignores its own packet
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	_last_anim = StringName(anim_name)
	_play_anim_local(_last_anim)


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
	# server already did it locally
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	change_state.emit(StringName(state_name), msg)


# ADDED: sync NPC look direction during talking (optional but makes it feel "the same")
func _net_broadcast_look_target(look_target: Vector3) -> void:
	if not net_sync_enabled:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	# FIXED: Godot 4 uses rpc() + @rpc(... "unreliable")
	rpc("_rpc_set_look_target", look_target)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_look_target(look_target: Vector3) -> void:
	# server ignores its own packet
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	_net_look_target = look_target
	_net_has_look_target = true


func _apply_net_look(npc3d: NPC) -> void:
	if not _net_has_look_target:
		return
	npc3d.look_at(_net_look_target)


# For finding nodes within nodes using groups
func find_descendant_in_group(node: Node, group: String) -> Node:
	if node.is_in_group(group):
		return node

	for child in node.get_children():
		var result = find_descendant_in_group(child, group)
		if result:
			return result

	return null
