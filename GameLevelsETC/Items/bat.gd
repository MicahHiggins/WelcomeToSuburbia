extends CharacterBody3D

@onready var batclean_low_2: Node3D = $batclean_low2
@onready var outlineMesh: MeshInstance3D = $batclean_low2/batclean_low
# NEW: direct path to your collider
@onready var collision_shape: CollisionShape3D = $"batclean_low2/batclean_low/StaticBody3D/CollisionShape3D"

var selected = false
var outlineWidth = 0.3
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var player 

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and selected:
		player.pick_up_object(self)
	

func _ready():
	player = get_tree().get_first_node_in_group("player")
	player.interact_object.connect(_set_selected)
	
	outlineMesh.visible = false
	

func _process(delta):
	# replaced %CollisionShape3D with the explicit path reference
	if collision_shape:
		collision_shape.disabled = player == get_parent()
	outlineMesh.visible = selected and player == get_parent()
	
	if selected:
		batclean_low_2.position.y = outlineWidth
	else:
		batclean_low_2.position.y = 0
		
func _physics_process(delta: float) -> void:
	if player == get_parent():
		return 
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	move_and_slide()

func _set_selected(object):
	selected = self == object
