extends CharacterBody3D

@onready var outlineMesh = $batclean_low


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
var selected = false
var outlineWidth =0.5
var player


func _ready():
	return
	#player = get_tree().get_first_node_in_group("player")
	#player.interact_object.connect(_set_selected)
	#outlineMesh.visible = false
	

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interaction") and selected:
		player.pick_up_object(self)
	

func _process(delta: float) -> void:
	%CollisionShape3D.disabled = player = get_parent()
	outlineMesh.visible = selected and not player = get_parent()
