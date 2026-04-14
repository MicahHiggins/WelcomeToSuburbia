extends Node3D


@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var quest_marker_: questMarker = $"QuestMarker!"

signal heart_beat

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision_shape_3d.set_deferred("disabled", true)
	questHub.iteration_changed.connect(iterationChange)
	GlobalVariables.gameStart.connect(_on_body_entered)
	quest_marker_.visible = false
	
	match(GlobalVariables.isaac_quest_progression):
		0:
			quest_marker_.visible = false
		1: 
			quest_marker_.visible = true
		_:
			quest_marker_.visible = false
			





func iterationChange(value: int):
	print("HEARTBEAT:", GlobalVariables.isaac_quest_progression)
	if GlobalVariables.isaac_quest_progression == 1:
		quest_marker_.visible = true
		collision_shape_3d.set_deferred("disabled", false) 
		
	if GlobalVariables.isaac_quest_progression > 1:
		queue_free()
		print("itereationChanged! Heartbeat! Error/DQ!")
			
func _on_body_entered(body: Node3D) -> void:
	if  body.is_in_group("player") && body.is_multiplayer_authority():
		
		questHub.isaacTrigger()
		questHub.it_change()
		
		quest_marker_.visible = false
		GlobalVariables.heart_beat = true
		
		#forgot what this is for...
		GlobalVariables.gameStart.emit()
		
	#
		#questHub.it_change()
		queue_free()
		
	
