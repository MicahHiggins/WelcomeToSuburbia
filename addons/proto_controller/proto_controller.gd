# Player.gd
# -----------
# Networked first-person player controller that:
# - Handles local movement + camera look
# - Owns a "carry marker" where pickup items are attached
# - Provides RPCs for server-authoritative pickup/drop
# - Is driven by a separate RayCast3D script for interaction
# - Works with any MultiplayerPeer backend (ENet, SteamMultiplayerPeer, etc.)

extends CharacterBody3D

# =========================
#        CONFIG / TOGGLES
# =========================

# Movement / abilities toggles (enable/disable features per player)
@export var can_move := true
@export var has_gravity := true
@export var can_jump := true
@export var can_sprint := true
@export var can_freefly := true

# Movement speeds
@export var look_speed := 0.002
@export var base_speed := 7.0
@export var jump_velocity := 4.5
@export var sprint_speed := 10.0
@export var freefly_speed := 25.0

# Input action names (must exist in InputMap)
@export var input_left := "ui_left"
@export var input_right := "ui_right"
@export var input_forward := "ui_up"
@export var input_back := "ui_down"
@export var input_jump := "ui_accept"
@export var input_sprint := "sprint"
@export var input_freefly := "freefly"
@export var input_interact := "interact"

# In Godot's MultiplayerAPI (SceneMultiplayer), the server/host
# always has peer ID 1, regardless of underlying transport (ENet, Steam, etc.)
const SERVER_ID := 1

# =========================
#         RUNTIME STATE
# =========================
var mouse_captured := false        # whether mouse is locked to screen for FPS look
var look_rotation := Vector2.ZERO  # pitch (x) + yaw (y)
var move_speed := 0.0              # current movement speed (walk/sprint)
var freeflying := false            # noclip state

# Item currently held by THIS local player (only valid on the owning peer)
var picked_object: Node = null

# =========================
#          NODE REFS
# =========================
@onready var head: Node3D = $Head                     # yaw/pitch root for camera
@onready var collider: CollisionShape3D = $Collider   # player collision shape
@onready var cam: Camera3D = $Head/Camera3D           # first-person camera

# Marker where held items attach (bat in hand). Must exist in scene:
# Head/CarryObjectMarker (Node3D or Marker3D).
@onready var carry_marker: Node3D = (
	$Head/CarryObjectMarker if $Head.has_node("CarryObjectMarker") else null
)

# Optional UI hint label ("Press E to interact")
var hint_label: Label

signal interact_object(target: Node)


# =========================
#       MULTIPLAYER SETUP
# =========================
func _enter_tree() -> void:
	# Assumes each Player node's name == its peer_id as string.
	# Example: node named "1" is host, "2" is a client, etc.
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	add_to_group("player")

	# Only the local authority controls this player and owns its camera
	if is_multiplayer_authority():
		cam.current = true
	else:
		cam.current = false

	_setup_hint_ui()
	_check_input_mappings()


# =========================
#        UI HINT SETUP
# =========================
func _setup_hint_ui() -> void:
	var ui := $UI if has_node("UI") else null
	if ui == null:
		ui = CanvasLayer.new()
		ui.name = "UI"
		add_child(ui)

	var h := ui.get_node("Hint") if ui.has_node("Hint") else null
	if h == null:
		h = Label.new()
		h.name = "Hint"
		h.text = "Press E to interact"
		h.visible = false
		h.add_theme_color_override("font_color", Color(1, 1, 1))
		h.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		h.add_theme_constant_override("outline_size", 3)
		# Anchor top-center on screen
		h.anchor_left = 0.5
		h.anchor_right = 0.5
		h.anchor_top = 0.0
		h.anchor_bottom = 0.0
		h.position = Vector2(0, 40)
		ui.add_child(h)

	hint_label = h


# =========================
#         INPUT HANDLING
# =========================
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Escape / ui_cancel = release mouse
	if event.is_action_pressed("ui_cancel"):
		_release_mouse()

	# NOTE:
	# "interact" is NOT handled here.
	# The RayCast3D script listens for interact and calls
	# request_pickup_rpc / request_drop_rpc on THIS player.


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Capture mouse whenever we click the left button
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_capture_mouse()

	# Mouse look (only when mouse is captured)
	if mouse_captured and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_rotate_look(mm.relative)

	# Toggle noclip / freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if freeflying:
			_disable_freefly()
		else:
			_enable_freefly()


# =========================
#      FRAME / PHYSICS
# =========================
func _process(_dt: float) -> void:
	if not is_multiplayer_authority():
		return
	# Hover + hint visibility can be driven from the RayCast script.
	# Nothing special needed here right now.


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# --- Freefly mode (noclip) ---
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() * freefly_speed * delta
		move_and_collide(motion)
		return

	# --- Gravity ---
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# --- Jump ---
	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

	# --- Sprint vs walk ---
	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	# --- Directional WASD movement ---
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		if move_dir != Vector3.ZERO:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, move_speed)
			velocity.z = move_toward(velocity.z, 0.0, move_speed)
	else:
		velocity.x = 0.0
		velocity.y = 0.0

	move_and_slide()


# =========================
#       HELPER METHODS
# =========================
func _rotate_look(delta_rel: Vector2) -> void:
	# Vertical (pitch) on the head
	look_rotation.x -= delta_rel.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

	# Horizontal (yaw) on the body
	look_rotation.y -= delta_rel.x * look_speed

	# Reset bases so rotations don't accumulate weirdly
	transform.basis = Basis()
	rotate_y(look_rotation.y)

	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func _release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


func _enable_freefly() -> void:
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO


func _disable_freefly() -> void:
	collider.disabled = false
	freeflying = false


