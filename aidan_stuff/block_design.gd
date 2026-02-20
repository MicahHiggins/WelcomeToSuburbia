extends Node3D

@onready var houses: Node3D = $Houses
@onready var roads: Node3D = $Roads

const PATROL_BUNDLE: PackedScene = preload("res://aidan_stuff/patrol_path.tscn")
const PATROL_BUNDLE_ABIGAIL: PackedScene = preload("res://NPC/patrol_bundel_abigail.tscn")
const PATROL_BUNDLE_CAMPBELL: PackedScene = preload("res://NPC/patrol_bundle_campbells.tscn")

# we want all npcs to spawn on this block, so we keep separate instances
var patrol_instance_bob: Node3D = null
var patrol_instance_abigail: Node3D = null
var patrol_instance_campbell: Node3D = null

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
	
	GlobalVariables.iterations = GlobalVariables.iterations + 1

	# Spawn Bob bundle
	if patrol_instance_bob == null or not is_instance_valid(patrol_instance_bob):
		patrol_instance_bob = PATROL_BUNDLE.instantiate() as Node3D
		add_child(patrol_instance_bob)

		# Move the entire bundle (NPC + PatrolPath + markers) with this block
		patrol_instance_bob.global_transform = global_transform

	# Spawn Abigail bundle
	if patrol_instance_abigail == null or not is_instance_valid(patrol_instance_abigail):
		patrol_instance_abigail = PATROL_BUNDLE_ABIGAIL.instantiate() as Node3D
		add_child(patrol_instance_abigail)

		# Move the entire bundle (NPC + PatrolPath + markers) with this block
		patrol_instance_abigail.global_transform = global_transform

	# Spawn Campbell bundle
	if patrol_instance_campbell == null or not is_instance_valid(patrol_instance_campbell):
		patrol_instance_campbell = PATROL_BUNDLE_CAMPBELL.instantiate() as Node3D
		add_child(patrol_instance_campbell)

		# Move the entire bundle (NPC + PatrolPath + markers) with this block
		patrol_instance_campbell.global_transform = global_transform

func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if not entered:
		return
	entered = false

	houses.visible = false
	roads.visible = false

	# Despawn Bob bundle
	if patrol_instance_bob != null and is_instance_valid(patrol_instance_bob):
		patrol_instance_bob.queue_free()
	patrol_instance_bob = null

	# Despawn Abigail bundle
	if patrol_instance_abigail != null and is_instance_valid(patrol_instance_abigail):
		patrol_instance_abigail.queue_free()
	patrol_instance_abigail = null

	# Despawn Campbell bundle
	if patrol_instance_campbell != null and is_instance_valid(patrol_instance_campbell):
		patrol_instance_campbell.queue_free()
	patrol_instance_campbell = null
