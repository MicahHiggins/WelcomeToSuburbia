# res://UVFlashlight.gd
extends CharacterBody3D
class_name UVFlashlight

@onready var interact_area: Area3D = $Area3D
@onready var uv_light: SpotLight3D = $SpotLight3D

@export var uv_cast_path: NodePath = NodePath("ShapeCast3D")
var uv_cast: ShapeCast3D = null

@export var outline_mesh_path: NodePath
var outline_mesh: MeshInstance3D = null

@export var authority_only_physics: bool = true

@export var enable_drop_physics: bool = true
@export var ground_friction: float = 5.0
@export var air_gravity_mult: float = 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var uv_range_m: float = 10.0
@export var reveal_radius_m: float = 1.75
@export var reveal_max_targets_per_frame: int = 12

@export var toggle_action: StringName = &"toggle_flashlight"
@export var replicate_light_toggle: bool = true

# -------------------------
# BRIGHTNESS / VISUAL BOOST
# (PATCH: keep ORIGINAL beam width; only boost brightness + range a bit)
# -------------------------
@export var beam_brightness_multiplier: float = 8.0
@export var beam_energy_on: float = 40.0
@export var beam_range_on: float = 18.0
# NOTE: we do NOT override spot_angle / attenuation so beam width stays like the scene.

# -------------------------
# PATCH: BEAM-VOLUME REVEAL (works even up-close / looking up)
# -------------------------
@export var reveal_use_beam_volume: bool = true
@export var beam_radius_near_m: float = 0.20
@export var beam_radius_growth_per_m: float = 0.06
@export var beam_extra_slop_m: float = 0.12
@export var beam_require_in_front: bool = true

var _held: bool = false
var _hovered: bool = false
var _uv_on: bool = false

var _revealed_this_frame: Dictionary = {}
var _previous_reveals: Array[UvRevealTarget] = []

const SERVER_ID: int = 1

# reveal replication (owner broadcasts which targets are being hit)
@export var replicate_reveal: bool = true
@export var reveal_send_rate_hz: float = 20.0
var _reveal_last_send_time: float = 0.0
var _net_prev_reveals: Dictionary = {} # String(path) -> bool

# replicate flashlight aim (rotation) so all peers see same beam direction
@export var replicate_aim: bool = true
@export var aim_send_rate_hz: float = 20.0
@export var aim_lerp_alpha: float = 0.35

var _aim_last_send_time: float = 0.0
var _aim_target_q: Quaternion = Quaternion.IDENTITY
var _aim_has_target: bool = false

# replicate dropped motion so the joiner sees it fall too
@export var replicate_drop_motion: bool = true
@export var drop_send_rate_hz: float = 20.0
@export var drop_lerp_alpha: float = 0.25

var _drop_last_send_time: float = 0.0
var _drop_target_pos: Vector3 = Vector3.ZERO
var _drop_target_q: Quaternion = Quaternion.IDENTITY
var _drop_has_target: bool = false

# remember how big the flashlight is supposed to be (prevents "huge flashlight" bugs)
var _base_scale: Vector3 = Vector3.ONE

# PATCH: when equipping after a level restart, clear stale net targets so it doesn't "lock" wrong.
var _just_equipped_reset: bool = false

# cache original light parameters so we can safely boost/restore
var _light_base_energy: float = 1.0
var _light_base_range: float = 10.0
var _light_base_spot_angle: float = 45.0
var _light_base_spot_atten: float = 1.0


func _ready() -> void:
	add_to_group("pickup")

	# cache intended scale from the scene file
	_base_scale = scale

	if outline_mesh_path != NodePath(""):
		outline_mesh = get_node_or_null(outline_mesh_path) as MeshInstance3D
		if outline_mesh != null:
			outline_mesh.visible = false

	if interact_area != null:
		interact_area.set_collision_layer_value(4, true)
		interact_area.collision_mask = 0

	uv_cast = get_node_or_null(uv_cast_path) as ShapeCast3D
	if uv_cast == null:
		push_error("[UVFlashlight] ShapeCast3D not found. Set uv_cast_path to your ShapeCast3D node.")
	else:
		uv_cast.enabled = false
		uv_cast.target_position = Vector3(0, 0, -uv_range_m)

	if uv_light != null:
		# cache base (SpotLight3D only)
		_light_base_energy = uv_light.light_energy
		_light_base_range = uv_light.spot_range
		_light_base_spot_angle = uv_light.spot_angle
		_light_base_spot_atten = uv_light.spot_attenuation

		uv_light.visible = false
		_apply_light_visuals(false)

	_reset_net_targets_to_current()


