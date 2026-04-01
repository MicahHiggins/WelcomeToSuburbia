extends NPCState
class_name SpeakState

const SERVER_ID: int = 1

@export var talk_detection: Area3D

# ADDED: keep it simple — server runs, clients mirror
@export var net_sync_enabled: bool = true

var _speaker_peer_id: int = -1

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""

var _net_look_target: Vector3 = Vector3.ZERO
var _net_has_look_target: bool = false


func enter(msg := {}) -> void:
	_stop_npc()
	_last_anim = &""

	# ADDED: remember who started the conversation
	_speaker_peer_id = int(msg.get("speaker", -1))

	_cache_anim_player()

	# ADDED: when we enter SpeakState, we just play the talking anim
	_play_anim_local(&"NewTalking")
	_net_broadcast_anim(&"NewTalking")


func physics_update(delta: float) -> void:
	_stop_npc()

	var npc3d := npc as NPC
	if npc3d == null:
		return

	# ADDED: clients don’t decide anything — they only apply what server sends
	if _is_net_client():
		_apply_net_anim()
		_apply_net_look(npc3d)
		return

	# SERVER / SINGLEPLAYER:
	_play_anim_local(&"NewTalking")
	_net_broadcast_anim(&"NewTalking")

	# If talk_detection isn't set, we can't aim at anyone
	if talk_detection == null or not is_instance_valid(talk_detection):
		return

	# ADDED: pick the "speaker" player first
	var chosen: Node3D = null

	if _speaker_peer_id != -1:
		for b in talk_detection.get_overlapping_bodies():
			var p := b as Node3D
			if p != null and p.is_in_group("player"):
				if int(p.get_multiplayer_authority()) == _speaker_peer_id:
					chosen = p
					break

	# fallback: if we couldn't find them, just pick the closest player in the area
	if chosen == null:
		var best_d := INF
		for b in talk_detection.get_overlapping_bodies():
			var p2 := b as Node3D
			if p2 != null and p2.is_in_group("player"):
				var d := npc3d.global_position.distance_to(p2.global_position)
				if d < best_d:
					best_d = d
					chosen = p2

	if chosen != null:
		var target := chosen.global_position
		var look_target := target
		look_target.y += 1.5
		npc3d.look_at(look_target)
		_net_broadcast_look_target(look_target)


func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0


# -------------------------------
# animation helpers
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
# multiplayer helpers
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

	rpc("_rpc_play_anim", String(anim_name))


@rpc("any_peer", "call_local", "unreliable")
func _rpc_play_anim(anim_name: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	_last_anim = StringName(anim_name)
	_play_anim_local(_last_anim)


func _net_broadcast_look_target(look_target: Vector3) -> void:
	if not net_sync_enabled:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	rpc("_rpc_set_look_target", look_target)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_look_target(look_target: Vector3) -> void:
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
