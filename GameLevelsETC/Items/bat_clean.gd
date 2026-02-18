extends CharacterBody3D
# --------------------------------------------
# Bat pickup:
# - server owns it (one source of truth)
# - server simulates physics
# - server streams transform (unreliable)
# - server also sends a reliable snapshot for late joiners
# --------------------------------------------

@onready var outline_mesh: MeshInstance3D = $batclean_low2/batclean_low/MeshInstance3D
@onready var interact_area: Area3D = $Area3D

var _hovered: bool = false
var _held: bool = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var authority_only_physics: bool = true

@export var net_send_rate_hz: float = 15.0
@export var net_lerp_alpha: float = 0.25

# if we get too far off, just snap (prevents slow flying across the map)
@export var snap_distance_m: float = 2.0

var _net_last_send_time: float = 0.0
var _net_target_transform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false


func _enter_tree() -> void:
	# server always owns the bat (same idea as bob)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		set_multiplayer_authority(1)


func _ready() -> void:
	# Add this node to the "pickup" group so Player/RayCast code
	print("IM IN")
	# can identify it as an interactable object.
	add_to_group("pickup")

	if outline_mesh:
		outline_mesh.visible = false

	if interact_area:
		interact_area.set_collision_layer_value(4, true)
		interact_area.collision_mask = 0

	# init target so we don’t lerp from identity
	_net_target_transform = global_transform

	# late joiners: give them the bat position immediately (reliable)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

		# also push one reliable snapshot right away
		_broadcast_initial_state()


func _broadcast_initial_state() -> void:
	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_net_set_state_reliable", global_transform)


func _on_peer_connected(peer_id: int) -> void:
	rpc_id(peer_id, "_net_set_state_reliable", global_transform)


func set_hovered(v: bool) -> void:
	_hovered = v
	if outline_mesh and not _held:
		outline_mesh.visible = v


func set_held(v: bool) -> void:
	_held = v

	if outline_mesh:
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
		return

	_do_physics(delta)


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
	# reliable snapshot for join-in-progress / hard reset
	if is_multiplayer_authority():
		return
	global_transform = new_transform
	_net_target_transform = new_transform
	_net_has_target = true


func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return

	# if we’re way off, snap instead of lerping forever
	var dist := global_position.distance_to(_net_target_transform.origin)
	if dist >= snap_distance_m:
		global_transform = _net_target_transform
		return

	global_transform = global_transform.interpolate_with(_net_target_transform, net_lerp_alpha)