func set_hovered(v: bool) -> void:
	_hovered = v
	if outline_mesh != null and not _held:
		outline_mesh.visible = v


func set_held(v: bool) -> void:
	_held = v
	if outline_mesh != null:
		outline_mesh.visible = false

	if v:
		_reset_net_targets_to_current()
		_just_equipped_reset = true
		_drop_has_target = false
	else:
		_set_uv_on(false)
		_reset_drop_targets_to_current()


func _unhandled_input(event: InputEvent) -> void:
	# only allow the flashlight owner to toggle it
	if not _held or not is_multiplayer_authority():
		return
	if event.is_action_pressed(String(toggle_action)):
		_set_uv_on(not _uv_on)


func _process(_delta: float) -> void:
	# SINGLEPLAYER: local reveal is fine
	if not multiplayer.has_multiplayer_peer():
		_process_reveal_local()
		return

	# MULTIPLAYER:
	# only the flashlight authority computes reveal and broadcasts it
	if replicate_reveal and is_multiplayer_authority():
		_process_reveal_local()
		_net_maybe_send_reveals()
	else:
		_revealed_this_frame.clear()
		_clear_previous_reveals()

	# aim replication tick (rotation)
	if replicate_aim and _held:
		if is_multiplayer_authority():
			_net_maybe_send_aim()
		else:
			_net_interpolate_remote_aim()

	# dropped motion replication (clients lerp to server)
	if replicate_drop_motion and not multiplayer.is_server() and not _held:
		_net_interpolate_remote_drop()


func _process_reveal_local() -> void:
	if not _held or not _uv_on:
		_revealed_this_frame.clear()
		_clear_previous_reveals()
		return

	if uv_cast != null:
		uv_cast.enabled = true
		uv_cast.target_position = Vector3(0, 0, -uv_range_m)
		uv_cast.force_shapecast_update()

	_revealed_this_frame.clear()
	_reveal_in_beam()
	_clear_previous_reveals()


func _physics_process(delta: float) -> void:
	if not enable_drop_physics:
		return

	if _held:
		velocity = Vector3.ZERO
		return

	var has_peer: bool = multiplayer.has_multiplayer_peer()
	if authority_only_physics and has_peer:
		if is_multiplayer_authority():
			_do_drop_physics(delta)
		return

	_do_drop_physics(delta)


func _do_drop_physics(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * air_gravity_mult * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)

	move_and_slide()

	if replicate_drop_motion and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not _held:
		_net_maybe_send_drop()


# =========================
#   REVEAL LOGIC (PATCHED)
# =========================
func _reveal_in_beam() -> void:
	if reveal_use_beam_volume:
		_reveal_in_beam_volume()
		return

	# fallback: your old point-hit radius logic
	var hit_pos: Vector3 = _find_uv_hit_point()

	var targets: Array = get_tree().get_nodes_in_group("uv_reveal")
	var count: int = 0

	for t_any in targets:
		if count >= reveal_max_targets_per_frame:
			break

		var rt: UvRevealTarget = t_any as UvRevealTarget
		if rt == null or not is_instance_valid(rt):
			continue

		var d: float = rt.global_position.distance_to(hit_pos)
		if d <= reveal_radius_m:
			rt.set_reveal(true)
			_revealed_this_frame[rt] = true
			count += 1

	_previous_reveals = _previous_reveals.filter(func(x): return x != null and is_instance_valid(x))
	for k_any in _revealed_this_frame.keys():
		var rr: UvRevealTarget = k_any as UvRevealTarget
		if rr != null and _previous_reveals.find(rr) == -1:
			_previous_reveals.append(rr)


