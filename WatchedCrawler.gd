extends CharacterBody3D
class_name WatchedCrawler

# ------------------------------------------------------------
# This thing moves ONLY when the "watch rule" says it can.
# Server is the boss: it moves it + sends transforms to everyone.
# ------------------------------------------------------------

const SERVER_ID: int = 1

@export var level_flow_manager_path: NodePath = NodePath("/root/Main/LevelFlowManager")

@export var watch_max_distance: float = 35.0
@export var watch_fov_degrees: float = 28.0
@export var watch_requires_line_of_sight: bool = true

@export var move_speed: float = 2.2
@export var accel: float = 8.0
@export var stop_friction: float = 18.0

@export var obstacle_probe_dist: float = 1.1
@export var climb_boost: float = 2.5
@export var wall_slide_strength: float = 1.2
@export var ground_stick_force: float = 10.0
@export var gravity: float = 22.0

@export var net_send_rate_hz: float = 15.0
@export var net_lerp_alpha: float = 0.25

# ------------------------------------------------------------
# iteration-based scary rules
# ------------------------------------------------------------
@export var start_move_iters: float = 1.0
@export var anyone_freezes_until_iters: float = 2.0
@export var both_freeze_until_iters: float = 4.0
@export var late_move_while_watched_iters: float = 4.0
@export var required_watchers_for_freeze: int = 2
@export var watched_move_speed_mult: float = 0.25

var _lfm: Node = null
var _net_last_send_t: float = 0.0
var _net_target_xform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false
var _last_watchers: int = 0


func _enter_tree() -> void:
	# make sure the server owns this thing in multiplayer
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(SERVER_ID)


func _ready() -> void:
	_lfm = get_node_or_null(level_flow_manager_path)
	_net_target_xform = global_transform


func _physics_process(delta: float) -> void:
	# clients only interpolate what the server sends
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_net_interpolate_remote()
		return

	var iters: float = _get_iters()

	# before this, it just sits there
	if iters < start_move_iters:
		velocity = Vector3.ZERO
		move_and_slide()
		_net_maybe_broadcast()
		return

	_last_watchers = _count_watchers()
	var watched: bool = _is_being_watched(iters, _last_watchers)

	if watched and iters < late_move_while_watched_iters:
		velocity.x = move_toward(velocity.x, 0.0, stop_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stop_friction * delta)
		velocity.y = move_toward(velocity.y, 0.0, stop_friction * delta)
	else:
		var target_pos: Vector3 = _get_nearest_camera_pos()

		# late iters = it still creeps even when watched (just slower)
		var saved_speed: float = move_speed
		if watched and iters >= late_move_while_watched_iters:
			move_speed = saved_speed * watched_move_speed_mult

		_move_toward_target(delta, target_pos)
		move_speed = saved_speed

	_do_gravity_and_stick(delta)
	move_and_slide()

	_net_maybe_broadcast()


func _get_iters() -> float:
	if _lfm != null and _lfm.has_method("witness_get_iters"):
		return float(_lfm.call("witness_get_iters"))
	return float(GlobalVariables.ITERS)


func _is_being_watched(iters: float, watchers: int) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return _singleplayer_camera_watch_check()

	if not multiplayer.is_server():
		return false

	if iters < anyone_freezes_until_iters:
		return watchers >= 1

	if iters < both_freeze_until_iters:
		return watchers >= required_watchers_for_freeze

	return watchers >= 1


func _count_watchers() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 1 if _singleplayer_camera_watch_check() else 0

	if not multiplayer.is_server():
		return 0

	if _lfm == null or not _lfm.has_method("get_all_peer_camera_xforms"):
		return 0

	var cams: Array = _lfm.call("get_all_peer_camera_xforms")
	if cams.is_empty():
		return 0

	var my_pos: Vector3 = global_position
	var cos_half: float = cos(deg_to_rad(watch_fov_degrees) * 0.5)
	var count: int = 0

	for cam_xf_any in cams:
		if typeof(cam_xf_any) != TYPE_TRANSFORM3D:
			continue

		var cam_xf: Transform3D = cam_xf_any
		var cam_pos: Vector3 = cam_xf.origin
		var to_me: Vector3 = my_pos - cam_pos
		var dist: float = to_me.length()
		if dist > watch_max_distance or dist < 0.001:
			continue

		var cam_forward: Vector3 = (-cam_xf.basis.z).normalized()
		var dir_to_me: Vector3 = to_me / dist

		if cam_forward.dot(dir_to_me) < cos_half:
			continue

		if watch_requires_line_of_sight and not _has_line_of_sight(cam_pos, my_pos):
			continue

		count += 1

	return count


