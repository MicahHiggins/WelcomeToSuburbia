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





func iterationChange(value: int):
	print(value)
	if value == 2:
		quest_marker_.visible = true
		collision_shape_3d.set_deferred("disabled", false) 
		
	elif value > 3:
		queue_free()
		print("itereationChanged! Heartbeat! Error/DQ!")
			
func _on_body_entered(body: Node3D) -> void:
	if  body.is_in_group("player") && body.is_multiplayer_authority():
		
		#isaac is talked too during his quest! change to phase 3 in isaac questline!
		
		GlobalVariables.isaac_quest_progression = 3
		questHub.isaacTrigger()
		
		quest_marker_.visible = false
		GlobalVariables.heart_beat = true
		
		#forgot what this is for...
		GlobalVariables.gameStart.emit()
		
		GlobalVariables.iterations += 1
		questHub.it_change()
		queue_free()
		
	