func _reveal_in_beam_volume() -> void:
	var origin: Vector3 = global_transform.origin
	var dir: Vector3 = (-global_transform.basis.z).normalized()

	var targets: Array = get_tree().get_nodes_in_group("uv_reveal")
	var count: int = 0

	for t_any in targets:
		if count >= reveal_max_targets_per_frame:
			break

		var rt: UvRevealTarget = t_any as UvRevealTarget
		if rt == null or not is_instance_valid(rt):
			continue

		var p: Vector3 = rt.global_position

		if beam_require_in_front:
			if (p - origin).dot(dir) < 0.0:
				continue

		var cp: Dictionary = _closest_point_on_ray(origin, dir, p)
		var t: float = float(cp["t"])
		if t > uv_range_m:
			continue

		var closest: Vector3 = cp["p"] as Vector3
		var lateral: float = p.distance_to(closest)

		var beam_r: float = _beam_radius_at_distance(t)
		var effective_r: float = maxf(beam_r, reveal_radius_m)

		if lateral <= effective_r:
			rt.set_reveal(true)
			_revealed_this_frame[rt] = true
			count += 1

	_previous_reveals = _previous_reveals.filter(func(x): return x != null and is_instance_valid(x))
	for k_any in _revealed_this_frame.keys():
		var rr: UvRevealTarget = k_any as UvRevealTarget
		if rr != null and _previous_reveals.find(rr) == -1:
			_previous_reveals.append(rr)


func _closest_point_on_ray(origin: Vector3, dir: Vector3, point: Vector3) -> Dictionary:
	# dir must be normalized
	var v: Vector3 = point - origin
	var t: float = v.dot(dir)
	if t < 0.0:
		t = 0.0
	return {"t": t, "p": origin + dir * t}


func _beam_radius_at_distance(t: float) -> float:
	return beam_radius_near_m + beam_radius_growth_per_m * t + beam_extra_slop_m


func _find_uv_hit_point() -> Vector3:
	var origin: Vector3 = global_transform.origin
	var forward: Vector3 = (-global_transform.basis.z).normalized()
	var fallback_hit: Vector3 = origin + forward * uv_range_m

	# 1) ShapeCast: find CLOSEST valid uv_reveal collider
	if uv_cast != null and uv_cast.is_colliding():
		var best_d: float = INF
		var best_p: Vector3 = Vector3.ZERO
		var found: bool = false

		for i: int in range(uv_cast.get_collision_count()):
			var col_obj: Object = uv_cast.get_collider(i)
			var col_node: Node = col_obj as Node
			if col_node == null:
				continue

			var ok: bool = col_node.is_in_group("uv_reveal") \
				or (col_node.get_parent() != null and col_node.get_parent().is_in_group("uv_reveal"))
			if not ok:
				continue

			var p: Vector3 = uv_cast.get_collision_point(i)
			var d: float = origin.distance_to(p)
			if d < best_d:
				best_d = d
				best_p = p
				found = true

		if found:
			return best_p

	# 2) Raycast fallback
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, fallback_hit)
	q.exclude = [self]
	var hit: Dictionary = space.intersect_ray(q)

	if not hit.is_empty():
		var col_obj2: Object = hit.get("collider")
		var col_node2: Node = col_obj2 as Node
		if col_node2 != null:
			var ok2: bool = col_node2.is_in_group("uv_reveal") \
				or (col_node2.get_parent() != null and col_node2.get_parent().is_in_group("uv_reveal"))
			if ok2:
				var pos_any: Variant = hit.get("position")
				if typeof(pos_any) == TYPE_VECTOR3:
					return pos_any as Vector3

	return fallback_hit


func _clear_previous_reveals() -> void:
	for rt_any in _previous_reveals:
		var rt: UvRevealTarget = rt_any as UvRevealTarget
		if rt == null or not is_instance_valid(rt):
			continue
		if not _revealed_this_frame.has(rt):
			rt.set_reveal(false)


# =========================
#   LIGHT VISUALS (PATCHED)
# =========================
func _apply_light_visuals(on: bool) -> void:
	if uv_light == null:
		return

	if on:
		# keep original width/shape; only boost energy (+ a bit of range)
		uv_light.light_energy = maxf(_light_base_energy * beam_brightness_multiplier, beam_energy_on)
		uv_light.spot_range = maxf(_light_base_range, beam_range_on)
		uv_light.spot_angle = _light_base_spot_angle
		uv_light.spot_attenuation = _light_base_spot_atten
	else:
		uv_light.light_energy = _light_base_energy
		uv_light.spot_range = _light_base_range
		uv_light.spot_angle = _light_base_spot_angle
		uv_light.spot_attenuation = _light_base_spot_atten


