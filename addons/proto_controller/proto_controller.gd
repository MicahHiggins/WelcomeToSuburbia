extends CharacterBody3D
# --------------------------------------------
# Networked first-person player controller:
# - Local movement + camera look
# - Multiplayer-safe inventory (server tells owner)
# - Pickup/drop/use routed through ItemManager ONLY
# - Drop is "drop" (bind to G)
# - Use/Attack is "use-attack" (plays "swing" locally + server broadcasts via ItemManager)
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
@export var input_drop := "drop"               # bind to G
@export var input_use_attack := "use-attack"   # bind to whatever you want

# Attack animation config
@export var attack_anim_name: StringName = &"swing"
@export var attack_cooldown: float = 0.35

# OPTIONAL: If your swing AnimationPlayer is on the player somewhere, set this.
# (But you said the AnimationPlayer is on the BAT, so the held-item fallback will usually be used.)
@export var swing_animplayer_path: NodePath = NodePath("AnimationPlayer")

# Multiplayer footsteps (audible to nearby players)
@export var footstep_hear_radius: float = 18.0
@export var footstep_min_interval: float = 0.12

# If your ItemManager is not at the scene root, this finds it anyway.
@export var item_manager_name: StringName = &"ItemManager"

# Server peer ID for SceneMultiplayer (ENet, Steam, etc.)
const SERVER_ID: int = 1

# =========================
#         RUNTIME STATE
# =========================
var mouse_captured: bool = false
var look_rotation: Vector2 = Vector2.ZERO
var move_speed: float = 0.0
var freeflying: bool = false

# Item currently held by THIS local player (local pointer; not authoritative)
var picked_object: Node = null

# Inventory is per-player, runtime-only
var inventory: Array[StringName] = []
signal inventory_changed(inv: Array[StringName])

# Attack spam guard
var _last_attack_time: float = -9999.0

# Cached ItemManager reference (resolved lazily + refreshed if invalid)
var _item_manager_cached: Node = null

# =========================
#      SANITY / TETHER
# =========================
var sanity: float = 100.0
var sanity_fx_intensity: float = 0.0

var tether_partner_pos: Vector3 = Vector3.ZERO
var tether_distance: float = 0.0
var tether_speed_mult: float = 1.0
var tether_hard_lock: bool = false

var _sanity_fx_rect: ColorRect
var _sanity_fx_mat: ShaderMaterial

# Hint timer
var _hint_timer: Timer
var hint_label: Label

# Footstep spam guard
var _last_footstep_time: float = -9999.0

# =========================
#    NETWORK SYNC CONFIG
# =========================
@export var net_send_rate_hz: float = 20.0
@export var net_lerp_alpha: float = 0.2

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

# Optional animation player for swing (resolved in _ready)
var _swing_anim: AnimationPlayer = null

signal interact_object(target: Node)

# =========================
#       MULTIPLAYER SETUP
# =========================
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	add_to_group("player")
	cam.current = is_multiplayer_authority()
	_net_target_transform = global_transform

	_swing_anim = get_node_or_null(swing_animplayer_path) as AnimationPlayer

	_setup_hint_ui()
	_check_input_mappings()
	_setup_sanity_fx_ui()

# =========================
#        PATH HELPERS
# =========================
func _scene_root() -> Node:
	return get_tree().current_scene

# =========================
#      ITEM MANAGER HOOK
# =========================
func _get_item_manager() -> Node:
	# Return cached if still valid
	if _item_manager_cached != null and is_instance_valid(_item_manager_cached):
		return _item_manager_cached

	var scene: Node = _scene_root()
	if scene == null:
		return null

	# 1) Direct child lookup (fast path)
	var direct: Node = scene.get_node_or_null(String(item_manager_name))
	if direct != null:
		_item_manager_cached = direct
		return _item_manager_cached

	# 2) Recursive find (fixes "ItemManager not at scene root" problems)
	var found: Node = scene.find_child(String(item_manager_name), true, false)
	if found != null:
		_item_manager_cached = found
		return _item_manager_cached

	return null

func _get_held_node() -> Node:
	# Prefer carry marker child (because ItemManager reparents items there)
	if carry_marker != null and carry_marker.get_child_count() > 0:
		var child: Node = carry_marker.get_child(0)
		if child != null and is_instance_valid(child):
			return child

	# Fallback local pointer
	if picked_object != null and is_instance_valid(picked_object):
		return picked_object

	return null

func _is_holding_item() -> bool:
	return _get_held_node() != null

func _get_held_item_key() -> NodePath:
	var held: Node = _get_held_node()
	if held == null:
		return NodePath("")

	if not held.has_meta("item_key"):
		return NodePath("")

	var key_str: String = String(held.get_meta("item_key"))
	if key_str == "":
		return NodePath("")

	return NodePath(key_str)

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
		h.text = "F = interact | G = drop | use-attack = swing"
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

	_hint_timer = ui.get_node_or_null("HintTimer") as Timer
	if _hint_timer == null:
		_hint_timer = Timer.new()
		_hint_timer.name = "HintTimer"
		_hint_timer.one_shot = true
		ui.add_child(_hint_timer)
	_hint_timer.timeout.connect(_on_hint_timeout)

