# PickupItem.gd
extends CharacterBody3D

# Change these to your actual nodes
@onready var outline_mesh: MeshInstance3D = $batclean_low2/batclean_low/MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _hovered := false
var _held := false

# Use 3D gravity (your earlier code accidentally used 2D)
var _g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))

func _ready() -> void:
	add_to_group("pickup")

	# Visibility default
	if outline_mesh:
		outline_mesh.visible = false

	# Ensure item is on world (1) and pickup (4) layers so it sits on ground and ray can hit it
	if has_method("set_collision_layer_value"):
		# character bodies use set_collision_layer_value in Godot 4
		set_collision_layer_value(1, true) # world
		set_collision_layer_value(4, true) # pickup layer
		# collide with world
		set_collision_mask_value(1, true)
	else:
		# Fallback if using custom body types
		collision_layer = 1 | (1 << 4)
		collision_mask = 1

func set_hovered(v: bool) -> void:
	_hovered = v
	# Only show outline if not currently held by a player
	if outline_mesh:
		outline_mesh.visible = _hovered and not _held

func set_held(v: bool) -> void:
	_held = v
	# While held, hide outline and disable collision
	if outline_mesh:
		outline_mesh.visible = false
	if collision_shape:
		collision_shape.disabled = v

func _physics_process(delta: float) -> void:
	if _held:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= _g * delta

	move_and_slide()
