extends Node3D
@onready var houses: Node3D = $Houses
@onready var roads: Node3D = $Roads

#@onready var patrol_path: PatrolPath = $patrol_path

const PATROL_PATH = preload("res://aidan_stuff/patrol_path.tscn")
#"res://NPC/npc_bob.tscn"

#var extra_bob = 0
var patrol_path
var bob_count

var entered = false
var exited = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	houses.visible = false
	roads.visible = false
	
	
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	bob_count = get_tree().get_nodes_in_group("your_group_name").size()


func _on_area_3d_body_entered(body: Node3D) -> void:
	if entered == false:
		patrol_path = PATROL_PATH.instantiate()
		roads.visible = true
		houses.visible = true
		add_child(patrol_path)
		patrol_path.position = Vector3(0, 0, 0)
		print("2 BOBS?")
		entered = true
		exited = false


	


func _on_area_3d_body_exited(body: Node3D) -> void:
	if exited == false:
		roads.visible = false
		houses.visible = false
		patrol_path.queue_free()
		print("NO BOBS?")
		exited = true
		entered = false
	
