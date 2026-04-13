extends CharacterBody3D
class_name WatchedCrawler

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
# iteration-based rules
# ------------------------------------------------------------
@export var start_move_iters: float = 1.0
@export var both_watch_required_iters: float = 4.0
@export var required_watchers_for_freeze: int = 2

@export var late_move_while_watched_iters: float = 9999.0
@export var watched_move_speed_mult: float = 0.25

@export var vanish_enabled: bool = false
@export var vanish_radius: float = 8.0
@export var vanish_delay_sec: float = 0.4

@export var debug_print: bool = true

var _lfm: Node = null
var _net_last_send_t: float = 0.0
var _net_target_xform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false

var _last_watchers: int = 0
var _vanish_t: float = 0.0


func _enter_tree() -> void:
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(SERVER_ID)


func _ready() -> void:
	_lfm = get_node_or_null(level_flow_manager_path)
	_net_target_xform = global_transform


func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_net_interpolate_remote()
		return

	var iters: float = _get_iters()

	if iters < start_move_iters:
		velocity = Vector3.ZERO
		move_and_slide()
		_net_maybe_broadcast()
		return

	_last_watchers = _count_watchers()
	var watched: bool = _should_freeze(iters, _last_watchers)

	if debug_print:
		print("[Crawler] iters=", iters, " watchers=", _last_watchers, " watched=", watched)

	if vanish_enabled:
		_update_vanish(delta, watched)
		if not is_inside_tree():
			return

	if watched and iters < late_move_while_watched_iters:
		velocity.x = move_toward(velocity.x, 0.0, stop_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stop_friction * delta)
		velocity.y = move_toward(velocity.y, 0.0, stop_friction * delta)
	else:
		var target_pos: Vector3 = _get_nearest_target_pos()

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

	# your real global seems to be GlobalVariables.iterations
	if "iterations" in GlobalVariables:
		return float(GlobalVariables.iterations)

	if "ITERS" in GlobalVariables:
		return float(GlobalVariables.ITERS)

	return 0.0


func _should_freeze(iters: float, watchers: int) -> bool:
	# If you are NOT in multiplayer, one watcher = freeze
	if not multiplayer.has_multiplayer_peer():
		return watchers >= 1

	# In multiplayer, server decides
	if not multiplayer.is_server():
		return false

	# early: any watcher freezes
	if iters < both_watch_required_iters:
		return watchers >= 1

	# later: requires both (or required_watchers_for_freeze)
	return watchers >= required_watchers_for_freeze


func _count_watchers() -> int:
	# true singleplayer
	if not multiplayer.has_multiplayer_peer():
		return 1 if _singleplayer_camera_watch_check() else 0

	# multiplayer but CLIENT: server decides
	if not multiplayer.is_server():
		return 0

	# MULTIPLAYER SERVER PATH:
	# If LFM missing/broken/empty, FALL BACK to local camera watch check
	if _lfm == null or not _lfm.has_method("get_all_peer_camera_xforms"):
		return 1 if _singleplayer_camera_watch_check() else 0

	var cams: Array = _lfm.call("get_all_peer_camera_xforms")
	if cams.is_empty():
		# THIS IS THE IMPORTANT FIX for “hosting alone” / LFM not populated yet
		return 1 if _singleplayer_camera_watch_check() else 0

	var my_pos: Vector3 = global_position + Vector3.UP * 0.8
	var cos_half: float = cos(deg_to_rad(watch_fov_degrees) * 0.5)
	var count: int = 0

	for cam_xf_any in cams:
		if typeof(cam_xf_any) != TYPE_TRANSFORM3D:
			continue

		var cam_xf: Transform3D = cam_xf_any as Transform3D
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


func _los_exclude_list() -> Array:
	var out: Array = [self]
	var players: Array = get_tree().get_nodes_in_group("player")
	for p_any in players:
		var p := p_any as Node
		if p != null:
			out.append(p)
	return out


