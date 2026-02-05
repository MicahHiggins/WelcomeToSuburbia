extends Node3D
@onready var houses: Node3D = $Houses
#@onready var patrol_path: PatrolPath = $patrol_path

const PATROL_PATH = preload("res://aidan_stuff/patrol_path.tscn")


var patrol_path
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	houses.visible = false
	patrol_path = PATROL_PATH.instantiate()
	
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_area_3d_body_entered(body: Node3D) -> void:
	houses.visible = true
	add_child(patrol_path)
	patrol_path.position = Vector3(0, 0, 0)
	
