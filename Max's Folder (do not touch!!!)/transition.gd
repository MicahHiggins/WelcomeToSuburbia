extends Area3D

@onready var quest_marker_: questMarker = $"QuestMarker!"
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.isaacQuest.connect(isaacTrigger)
	quest_marker_.visible = false
	collision_shape_3d.set_deferred("disabled", true)
	
	match(GlobalVariables.isaac_quest_progression):
		4:
			quest_marker_.visible = true
		_:
			quest_marker_.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



func isaacTrigger(value: int):
	if GlobalVariables.isaac_quest_progression == 4:
		quest_marker_.visible = true
		collision_shape_3d.set_deferred("disabled", false) 
		
	


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("SUCCESS!!!!")
