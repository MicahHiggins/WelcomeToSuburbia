extends CharacterBody3D
# --------------------------------------------
# Generic 3D pickup item with:
#  - Outline that shows when hovered by a ray
#  - Simple gravity when on the ground
#  - "Held" state (used when a Player picks it up)
#  - Area3D used as the raycast target / hit shape
#  - Optional authority-only physics + lightweight net sync
# --------------------------------------------

# Mesh that should glow / outline when hovered
@onready var outline_mesh: MeshInstance3D = $batclean_low2/batclean_low/MeshInstance3D

# Area used as the thing the RayCast3D actually collides with
# (usually a simple shape around the object)
@onready var interact_area: Area3D = $Area3D

# Local state flags
var _hovered: bool = false   # true while the ray is pointing at this pickup
var _held: bool = false      # true while a player is holding this item

# Gravity strength for this body (pulled from project settings)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# If true, only the multiplayer authority will simulate physics/ gravity
# and then broadcast its transform to everyone else.
@export var authority_only_physics: bool = true

# -------------------------
#   NET SYNC SETTINGS
# -------------------------
@export var net_send_rate_hz: float = 15.0       # how often authority sends state
@export var net_lerp_alpha: float = 0.25         # interpolation factor for remotes

var _net_last_send_time: float = 0.0
var _net_target_transform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false


func _ready() -> void:
	# Add this node to the "pickup" group so Player/RayCast code
	# can identify it as an interactable object.
	add_to_group("pickup")

	# Outline is hidden by default (only visible when hovered)
	if outline_mesh:
		outline_mesh.visible = false

	# Ensure the interact Area3D is on a collision layer that the
	# RayCast3D is actually checking. (Ray cast collision_mask should
	# include layer 4.)
	if interact_area:
		# Turn on layer 4 for this area
		interact_area.set_collision_layer_value(4, true)
		# No need for this Area3D to detect anything itself; it only
		# exists to be hit by raycasts, so collision_mask is zero.
		interact_area.collision_mask = 0


func set_hovered(v: bool) -> void:
	# Called by the RayCast script when the cursor enters/leaves this item.
	_hovered = v

	# Show outline only when hovered AND not currently held
	if outline_mesh and not _held:
		outline_mesh.visible = v


func set_held(v: bool) -> void:
	# Called by Player code (via RPC) when the item is picked up / dropped.
	# This is executed on ALL peers, keeping _held in sync everywhere.
	_held = v

	# When held, outline is always off
	if outline_mesh:
		outline_mesh.visible = false

	# While held, this body should not simulate physics / gravity
	if v:
		velocity = Vector3.ZERO
	else:
		# On drop, gravity resumes in _do_physics.
		pass


func interact() -> void:
	# Optional direct interaction method; the real pickup logic
	# is handled by the Player.gd RPC system.
	print("Bat interacted with!")
	set_held(true)


func _physics_process(delta: float) -> void:
	var has_peer := multiplayer.has_multiplayer_peer()

	# When using authority-only physics in multiplayer:
	# - Authority runs full physics + sends transform.
	# - Non-authority lerps toward the last received transform.
	if authority_only_physics and has_peer:
		if is_multiplayer_authority():
			_do_physics(delta)
			_net_maybe_send_state()
		else:
			_net_interpolate_remote()
		return

	# Single-player or authority_only_physics = false:
	# everyone just runs local physics (no net sync needed).
	_do_physics(delta)


# -------------------------
#    LOCAL PHYSICS STEP
# -------------------------
func _do_physics(delta: float) -> void:
	# If held by a player, it should not fall or slide on the ground.
	if _held:
		velocity = Vector3.ZERO
		return

	# Basic gravity: if not on the floor, pull downward.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# When on the floor, gently reduce X/Z so it doesn't slide forever.
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)

	# Move the body with the current velocity.
	move_and_slide()


# -------------------------
#   NET SYNC HELPERS
# -------------------------
func _net_maybe_send_state() -> void:
	# Only send if we have a proper multiplayer peer and are connected.
	if not multiplayer.has_multiplayer_peer():
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null:
		return
	if mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	# Throttle sending to net_send_rate_hz
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(net_send_rate_hz, 1.0)
	if now - _net_last_send_time < min_interval:
		return

	_net_last_send_time = now

	# Send our transform to everyone (including ourselves).
	# Behavior is defined below in _net_set_state().
	rpc("_net_set_state", global_transform)


@rpc("any_peer", "call_local", "unreliable")
func _net_set_state(new_transform: Transform3D) -> void:
	# This is called on ALL peers whenever the authority sends a state:
	# - On the authority itself, we ignore (we already simulate locally).
	# - On non-authority peers, we store this as a target to interpolate to.
	if is_multiplayer_authority():
		return

	_net_target_transform = new_transform
	_net_has_target = true


func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return

	# Simple interpolation towards the last known authority transform.
	global_transform = global_transform.interpolate_with(_net_target_transform, net_lerp_alpha)