func _set_uv_on(v: bool) -> void:
	_uv_on = v

	if uv_light != null:
		uv_light.visible = v
	_apply_light_visuals(v)

	if uv_cast != null:
		uv_cast.enabled = v

	if replicate_light_toggle and multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		var mp: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		rpc("_rpc_set_uv_visible", v)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_uv_visible(v: bool) -> void:
	if uv_light != null:
		uv_light.visible = v
	_apply_light_visuals(v)


# =========================
#   NET REVEAL REPLICATION
# =========================
func _net_maybe_send_reveals() -> void:
	if not replicate_reveal:
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(reveal_send_rate_hz, 1.0)
	if now - _reveal_last_send_time < min_interval:
		return
	_reveal_last_send_time = now

	var paths: Array[String] = []
	for k_any in _revealed_this_frame.keys():
		var rt: UvRevealTarget = k_any as UvRevealTarget
		if rt != null and is_instance_valid(rt):
			paths.append(String(rt.get_path()))

	rpc("_rpc_apply_reveals", paths)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_apply_reveals(paths: Array[String]) -> void:
	var seen: Dictionary = {}
	for pstr in paths:
		seen[pstr] = true
		var n: Node = get_node_or_null(NodePath(pstr))
		var rt: UvRevealTarget = n as UvRevealTarget
		if rt != null and is_instance_valid(rt):
			rt.set_reveal(true)

	for old_key_any in _net_prev_reveals.keys():
		var kstr: String = String(old_key_any)
		if not seen.has(kstr):
			var n2: Node = get_node_or_null(NodePath(kstr))
			var rt2: UvRevealTarget = n2 as UvRevealTarget
			if rt2 != null and is_instance_valid(rt2):
				rt2.set_reveal(false)

	_net_prev_reveals = seen


# =========================
#   AIM REPLICATION (QUAT)
# =========================
func _net_maybe_send_aim() -> void:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(aim_send_rate_hz, 1.0)
	if now - _aim_last_send_time < min_interval:
		return

	_aim_last_send_time = now

	var q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	rpc("_rpc_set_aim_quat", q)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_aim_quat(q: Quaternion) -> void:
	if is_multiplayer_authority():
		return
	_aim_target_q = q
	_aim_has_target = true


func _net_interpolate_remote_aim() -> void:
	if _just_equipped_reset:
		_just_equipped_reset = false
		return

	if not _aim_has_target:
		return

	var cur_q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	var new_q: Quaternion = cur_q.slerp(_aim_target_q, aim_lerp_alpha)

	var b: Basis = Basis(new_q).scaled(_base_scale)
	global_transform = Transform3D(b, global_position)


# =========================
#   DROP REPLICATION (POS + QUAT)
# =========================
func _net_maybe_send_drop() -> void:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(drop_send_rate_hz, 1.0)
	if now - _drop_last_send_time < min_interval:
		return
	_drop_last_send_time = now

	var q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	rpc("_rpc_set_drop_state", global_position, q)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_drop_state(pos: Vector3, q: Quaternion) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return

	_drop_target_pos = pos
	_drop_target_q = q
	_drop_has_target = true


func _net_interpolate_remote_drop() -> void:
	if not _drop_has_target:
		return

	var pos: Vector3 = global_position.lerp(_drop_target_pos, drop_lerp_alpha)
	var cur_q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	var new_q: Quaternion = cur_q.slerp(_drop_target_q, drop_lerp_alpha)

	var b: Basis = Basis(new_q).scaled(_base_scale)
	global_transform = Transform3D(b, pos)


# =========================
#   PATCH HELPERS
# =========================
func _reset_net_targets_to_current() -> void:
	_aim_target_q = global_transform.basis.orthonormalized().get_rotation_quaternion()
	_aim_has_target = false
	_aim_last_send_time = 0.0

	_reveal_last_send_time = 0.0
	_net_prev_reveals.clear()
	_revealed_this_frame.clear()
	_previous_reveals.clear()

	_reset_drop_targets_to_current()


func _reset_drop_targets_to_current() -> void:
	_drop_target_pos = global_position
	_drop_target_q = global_transform.basis.orthonormalized().get_rotation_quaternion()
	_drop_has_target = false
	_drop_last_send_time = 0.0
