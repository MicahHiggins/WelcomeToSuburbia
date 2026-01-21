extends CharacterBody3D
# --------------------------------------------
# Networked first-person player controller:
# - Local movement + camera look
# - Carry marker for pickup items
# - Server-authoritative pickup/drop
# - Transport-agnostic (ENet, SteamMultiplayerPeer, etc.)
# --------------------------------------------

# =========================
#        CONFIG / TOGGLES
# =========================

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

# Server peer ID for SceneMultiplayer (ENet, Steam, etc.)
const SERVER_ID := 1

# =========================
#         RUNTIME STATE
# =========================
var mouse_captured: bool = false
var look_rotation: Vector2 = Vector2.ZERO
var move_speed: float = 0.0
var freeflying: bool = false

# Item currently held by THIS local player
var picked_object: Node = null

# =========================
#    NETWORK SYNC CONFIG
# =========================
@export var net_send_rate_hz: float = 20.0      # how often authority sends state
@export var net_lerp_alpha: float = 0.2         # interpolation factor for remotes

var _net_last_send_time: float = 0.0
var _net_target_transform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false

# =========================
#          NODE REFS
# =========================
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider
@onready var cam: Camera3D = $Head/Camera3D
@onready var footstep: AudioStreamPlayer3D = $PlayerAudios/Footstep

@onready var carry_marker: Node3D = (
	$Head/CarryObjectMarker if $Head.has_node("CarryObjectMarker") else null
)

var hint_label: Label

signal interact_object(target: Node)


# =========================
#       MULTIPLAYER SETUP
# =========================
func _enter_tree() -> void:
	# Name of Player node is expected to be the peer ID as string.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("player")

	# Only the local authority owns its camera
	if is_multiplayer_authority():
		cam.current = true
	else:
		cam.current = false

	_net_target_transform = global_transform

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

	if event.is_action_pressed("ui_cancel"):
		_release_mouse()
	# "interact" is handled by the RayCast script.


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_capture_mouse()

	if mouse_captured and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_rotate_look(mm.relative)

	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if freeflying:
			_disable_freefly()
		else:
			_enable_freefly()


# =========================
#      FRAME / PHYSICS
# =========================
func _process(_dt: float) -> void:
	# Hover + hint visibility driven from RayCast; nothing special here now.
	pass


func _physics_process(delta: float) -> void:
	# AUTHORITY: simulate full movement and send state
	if is_multiplayer_authority():
		_physics_authority(delta)
		_net_maybe_send_state()
		return

	# NON-AUTHORITY: just interpolate toward last received state
	_net_interpolate_remote()


func _physics_authority(delta: float) -> void:
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

	if is_on_floor() and velocity != Vector3.ZERO:
		%FootstepAnimation.play("walk")

	move_and_slide()


func _net_maybe_send_state() -> void:
	# Only send if we actually have a connected peer
	if not multiplayer.has_multiplayer_peer():
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null:
		return
	if mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	# Throttle to net_send_rate_hz
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(net_send_rate_hz, 1.0)
	if now - _net_last_send_time < min_interval:
		return

	_net_last_send_time = now

	# Everyone (host + clients) calls this; server will rebroadcast.
	# Reliability is defined by the @rpc annotation on _net_state_from_client.
	rpc("_net_state_from_client", global_transform)


func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return
	# Simple lerp toward target transform
	global_transform = global_transform.interpolate_with(_net_target_transform, net_lerp_alpha)


# Called from authority on ANY peer.
# - On a client: runs locally (because of call_local) and also on the server.
# - On the server: after receiving from a client, rebroadcasts to everyone.
@rpc("any_peer", "call_local", "unreliable")
func _net_state_from_client(new_transform: Transform3D) -> void:
	if multiplayer.is_server():
		# On the server's copy of this player
		if not is_multiplayer_authority():
			_net_set_target(new_transform)
		# Rebroadcast to all clients (including the sender; they will ignore if authority)
		rpc("_net_apply_state", new_transform)
	else:
		# On a client:
		# - For the local authority player, is_multiplayer_authority() == true → ignore.
		# - For remote players (copies spawned by RPCs), apply as target.
		if not is_multiplayer_authority():
			_net_set_target(new_transform)


@rpc("any_peer", "unreliable")
func _net_apply_state(new_transform: Transform3D) -> void:
	# Received from server on every client
	if is_multiplayer_authority():
		# Never override the locally controlled player
		return
	_net_set_target(new_transform)


func _net_set_target(new_transform: Transform3D) -> void:
	_net_target_transform = new_transform
	_net_has_target = true


func _play_footstep_audio() -> void:
	footstep.pitch_scale = randf_range(0.85, 1.25)
	footstep.play()


# =========================
#       HELPER METHODS
# =========================
func _rotate_look(delta_rel: Vector2) -> void:
	look_rotation.x -= delta_rel.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

	look_rotation.y -= delta_rel.x * look_speed

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
func request_pickup_rpc(item_path: NodePath) -> void:
	if multiplayer.is_server():
		request_pickup(item_path)
	else:
		rpc_id(SERVER_ID, "request_pickup", item_path)


func request_drop_rpc() -> void:
	if picked_object == null:
		return

	var item_path: NodePath = picked_object.get_path()

	if multiplayer.is_server():
		request_drop(item_path)
	else:
		rpc_id(SERVER_ID, "request_drop", item_path)


# =========================
#   SERVER-AUTH PICKUP/DROP
# =========================
@rpc("any_peer", "reliable")
func request_pickup(item_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()

	var item := get_tree().root.get_node_or_null(item_path)
	if item == null:
		return
	if not item.is_in_group("pickup"):
		return

	if item.has_meta("locked") and bool(item.get_meta("locked")):
		return
	item.set_meta("locked", true)

	var p := _player_for_peer(sender)
	if p == null:
		item.set_meta("locked", false)
		return

	rpc("apply_pickup", item_path, p.get_path(), sender)


@rpc("any_peer", "call_local", "reliable")
func apply_pickup(item_path: NodePath, player_path: NodePath, new_owner_id: int) -> void:
	var item := get_tree().root.get_node_or_null(item_path)
	var player := get_tree().root.get_node_or_null(player_path)
	if item == null or player == null:
		return

	item.set_multiplayer_authority(new_owner_id)

	var marker := player.get_node_or_null("Head/CarryObjectMarker")
	if marker != null and marker is Node3D:
		var marker3d := marker as Node3D
		item.reparent(marker3d)
		item.transform = Transform3D.IDENTITY
	else:
		item.reparent(player)

	if "set_held" in item:
		item.call_deferred("set_held", true)

	if multiplayer.get_unique_id() == new_owner_id:
		picked_object = item


@rpc("any_peer", "reliable")
func request_drop(item_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var item := get_tree().root.get_node_or_null(item_path)
	if item == null:
		return

	item.set_meta("locked", false)
	rpc("apply_drop", item_path)


@rpc("any_peer", "call_local", "reliable")
func apply_drop(item_path: NodePath) -> void:
	var item := get_tree().root.get_node_or_null(item_path)
	if item == null:
		return

	item.reparent(get_tree().current_scene)

	if "set_held" in item:
		item.call_deferred("set_held", false)

	if picked_object == item and is_multiplayer_authority():
		picked_object = null


# =========================
#      PLAYER LOOKUP
# =========================
func _player_for_peer(peer_id: int) -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	for n in players:
		if n is Node3D:
			var nd := n as Node3D
			if nd.get_multiplayer_authority() == peer_id:
				return nd
	return null
