extends CharacterBody3D
# --------------------------------------------
# Generic 3D pickup item with:
#  - Outline that shows when hovered by a ray
#  - Simple gravity when on the ground
#  - "Held" state (used when a Player picks it up)
#  - Area3D used as the raycast target / hit shape
# --------------------------------------------

# Mesh that should glow / outline when hovered
@onready var outline_mesh: MeshInstance3D = $batclean_low2/batclean_low/MeshInstance3D

# Area used as the thing the RayCast3D actually collides with
# (usually a simple shape around the object)
@onready var interact_area: Area3D = $Area3D

# Local state flags
var _hovered := false    # true while the ray is pointing at this pickup
var _held := false       # true while a player is holding this item

# Gravity strength for this body (pulled from project settings)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


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
	# Called by Player code when the item is picked up / dropped.
	_held = v

	# When held, outline is always off
	if outline_mesh:
		outline_mesh.visible = false

	# While held, this body should not simulate physics / gravity
	if v:
		velocity = Vector3.ZERO


func interact() -> void:
	# Optional method if any direct interaction is needed.
	# Not strictly required by the pickup system, but can be wired up.
	print("Bat interacted with!")
	set_held(true)


func _physics_process(delta: float) -> void:
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
