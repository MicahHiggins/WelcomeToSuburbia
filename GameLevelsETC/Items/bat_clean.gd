extends CharacterBody3D

@onready var outline_mesh: MeshInstance3D = $batclean_low2/batclean_low/MeshInstance3D
@onready var interact_area: Area3D = $Area3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _hovered: bool = false
var _held: bool = false

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

@export var authority_only_physics: bool = true

@export var net_send_rate_hz: float = 15.0
@export var net_lerp_alpha: float = 0.25
@export var snap_distance_m: float = 2.0

@export var debug_print: bool = true
@export var debug_interval_sec: float = 0.75

var _net_last_send_time: float = 0.0
var _net_target_transform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false

var _dbg_t: float = 0.0

func _enter_tree() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("pickup")

	if outline_mesh != null:
		outline_mesh.visible = false

	if interact_area != null:
		interact_area.set_collision_layer_value(4, true)
		interact_area.collision_mask = 0

	_net_target_transform = global_transform

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		_broadcast_initial_state()

	if debug_print:
		print("BAT READY | name:", name,
			" uid:", (multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1),
			" auth:", int(get_multiplayer_authority()),
			" is_auth:", is_multiplayer_authority(),
			" pos:", global_position,
			" scale:", global_scale,
			" cs_ok:", collision_shape != null,
			" area_ok:", interact_area != null,
			" mesh_ok:", outline_mesh != null)

func _broadcast_initial_state() -> void:
	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_net_set_state_reliable", global_transform)

func _on_peer_connected(peer_id: int) -> void:
	rpc_id(peer_id, "_net_set_state_reliable", global_transform)

func set_hovered(v: bool) -> void:
	_hovered = v
	if outline_mesh != null and not _held:
		outline_mesh.visible = v

func set_held(v: bool) -> void:
	_held = v
	if outline_mesh != null:
		outline_mesh.visible = false
	if v:
		velocity = Vector3.ZERO

func interact() -> void:
	print("Bat interacted with!")
	set_held(true)

func _physics_process(delta: float) -> void:
	var has_peer := multiplayer.has_multiplayer_peer()

	if authority_only_physics and has_peer:
		if is_multiplayer_authority():
			_do_physics(delta)
			_net_maybe_send_state()
		else:
			_net_interpolate_remote()
	else:
		_do_physics(delta)

	_dbg_t += delta
	if debug_print and _dbg_t >= debug_interval_sec:
		_dbg_t = 0.0
		_debug_tick()

func _do_physics(delta: float) -> void:
	if _held:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)

	move_and_slide()

func _net_maybe_send_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null:
		return
	if mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(net_send_rate_hz, 1.0)
	if now - _net_last_send_time < min_interval:
		return

	_net_last_send_time = now
	rpc("_net_set_state_unreliable", global_transform)

@rpc("any_peer", "call_local", "unreliable")
func _net_set_state_unreliable(new_transform: Transform3D) -> void:
	if is_multiplayer_authority():
		return
	_net_target_transform = new_transform
	_net_has_target = true

@rpc("any_peer", "call_local", "reliable")
func _net_set_state_reliable(new_transform: Transform3D) -> void:
	if is_multiplayer_authority():
		return
	global_transform = new_transform
	_net_target_transform = new_transform
	_net_has_target = true

func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return

	var dist := global_position.distance_to(_net_target_transform.origin)
	if dist >= snap_distance_m:
		global_transform = _net_target_transform
		return

	global_transform = global_transform.interpolate_with(_net_target_transform, net_lerp_alpha)

func _debug_tick() -> void:
	var mp_on := multiplayer.has_multiplayer_peer()
	var uid := (multiplayer.get_unique_id() if mp_on else -1)
	var auth := int(get_multiplayer_authority())
	var is_auth := is_multiplayer_authority()

	var pos := global_position
	var vel := velocity
	var on_floor := is_on_floor()
	var drift := pos.distance_to(_net_target_transform.origin)

	var mesh_ok := outline_mesh != null
	var area_ok := interact_area != null
	var cs_ok := collision_shape != null
	var cs_disabled := false
	if cs_ok:
		cs_disabled = collision_shape.disabled

	var mesh_vis := false
	if mesh_ok:
		mesh_vis = outline_mesh.visible

	print("BAT DBG | uid:", uid,
		" auth:", auth,
		" is_auth:", is_auth,
		" held:", _held,
		" hovered:", _hovered,
		" pos:", pos,
		" vel:", vel,
		" on_floor:", on_floor,
		" drift:", drift,
		" scale:", global_scale,
		" cs_ok:", cs_ok,
		" cs_dis:", cs_disabled,
		" mesh_ok:", mesh_ok,
		" mesh_vis:", mesh_vis,
		" area_ok:", area_ok,
		" net_has_target:", _net_has_target)
