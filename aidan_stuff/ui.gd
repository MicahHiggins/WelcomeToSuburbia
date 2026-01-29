extends CanvasLayer

@onready var item1: Label = $Item1Label
@onready var item2: Label = $Item2Lable

# Arrow UI (matches your tree)
@onready var root_control: Control = $Control
@onready var partner_arrow: TextureRect = $Control/PartnerArrow
@onready var distance_label: Label = $Control/distance

@export var hide_when_close_m: float = 1.5
@export var show_distance: bool = true

# Layout tuning (pixels) — not used here (you said you'll position it yourself)
@export var arrow_top_margin: float = 22.0
@export var distance_gap: float = 6.0

# DEBUG
@export var debug_force_show_arrow: bool = false

# If tether data isn't being set, we can still find the other player reliably
@export var prefer_scan_for_partner: bool = true

var player: CharacterBody3D
var cam: Camera3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D

	# UI should only be visible & updating for the locally controlled player.
	if player == null or not player.is_multiplayer_authority():
		visible = false
		set_process(false)
		return

	visible = true

	# Cache camera
	cam = player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		var found: Node = player.find_child("Camera3D", true, false)
		cam = found as Camera3D

	# Make HUD NOT steal the mouse (pause menu buttons need this)
	_make_hud_ignore_mouse()

	_update_labels()

func _make_hud_ignore_mouse() -> void:
	if root_control != null:
		root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if partner_arrow != null:
		partner_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if distance_label != null:
		distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	_update_labels()
	_update_partner_arrow()

func _update_labels() -> void:
	if player == null:
		return

	var inv: Array[StringName] = player.inventory
	item1.text = ""
	item2.text = ""

	if inv.size() >= 1:
		item1.text = String(inv[0])
	if inv.size() >= 2:
		item2.text = String(inv[1])

# -------------------------
# Partner finding helper
# -------------------------
func _get_other_player_node() -> Node3D:
	if not multiplayer.has_multiplayer_peer():
		return null

	var my_id: int = multiplayer.get_unique_id()
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Node3D
		if p == null:
			continue
		if p.get_multiplayer_authority() != my_id:
			return p
	return null

func _update_partner_arrow() -> void:
	if player == null or partner_arrow == null or cam == null:
		if partner_arrow != null:
			partner_arrow.visible = false
		if distance_label != null:
			distance_label.visible = false
		return

	# Choose partner position
	var partner_pos: Vector3 = Vector3.ZERO

	# Prefer scanning for the other player (works even if tether_partner_pos is never set)
	if prefer_scan_for_partner:
		var other: Node3D = _get_other_player_node()
		if other != null:
			partner_pos = other.global_position

	# Fallback to your tether state if scan didn't find anyone
	if partner_pos == Vector3.ZERO:
		partner_pos = player.tether_partner_pos

	# Hide if not set yet (unless debug)
	if partner_pos == Vector3.ZERO and not debug_force_show_arrow:
		partner_arrow.visible = false
		if distance_label != null:
			distance_label.visible = false
		return

	# Debug: fake a partner 10m in front so you can see rotation behavior
	if partner_pos == Vector3.ZERO and debug_force_show_arrow:
		partner_pos = player.global_position + (-cam.global_transform.basis.z).normalized() * 10.0

	# Flatten to horizontal direction (no up/down)
	var to_partner: Vector3 = partner_pos - player.global_position
	to_partner.y = 0.0

	var dist: float = to_partner.length()
	if dist < hide_when_close_m and not debug_force_show_arrow:
		partner_arrow.visible = false
		if distance_label != null:
			distance_label.visible = false
		return

	partner_arrow.visible = true

	# Distance text
	if distance_label != null:
		distance_label.visible = show_distance
		if show_distance:
			distance_label.text = "%dm" % int(round(dist))

	if dist <= 0.001:
		return

	var dir: Vector3 = to_partner / dist

	# Camera forward/right on horizontal plane
	var cam_basis: Basis = cam.global_transform.basis
	var cam_forward: Vector3 = -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	var cam_right: Vector3 = cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	# Project direction into camera 2D plane:
	# x = right, y = forward
	var x: float = dir.dot(cam_right)
	var y: float = dir.dot(cam_forward)

	# IMPORTANT FIX:
	# Godot 2D rotation is clockwise (because +Y is down), so we invert y.
	# Arrow art points RIGHT at rotation = 0.
	var angle: float = atan2(-y, x)
	partner_arrow.rotation = angle
