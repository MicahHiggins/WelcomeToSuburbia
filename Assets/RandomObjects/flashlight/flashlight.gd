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

# server id (host)
const SERVER_ID: int = 1

# reveal replication (owner broadcasts which targets are being hit)
@export var replicate_reveal: bool = true
@export var reveal_send_rate_hz: float = 20.0
var _reveal_last_send_time: float = 0.0

# receiver-side cache so we can turn off ones not in the latest packet
var _net_prev_reveals: Dictionary = {} # String(path) -> bool

# replicate flashlight aim (rotation) so all peers see same beam direction
@export var replicate_aim: bool = true
@export var aim_send_rate_hz: float = 20.0
@export var aim_lerp_alpha: float = 0.35

var _aim_last_send_time: float = 0.0
var _aim_target_basis: Basis = Basis.IDENTITY
var _aim_has_target: bool = false


func _ready() -> void:
	add_to_group("pickup")

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

	# ADDED: make sure our starting aim basis is "clean rotation" (no scale)
	_aim_target_basis = global_transform.basis.orthonormalized()


func set_hovered(v: bool) -> void:
	_hovered = v
	if outline_mesh != null and not _held:
		outline_mesh.visible = v


func set_held(v: bool) -> void:
	_held = v
	if outline_mesh != null:
		outline_mesh.visible = false
	if not v:
		_set_uv_on(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _held:
		return
	if event.is_action_pressed(String(toggle_action)):
		_set_uv_on(not _uv_on)


func _process(_delta: float) -> void:
	# SINGLEPLAYER: local reveal is fine
	if not multiplayer.has_multiplayer_peer():
		_process_reveal_local()
		return

	# MULTIPLAYER:
	# Only the flashlight authority computes reveal and broadcasts it.
	# Everyone else only applies what they receive.
	if replicate_reveal and is_multiplayer_authority():
		_process_reveal_local()
		_net_maybe_send_reveals()
	else:
		# Non-authority should not run local reveal; it would diverge.
		_revealed_this_frame.clear()
		_clear_previous_reveals()

	# Aim replication tick (rotation)
	if replicate_aim and multiplayer.has_multiplayer_peer() and _held:
		if is_multiplayer_authority():
			_net_maybe_send_aim()
		else:
			_net_interpolate_remote_aim()


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


func _reveal_in_beam() -> void:
	# Default beam center is max range straight ahead
	var hit_pos := global_transform.origin + (-global_transform.basis.z.normalized() * uv_range_m)

	# Only accept collisions that belong to uv_reveal targets
	if uv_cast != null and uv_cast.is_colliding():
		var best_d := -INF

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
			var d := global_transform.origin.distance_to(p)

			# Pick the farthest valid uv_reveal hit
			if d > best_d:
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

	if replicate_light_toggle and multiplayer.has_multiplayer_peer():
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

	# Pack current revealed targets as absolute node paths (must match on all peers)
	var paths: Array[String] = []
	for k in _revealed_this_frame.keys():
		var rt := k as UvRevealTarget
		if rt != null and is_instance_valid(rt):
			paths.append(String(rt.get_path()))

	rpc("_rpc_apply_reveals", paths)


# apply reveal list on all peers (including host)
@rpc("any_peer", "call_local", "unreliable")
func _rpc_apply_reveals(paths: Array[String]) -> void:
	# Turn ON any targets in the list
	var seen: Dictionary = {}
	for pstr in paths:
		seen[pstr] = true
		var n: Node = get_node_or_null(NodePath(pstr))
		var rt := n as UvRevealTarget
		if rt != null and is_instance_valid(rt):
			rt.set_reveal(true)

	# Turn OFF anything that was on last tick but is missing now
	for old_key in _net_prev_reveals.keys():
		var kstr: String = String(old_key)
		if not seen.has(kstr):
			var n2: Node = get_node_or_null(NodePath(kstr))
			var rt2 := n2 as UvRevealTarget
			if rt2 != null and is_instance_valid(rt2):
				rt2.set_reveal(false)

	_net_prev_reveals = seen


# Aim replication (rotation only)
func _net_maybe_send_aim() -> void:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(aim_send_rate_hz, 1.0)
	if now - _aim_last_send_time < min_interval:
		return

	_aim_last_send_time = now

	# CHANGED: always send a clean rotation basis (no scale) so slerp won't explode
	var clean_basis: Basis = global_transform.basis.orthonormalized()
	rpc("_rpc_set_aim_basis", clean_basis)


@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_aim_basis(b: Basis) -> void:
	# owner ignores its own packets
	if is_multiplayer_authority():
		return

	# CHANGED: sanitize incoming basis so it's a real rotation
	_aim_target_basis = b.orthonormalized()
	_aim_has_target = true


func _net_interpolate_remote_aim() -> void:
	if not _aim_has_target:
		return

	# CHANGED: sanitize both bases before slerp (fixes the "Basis must be normalized" error)
	var gt := global_transform
	var cur_basis: Basis = gt.basis.orthonormalized()
	var tgt_basis: Basis = _aim_target_basis.orthonormalized()

	gt.basis = cur_basis.slerp(tgt_basis, aim_lerp_alpha)
	global_transform = gt
