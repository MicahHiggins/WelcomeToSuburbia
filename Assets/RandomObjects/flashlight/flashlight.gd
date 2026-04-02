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
		uv_light.visible = false

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
		# PATCH: equip = clear stale interpolation targets (restart-safe)
		_reset_net_targets_to_current()
		_just_equipped_reset = true

		# When held, the drop interpolation should not keep pulling us around on clients
		_drop_has_target = false
	else:
		_set_uv_on(false)
		# if dropped, we start drop targets from where we are now
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

	var has_peer := multiplayer.has_multiplayer_peer()
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

	# server streams dropped motion so everyone sees it fall
	if replicate_drop_motion and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not _held:
		_net_maybe_send_drop()


func _reveal_in_beam() -> void:
	var origin := global_transform.origin
	var forward := (-global_transform.basis.z).normalized()

	# default hit = straight ahead max range
	var hit_pos := origin + forward * uv_range_m

	# PATCH: choose CLOSEST valid uv_reveal collision (more stable / consistent)
	if uv_cast != null and uv_cast.is_colliding():
		var best_d := INF
		for i in range(uv_cast.get_collision_count()):
			var col := uv_cast.get_collider(i)

			var ok := false
			if col != null and col is Node:
				var n := col as Node
				if n.is_in_group("uv_reveal"):
					ok = true
				elif n.get_parent() != null and n.get_parent().is_in_group("uv_reveal"):
					ok = true

			if not ok:
				continue

			var p := uv_cast.get_collision_point(i)
			var d := origin.distance_to(p)
			if d < best_d:
				best_d = d
				hit_pos = p

	var targets: Array = get_tree().get_nodes_in_group("uv_reveal")
	var count := 0

	for t in targets:
		if count >= reveal_max_targets_per_frame:
			break

		var rt := t as UvRevealTarget
		if rt == null or not is_instance_valid(rt):
			continue

		var d := rt.global_position.distance_to(hit_pos)
		if d <= reveal_radius_m:
			rt.set_reveal(true)
			_revealed_this_frame[rt] = true
			count += 1

	_previous_reveals = _previous_reveals.filter(func(x): return x != null and is_instance_valid(x))
	for k in _revealed_this_frame.keys():
		var rr := k as UvRevealTarget
		if rr != null and _previous_reveals.find(rr) == -1:
			_previous_reveals.append(rr)


func _clear_previous_reveals() -> void:
	for rt in _previous_reveals:
		if rt == null or not is_instance_valid(rt):
			continue
		if not _revealed_this_frame.has(rt):
			rt.set_reveal(false)


func _set_uv_on(v: bool) -> void:
	_uv_on = v

	if uv_light != null:
		uv_light.visible = v
	if uv_cast != null:
		uv_cast.enabled = v

	# PATCH: only the authority should replicate the toggle, otherwise remote clients can spam it.
	if replicate_light_toggle and multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		var mp: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		rpc("_rpc_set_uv_visible", v)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_uv_visible(v: bool) -> void:
	if uv_light != null:
		uv_light.visible = v


# send revealed targets to everyone (owner authoritative)
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
	for k in _revealed_this_frame.keys():
		var rt := k as UvRevealTarget
		if rt != null and is_instance_valid(rt):
			paths.append(String(rt.get_path()))

	rpc("_rpc_apply_reveals", paths)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_apply_reveals(paths: Array[String]) -> void:
	var seen: Dictionary = {}
	for pstr in paths:
		seen[pstr] = true
		var n: Node = get_node_or_null(NodePath(pstr))
		var rt := n as UvRevealTarget
		if rt != null and is_instance_valid(rt):
			rt.set_reveal(true)

	for old_key in _net_prev_reveals.keys():
		var kstr: String = String(old_key)
		if not seen.has(kstr):
			var n2: Node = get_node_or_null(NodePath(kstr))
			var rt2 := n2 as UvRevealTarget
			if rt2 != null and is_instance_valid(rt2):
				rt2.set_reveal(false)

	_net_prev_reveals = seen


# -------------------------
# AIM REPLICATION (QUAT)
# -------------------------
func _net_maybe_send_aim() -> void:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(aim_send_rate_hz, 1.0)
	if now - _aim_last_send_time < min_interval:
		return

	_aim_last_send_time = now

	# send only a clean rotation (quat), never a raw basis
	var q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	rpc("_rpc_set_aim_quat", q)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_aim_quat(q: Quaternion) -> void:
	if is_multiplayer_authority():
		return
	_aim_target_q = q
	_aim_has_target = true


func _net_interpolate_remote_aim() -> void:
	# PATCH: if we were just equipped (scene restart), don't interpolate old target for a frame
	if _just_equipped_reset:
		_just_equipped_reset = false
		return

	if not _aim_has_target:
		return

	var cur_q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	var new_q: Quaternion = cur_q.slerp(_aim_target_q, aim_lerp_alpha)

	# keep the same scale every time (prevents "big flashlight")
	var b: Basis = Basis(new_q).scaled(_base_scale)
	global_transform = Transform3D(b, global_position)


# -------------------------
# DROP REPLICATION (POS + QUAT)
# -------------------------
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
	# server doesn't need its own packet
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return

	_drop_target_pos = pos
	_drop_target_q = q
	_drop_has_target = true


func _net_interpolate_remote_drop() -> void:
	if not _drop_has_target:
		return

	var pos := global_position.lerp(_drop_target_pos, drop_lerp_alpha)
	var cur_q: Quaternion = global_transform.basis.orthonormalized().get_rotation_quaternion()
	var new_q: Quaternion = cur_q.slerp(_drop_target_q, drop_lerp_alpha)

	# rebuild a clean basis + keep our original scale
	var b: Basis = Basis(new_q).scaled(_base_scale)
	global_transform = Transform3D(b, pos)

# =========================
#   PATCH HELPERS
# =========================
func _reset_net_targets_to_current() -> void:
	# aim targets
	_aim_target_q = global_transform.basis.orthonormalized().get_rotation_quaternion()
	_aim_has_target = false
	_aim_last_send_time = 0.0

	# reveal targets
	_reveal_last_send_time = 0.0
	_net_prev_reveals.clear()
	_revealed_this_frame.clear()
	_previous_reveals.clear()

	# drop targets
	_reset_drop_targets_to_current()

func _reset_drop_targets_to_current() -> void:
	_drop_target_pos = global_position
	_drop_target_q = global_transform.basis.orthonormalized().get_rotation_quaternion()
	_drop_has_target = false
	_drop_last_send_time = 0.0