func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	q.exclude = [self]
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _singleplayer_camera_watch_check() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false

	var cam_pos: Vector3 = cam.global_position
	var to_me: Vector3 = global_position - cam_pos
	var dist: float = to_me.length()
	if dist > watch_max_distance or dist < 0.001:
		return false

	var cam_forward: Vector3 = (-cam.global_transform.basis.z).normalized()
	var dir_to_me: Vector3 = to_me / dist
	var cos_half: float = cos(deg_to_rad(watch_fov_degrees) * 0.5)

	if cam_forward.dot(dir_to_me) < cos_half:
		return false

	if watch_requires_line_of_sight and not _has_line_of_sight(cam_pos, global_position):
		return false

	return true


func _get_nearest_camera_pos() -> Vector3:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if _lfm != null and _lfm.has_method("get_all_peer_camera_xforms"):
			var cams: Array = _lfm.call("get_all_peer_camera_xforms")
			var best_d: float = INF
			var best_pos: Vector3 = global_position
			for cam_xf_any in cams:
				if typeof(cam_xf_any) != TYPE_TRANSFORM3D:
					continue
				var cam_xf: Transform3D = cam_xf_any
				var d: float = global_position.distance_to(cam_xf.origin)
				if d < best_d:
					best_d = d
					best_pos = cam_xf.origin
			return best_pos

	var players := get_tree().get_nodes_in_group("player")
	var best: Vector3 = global_position
	var best_d2: float = INF
	for p_any in players:
		var p := p_any as Node3D
		if p == null:
			continue
		var d2: float = global_position.distance_squared_to(p.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = p.global_position
	return best


func _move_toward_target(delta: float, target_pos: Vector3) -> void:
	var my_pos: Vector3 = global_position
	var to_target: Vector3 = (target_pos - my_pos)
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return

	var desired_dir: Vector3 = to_target.normalized()

	var space := get_world_3d().direct_space_state
	var probe_from: Vector3 = my_pos + Vector3.UP * 0.7
	var probe_to: Vector3 = probe_from + desired_dir * obstacle_probe_dist
	var q := PhysicsRayQueryParameters3D.create(probe_from, probe_to)
	q.exclude = [self]
	var hit := space.intersect_ray(q)

	if not hit.is_empty():
		var n: Vector3 = hit.get("normal", Vector3.UP)
		var slide_dir: Vector3 = desired_dir.slide(n).normalized()
		if slide_dir.length() < 0.01:
			slide_dir = desired_dir.cross(Vector3.UP).normalized()

		desired_dir = (slide_dir * wall_slide_strength + Vector3.UP * climb_boost).normalized()

	var desired_vel: Vector3 = desired_dir * move_speed
	velocity.x = move_toward(velocity.x, desired_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_vel.z, accel * delta)

	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length() > 0.1:
		look_at(global_position + flat_vel.normalized(), Vector3.UP)


func _do_gravity_and_stick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = move_toward(velocity.y, -ground_stick_force, ground_stick_force * delta)


# ------------------------------------------------------------
# Net sync (server -> everyone)
# ------------------------------------------------------------
func _net_maybe_broadcast() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / maxf(net_send_rate_hz, 1.0) # typed so godot doesn't complain
	if now - _net_last_send_t < min_interval:
		return
	_net_last_send_t = now

	# CHANGED: in Godot 4, use rpc() + mark the rpc function as "unreliable"
	rpc("_rpc_set_transform", global_transform)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_transform(t: Transform3D) -> void:
	# server doesn't apply its own packets
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return

	_net_target_xform = t
	_net_has_target = true


func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return
	global_transform = global_transform.interpolate_with(_net_target_xform, net_lerp_alpha)