func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	q.exclude = _los_exclude_list()
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _singleplayer_camera_watch_check() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		# fallback: try finding player camera
		var players: Array = get_tree().get_nodes_in_group("player")
		for p_any in players:
			var p := p_any as Node
			if p == null:
				continue
			if p.has_node("Head/Camera3D"):
				cam = p.get_node("Head/Camera3D") as Camera3D
				break
			if p.has_node("Camera3D"):
				cam = p.get_node("Camera3D") as Camera3D
				break
			var found := p.find_child("Camera3D", true, false) as Camera3D
			if found != null:
				cam = found
				break

	if cam == null:
		if debug_print:
			print("[Crawler] no camera found for watch check")
		return false

	var cam_pos: Vector3 = cam.global_position
	var my_pos: Vector3 = global_position + Vector3.UP * 0.8
	var to_me: Vector3 = my_pos - cam_pos
	var dist: float = to_me.length()
	if dist > watch_max_distance or dist < 0.001:
		return false

	var cam_forward: Vector3 = (-cam.global_transform.basis.z).normalized()
	var dir_to_me: Vector3 = to_me / dist
	var cos_half: float = cos(deg_to_rad(watch_fov_degrees) * 0.5)

	if cam_forward.dot(dir_to_me) < cos_half:
		return false

	if watch_requires_line_of_sight and not _has_line_of_sight(cam_pos, my_pos):
		return false

	return true


func _get_nearest_target_pos() -> Vector3:
	# multiplayer server: chase nearest camera xform if available
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if _lfm != null and _lfm.has_method("get_all_peer_camera_xforms"):
			var cams: Array = _lfm.call("get_all_peer_camera_xforms")
			if not cams.is_empty():
				var best_d2: float = INF
				var best: Vector3 = global_position
				for cam_xf_any in cams:
					if typeof(cam_xf_any) != TYPE_TRANSFORM3D:
						continue
					var cam_xf: Transform3D = cam_xf_any as Transform3D
					var d2: float = global_position.distance_squared_to(cam_xf.origin)
					if d2 < best_d2:
						best_d2 = d2
						best = cam_xf.origin
				return best

	# fallback: chase viewport camera
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position

	# last fallback: player group
	var players: Array = get_tree().get_nodes_in_group("player")
	var best2: Vector3 = global_position
	var best_d2b: float = INF
	for p_any in players:
		var p := p_any as Node3D
		if p == null:
			continue
		var d2b: float = global_position.distance_squared_to(p.global_position)
		if d2b < best_d2b:
			best_d2b = d2b
			best2 = p.global_position
	return best2


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


func _update_vanish(delta: float, watched: bool) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var in_radius: int = _count_players_in_radius(vanish_radius)
	if in_radius >= required_watchers_for_freeze and not watched and _last_watchers == 0:
		_vanish_t += delta
		if _vanish_t >= vanish_delay_sec:
			queue_free()
	else:
		_vanish_t = 0.0


func _count_players_in_radius(r: float) -> int:
	var r2: float = r * r
	var count: int = 0

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if _lfm != null and _lfm.has_method("get_all_peer_camera_xforms"):
			var cams: Array = _lfm.call("get_all_peer_camera_xforms")
			if not cams.is_empty():
				for cam_xf_any in cams:
					if typeof(cam_xf_any) != TYPE_TRANSFORM3D:
						continue
					var cam_xf: Transform3D = cam_xf_any as Transform3D
					if global_position.distance_squared_to(cam_xf.origin) <= r2:
						count += 1
				return count

	# fallback: viewport camera
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and global_position.distance_squared_to(cam.global_position) <= r2:
		return 1

	# fallback: player group
	var players: Array = get_tree().get_nodes_in_group("player")
	for p_any in players:
		var p := p_any as Node3D
		if p == null:
			continue
		if global_position.distance_squared_to(p.global_position) <= r2:
			count += 1
	return count


func _net_maybe_broadcast() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / maxf(net_send_rate_hz, 1.0)
	if now - _net_last_send_t < min_interval:
		return
	_net_last_send_t = now

	rpc("_rpc_set_transform", global_transform)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_transform(t: Transform3D) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	_net_target_xform = t
	_net_has_target = true


func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return
	global_transform = global_transform.interpolate_with(_net_target_xform, net_lerp_alpha)