func _on_hint_timeout() -> void:
	pass

func _show_hint_temp(msg: String, seconds: float = 1.25) -> void:
	if hint_label == null:
		return
	hint_label.text = msg
	hint_label.visible = true
	if _hint_timer != null:
		_hint_timer.stop()
		_hint_timer.wait_time = seconds
		_hint_timer.start()

# =========================
#     SANITY SCREEN FX UI
# =========================
func _setup_sanity_fx_ui() -> void:
	if not is_multiplayer_authority():
		return

	var ui := $UI if has_node("UI") else null
	if ui == null:
		ui = CanvasLayer.new()
		ui.name = "UI"
		add_child(ui)

	_sanity_fx_rect = ui.get_node_or_null("SanityFX")
	if _sanity_fx_rect == null:
		_sanity_fx_rect = ColorRect.new()
		_sanity_fx_rect.name = "SanityFX"
		_sanity_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sanity_fx_rect.anchor_left = 0.0
		_sanity_fx_rect.anchor_top = 0.0
		_sanity_fx_rect.anchor_right = 1.0
		_sanity_fx_rect.anchor_bottom = 1.0
		_sanity_fx_rect.offset_left = 0.0
		_sanity_fx_rect.offset_top = 0.0
		_sanity_fx_rect.offset_right = 0.0
		_sanity_fx_rect.offset_bottom = 0.0
		_sanity_fx_rect.z_index = 999
		ui.add_child(_sanity_fx_rect)

		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;

	float w = sin((uv.y * 14.0 + t * 2.0)) * cos((uv.x * 10.0 - t * 1.7));
	vec2 offs = vec2(w, -w) * (0.012 * intensity);

	vec4 col = texture(screen_tex, uv + offs);

	col.rgb += vec3(0.08, -0.03, 0.06) * intensity * sin(t + uv.x * 6.0);
	vec2 p = uv - 0.5;
	float v = 1.0 - smoothstep(0.15, 0.70, dot(p, p));
	col.rgb *= mix(1.0, v, 0.9 * intensity);

	COLOR = col;
}
"""
		_sanity_fx_mat = ShaderMaterial.new()
		_sanity_fx_mat.shader = sh
		_sanity_fx_rect.material = _sanity_fx_mat

	_sanity_fx_rect.visible = false

# =========================
#         INPUT HANDLING
# =========================
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		_release_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_capture_mouse()

	if mouse_captured and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_rotate_look(mm.relative)

	# Freefly toggle
	if can_freefly and event.is_action_pressed(input_freefly):
		freeflying = not freeflying
		if freeflying:
			_enable_freefly()
		else:
			_disable_freefly()

	# DROP
	if event.is_action_pressed(input_drop):
		request_drop_rpc()

	# USE/ATTACK (server-authoritative via ItemManager)
	if event.is_action_pressed(input_use_attack):
		_try_use_attack()

func _try_use_attack() -> void:
	if not _is_holding_item():
		return

	var now: float = Time.get_ticks_msec() * 0.001
	if now - _last_attack_time < attack_cooldown:
		return
	_last_attack_time = now

	# Local feel (optional). The real "everyone sees it" comes from ItemManager.apply_use_attack.
	_play_attack_local()

	# Tell server to broadcast animation on the held item.
	request_use_attack_rpc()

func _play_attack_local() -> void:
	# Prefer player's AnimationPlayer if configured
	if _swing_anim != null and _swing_anim.has_animation(String(attack_anim_name)):
		_swing_anim.stop()
		_swing_anim.play(String(attack_anim_name))
		return

	# Fallback: AnimationPlayer on the held item (your bat case)
	var held: Node = _get_held_node()
	if held != null:
		var held_anim: AnimationPlayer = held.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if held_anim != null and held_anim.has_animation(String(attack_anim_name)):
			held_anim.stop()
			held_anim.play(String(attack_anim_name))

# =========================
#      FRAME / PHYSICS
# =========================
func _process(_dt: float) -> void:
	if not is_multiplayer_authority():
		return
	if _sanity_fx_mat != null and _sanity_fx_rect != null:
		_sanity_fx_rect.visible = sanity_fx_intensity > 0.01
		_sanity_fx_mat.set_shader_parameter("intensity", sanity_fx_intensity)

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if is_multiplayer_authority():
		_physics_authority(delta)
		_net_maybe_send_state()
		return

	_net_interpolate_remote()

func _physics_authority(delta: float) -> void:
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() * freefly_speed * delta
		move_and_collide(motion)
		return

	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

	move_speed = sprint_speed if (can_sprint and Input.is_action_pressed(input_sprint)) else base_speed
	move_speed *= tether_speed_mult

	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

		if tether_hard_lock and move_dir != Vector3.ZERO:
			var to_partner: Vector3 = tether_partner_pos - global_position
			to_partner.y = 0.0
			if to_partner.length() > 0.001:
				var toward_dir: Vector3 = to_partner.normalized()
				var toward_amt: float = move_dir.dot(toward_dir)
				if toward_amt <= 0.0:
					move_dir = Vector3.ZERO
				else:
					move_dir = toward_dir * toward_amt

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

# =========================
#        NET MOVEMENT
# =========================
func _net_maybe_send_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null:
		return
	if mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / maxf(net_send_rate_hz, 1.0)
	if now - _net_last_send_time < min_interval:
		return

	_net_last_send_time = now
	rpc("_net_state_from_client", global_transform)

func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return
	global_transform = global_transform.interpolate_with(_net_target_transform, net_lerp_alpha)

@rpc("any_peer", "call_local", "unreliable")
func _net_state_from_client(new_transform: Transform3D) -> void:
	if multiplayer.is_server():
		if not is_multiplayer_authority():
			_net_set_target(new_transform)
		rpc("_net_apply_state", new_transform)
	else:
		if not is_multiplayer_authority():
			_net_set_target(new_transform)

@rpc("any_peer", "unreliable")
func _net_apply_state(new_transform: Transform3D) -> void:
	if is_multiplayer_authority():
		return
	_net_set_target(new_transform)

func _net_set_target(new_transform: Transform3D) -> void:
	_net_target_transform = new_transform
	_net_has_target = true

# =========================
#   MULTIPLAYER FOOTSTEPS
# =========================
func _get_local_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	var my_id: int = multiplayer.get_unique_id()
	for p in players:
		if p is Node3D:
			var p3d := p as Node3D
			if p3d.get_multiplayer_authority() == my_id:
				return p3d
	return null

func _play_footstep_audio() -> void:
	if footstep == null:
		return

	if not multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			footstep.pitch_scale = randf_range(0.85, 1.25)
			footstep.play()
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if is_multiplayer_authority():
			footstep.pitch_scale = randf_range(0.85, 1.25)
			footstep.play()
		return

	var now: float = Time.get_ticks_msec() * 0.001
	if now - _last_footstep_time < footstep_min_interval:
		return
	_last_footstep_time = now

	if not is_multiplayer_authority():
		return

	footstep.pitch_scale = randf_range(0.85, 1.25)
	footstep.play()
	rpc("_rpc_footstep_event", global_position)

@rpc("any_peer", "call_local", "unreliable")
func _rpc_footstep_event(step_pos: Vector3) -> void:
	if is_multiplayer_authority():
		return
	if footstep == null:
		return

	var local_player := _get_local_player()
	if local_player == null:
		return

	var dist := local_player.global_position.distance_to(step_pos)
	if dist > footstep_hear_radius:
		return

	var prev_pos := footstep.global_position
	footstep.global_position = step_pos
	footstep.pitch_scale = randf_range(0.85, 1.25)
	footstep.play()
	footstep.global_position = prev_pos

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
	if not InputMap.has_action(input_drop):
		push_error("Missing action: " + input_drop + " (bind it to G)")
	if not InputMap.has_action(input_use_attack):
		push_error("Missing action: " + input_use_attack + " (bind it in InputMap)")

# =========================
#  SERVER -> CLIENT RPCs
# =========================
@rpc("any_peer", "call_local", "reliable")
func server_set_inventory(new_inventory: Array[StringName]) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != SERVER_ID:
		return
	if sender == 0 and not multiplayer.is_server():
		return

	inventory = new_inventory.duplicate()
	inventory_changed.emit(inventory)

@rpc("any_peer", "call_local", "unreliable")
func server_show_hint(msg: String, seconds: float = 1.25) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != SERVER_ID:
		return
	if sender == 0 and not multiplayer.is_server():
		return
	if not is_multiplayer_authority():
		return
	_show_hint_temp(msg, seconds)

# =========================
#   PICKUP/DROP/USE ROUTED THROUGH ItemManager
# =========================
func request_pickup_rpc(item_path: NodePath) -> void:
	var im := _get_item_manager()
	if im == null:
		push_error("ItemManager not found in current_scene (direct or nested). Check its name and that clients load it too.")
		return

	if multiplayer.is_server():
		im.request_pickup(item_path)
	else:
		im.rpc_id(SERVER_ID, "request_pickup", item_path)

func request_drop_rpc() -> void:
	var im := _get_item_manager()
	if im == null:
		push_error("ItemManager not found in current_scene (direct or nested).")
		return

	var item_key: NodePath = _get_held_item_key()
	if String(item_key) == "":
		return

	if multiplayer.is_server():
		im.request_drop(item_key)
	else:
		im.rpc_id(SERVER_ID, "request_drop", item_key)

func request_use_attack_rpc() -> void:
	var im := _get_item_manager()
	if im == null:
		push_error("ItemManager not found in current_scene (direct or nested).")
		return

	var item_key: NodePath = _get_held_item_key()
	if String(item_key) == "":
		return

	if multiplayer.is_server():
		im.request_use_attack(item_key)
	else:
		im.rpc_id(SERVER_ID, "request_use_attack", item_key)
