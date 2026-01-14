
extends CharacterBody3D

@onready var outline_mesh: MeshInstance3D = $batclean_low2/batclean_low/MeshInstance3D
@onready var interact_area: Area3D = $Area3D

var _hovered := false
var _held := false

# Gravity for the bat
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# So the player / ray can find this as a pickup
	add_to_group("pickup")

	# Outline off by default
	if outline_mesh:
		outline_mesh.visible = false

	# Make sure the InteractArea is on a layer your RayCast3D can see
	# For now: put it on layer 4
	if interact_area:
		interact_area.set_collision_layer_value(4, true)
		# We don't need InteractArea to detect anything itself
		interact_area.collision_mask = 0

func set_hovered(v: bool) -> void:
	_hovered = v
	if outline_mesh and not _held:
		outline_mesh.visible = v

func set_held(v: bool) -> void:
	_held = v
	if outline_mesh:
		outline_mesh.visible = false

	# While held, we freeze physics
	if v:
		velocity = Vector3.ZERO

func interact() -> void:
	# Optional: this is what happens when you press interact on the bat
	print("Bat interacted with!")
	set_held(true)

func _physics_process(delta: float) -> void:
	if _held:
		# Do not simulate gravity while held
		velocity = Vector3.ZERO
		return

	# Simple gravity so bat falls to the ground
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# When on floor, don't keep sliding forever
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)

	move_and_slide()
