extends NPCState
class_name PatrolState

@export var arrive_dist: float = 0.6
@export var wait_at_waypoint: float = 0.0

@export var retry_autofind: bool = true
@export var retry_interval: float = 0.5
@export var retry_max_seconds: float = 6.0

@export var talk_range: Area3D

var _wps: Array[Node3D] = []
var _idx: int = 0
var _wait_t: float = 0.0
var _loop: bool = true

var _retry_t: float = 0.0
var _retry_left: float = 0.0

# -------------------------------
# ADDED: super small multiplayer sync
# - server runs the AI
# - server tells everyone what anim to play
# - server tells everyone when to change to TalkState
# -------------------------------
@export var net_sync_anim: bool = true

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""


func enter(msg := {}) -> void:
	_wps.clear()
	_idx = 0
	_wait_t = 0.0
	_loop = true

	_retry_t = 0.0
	_retry_left = retry_max_seconds

	_last_anim = &""
	_cache_anim_player()

	if npc == null:
		return

	_try_build_path()

	# ADDED: when we enter patrol, make sure everyone starts the same anim
	_play_anim_local(&"NewWalking")
	_net_broadcast_anim(&"NewWalking")


func physics_update(delta: float) -> void:
	var npc3d := npc as NPC
	if npc3d == null:
		return

	# ADDED: clients do NOT run patrol AI (server is the boss)
	# clients will still see movement if your NPC transform is already synced somewhere else
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Find and play animations for NPC models (but don't restart it every frame)
	_play_anim_local(&"NewWalking")
	_net_broadcast_anim(&"NewWalking")

	# talk interrupt (optional)
	if _is_player_in_talk_range():
		npc3d.save_patrol_resume(_idx, _wait_t)
		npc3d.velocity.x = 0.0
		npc3d.velocity.z = 0.0

		# ADDED: make everyone switch to TalkState at the same time
		_net_broadcast_state_change(&"TalkState", {})
		change_state.emit(&"TalkState", {})
		return

	# If no waypoints, retry (PCG timing)
	if _wps.size() == 0:
		if retry_autofind and _retry_left > 0.0:
			_retry_left -= delta
			_retry_t -= delta
			if _retry_t <= 0.0:
				_retry_t = retry_interval
				_try_build_path()
		return

	# wait at waypoint
	if _wait_t > 0.0:
		_wait_t -= delta
		return

	_idx = clampi(_idx, 0, _wps.size() - 1)

	# read current waypoint global position each frame
	var wp := _wps[_idx]
	if wp == null or not is_instance_valid(wp):
		_wps.clear()
		return

	var target := wp.global_position
	var look_target := target
	look_target.y -= 0.55
	npc3d.move_toward_world(target, delta)
	npc3d.look_at(look_target)

	var flat_dist := Vector3(npc3d.global_position.x, 0.0, npc3d.global_position.z) \
		.distance_to(Vector3(target.x, 0.0, target.z))

	if flat_dist <= arrive_dist:
		if wait_at_waypoint > 0.0:
			_wait_t = wait_at_waypoint
		_advance()
		return


func _try_build_path() -> void:
	var npc3d := npc as NPC
	if npc3d == null:
		return

	# NPC already bound to its own PatrolPath via patrol_path_node
	var path := npc3d.patrol_path
	if path == null or not is_instance_valid(path):
		return

	_wps = path.get_waypoint_nodes_sorted()
	_loop = path.loop

	if _wps.size() == 0:
		return

	# resume (optional)
	var resume := npc3d.consume_patrol_resume()
	if bool(resume.get("has_data", false)):
		_idx = clampi(int(resume.get("idx", 0)), 0, _wps.size() - 1)
		_wait_t = float(resume.get("wait_t", 0.0))
	else:
		_idx = _closest_index(npc3d.global_position, _wps)


func _advance() -> void:
	_idx += 1
	if _idx >= _wps.size():
		_idx = 0 if _loop else (_wps.size() - 1)


func _closest_index(pos: Vector3, wps: Array[Node3D]) -> int:
	var best_i := 0
	var best_d := INF
	for i in range(wps.size()):
		var w := wps[i]
		if w == null or not is_instance_valid(w):
			continue
		var d := pos.distance_to(w.global_position)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _is_player_in_talk_range() -> bool:
	if talk_range == null or not is_instance_valid(talk_range):
		return false
	for b in talk_range.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			return true
	return false


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