func _check_input_mappings() -> void:
	# Safety checks so missing input actions don’t silently break movement
	if can_move and not InputMap.has_action(input_left):
		push_error("Missing action: " + input_left); can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Missing action: " + input_right); can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Missing action: " + input_forward); can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Missing action: " + input_back); can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Missing action: " + input_jump); can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Missing action: " + input_sprint); can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Missing action: " + input_freefly); can_freefly = false
	if not InputMap.has_action(input_interact):
		push_error("Missing action: " + input_interact)


# =========================
#   BRIDGE CALLED BY RAY
# =========================
# These are what the RayCast3D script calls when you press "interact".

func request_pickup_rpc(item_path: NodePath) -> void:
	# Called by the RayCast on THIS local player.
	# The server should always be the authority that decides
	# who actually picks up the item (even with Steam).

	if multiplayer.is_server():
		# If this is the host/server, we can call request_pickup()
		# directly (no rpc), but request_pickup uses remote_sender_id,
		# so the host case is handled inside request_pickup.
		request_pickup(item_path)
	else:
		# Clients send an RPC to the server (peer 1).
		rpc_id(SERVER_ID, "request_pickup", item_path)


func request_drop_rpc() -> void:
	if picked_object == null:
		return

	var item_path: NodePath = picked_object.get_path()

	if multiplayer.is_server():
		# Host just calls request_drop directly
		request_drop(item_path)
	else:
		# Clients ask server to process the drop
		rpc_id(SERVER_ID, "request_drop", item_path)


# =========================
#   SERVER-AUTH PICKUP/DROP
# =========================
# The server is the only peer that modifies the game state
# (who holds what). Changes are then broadcast via apply_* RPCs.

@rpc("any_peer", "reliable")
func request_pickup(item_path: NodePath) -> void:
	# This runs ONLY on the server.
	if not multiplayer.is_server():
		return

	# Who sent this RPC?
	var sender := multiplayer.get_remote_sender_id()

	# If this was called locally (host path via request_pickup_rpc),
	# remote_sender_id == 0. In that case, treat the sender
	# as the server's own peer id.
	if sender == 0:
		sender = multiplayer.get_unique_id()

	# Look up the item node in the scene tree
	var item := get_tree().root.get_node_or_null(item_path)
	if item == null:
		return
	if not item.is_in_group("pickup"):
		return

	# Prevent double-pickups on the server
	if item.has_meta("locked") and bool(item.get_meta("locked")):
		return
	item.set_meta("locked", true)

	# Find the Player node for that peer id
	var p := _player_for_peer(sender)
	if p == null:
		item.set_meta("locked", false)
		return

	# Tell everyone to apply the pickup for this item + player
	# apply_pickup is marked call_local so it runs on all peers.
	rpc("apply_pickup", item_path, p.get_path(), sender)


@rpc("any_peer", "call_local", "reliable")
func apply_pickup(item_path: NodePath, player_path: NodePath, new_owner_id: int) -> void:
	# This runs on ALL peers (server + all clients).
	# It actually moves the item under the correct player/marker
	# so everyone sees the same thing.

	var item := get_tree().root.get_node_or_null(item_path)
	var player := get_tree().root.get_node_or_null(player_path)
	if item == null or player == null:
		return

	# Transfer network authority to the new owner
	item.set_multiplayer_authority(new_owner_id)

	# Try to attach directly to that player's CarryObjectMarker
	var marker := player.get_node_or_null("Head/CarryObjectMarker")

	if marker != null and marker is Node3D:
		var marker3d := marker as Node3D

		# Reparent under the marker so local (0,0,0) == marker position.
		# This guarantees the same relative position for EVERY peer.
		item.reparent(marker3d)
		# Reset local transform so it snaps exactly to the marker.
		item.transform = Transform3D.IDENTITY
	else:
		# Fallback: if marker is missing for some reason, reparent
		# under the player and match global transform roughly.
		item.reparent(player)
		# Optional: you could keep previous global transform or
		# set it based on some default offset.

	# Let the item know it's now held (disables collision, hides outline, etc.)
	if "set_held" in item:
		item.call_deferred("set_held", true)

	# Only the owning peer remembers "picked_object"
	if multiplayer.get_unique_id() == new_owner_id:
		picked_object = item


@rpc("any_peer", "reliable")
func request_drop(item_path: NodePath) -> void:
	# Only server responds to drop requests
	if not multiplayer.is_server():
		return

	var item := get_tree().root.get_node_or_null(item_path)
	if item == null:
		return

	# Unlock the item so it can be picked up again later
	item.set_meta("locked", false)

	# Broadcast the drop to all peers (apply_drop is call_local)
	rpc("apply_drop", item_path)


@rpc("any_peer", "call_local", "reliable")
func apply_drop(item_path: NodePath) -> void:
	# Runs on all peers. Puts the item back in the world.

	var item := get_tree().root.get_node_or_null(item_path)
	if item == null:
		return

	# Reparent to the current scene root (or some world node)
	# Global transform is preserved, so it drops where it was.
	item.reparent(get_tree().current_scene)

	# Restore item behavior (outline, collider, gravity) via set_held(false)
	if "set_held" in item:
		item.call_deferred("set_held", false)

	# If THIS peer thought we were holding this object, clear reference
	if picked_object == item and is_multiplayer_authority():
		picked_object = null


# =========================
#      PLAYER LOOKUP
# =========================
func _player_for_peer(peer_id: int) -> Node3D:
	# Find the Player node whose multiplayer authority matches peer_id
	var players := get_tree().get_nodes_in_group("player")
	for n in players:
		if n is Node3D:
			var nd := n as Node3D
			if nd.get_multiplayer_authority() == peer_id:
				return nd
	return null
