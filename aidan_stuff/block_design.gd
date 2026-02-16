extends Node3D

@onready var houses: Node3D = $Houses
@onready var roads: Node3D = $Roads

const PATROL_BUNDLE: PackedScene = preload("res://aidan_stuff/patrol_path.tscn")

var patrol_instance: Node3D = null
var entered := false

func _ready() -> void:
	houses.visible = false
	roads.visible = false

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if entered:
		return
	entered = true

	houses.visible = true
	roads.visible = true

	if patrol_instance == null or not is_instance_valid(patrol_instance):
		patrol_instance = PATROL_BUNDLE.instantiate() as Node3D
		add_child(patrol_instance)

		# Move the entire bundle (NPC + PatrolPath + markers) with this block
		patrol_instance.global_transform = global_transform

func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if not entered:
		return
	entered = false

	houses.visible = false
	roads.visible = false

	if patrol_instance != null and is_instance_valid(patrol_instance):
		patrol_instance.queue_free()
	patrol_instance = null
