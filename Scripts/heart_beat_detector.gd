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
	if value == 1:
		quest_marker_.visible = true
		#print("itrationChanged! Heartbeat!")
		#questHub.it_change()
		
		
		collision_shape_3d.set_deferred("disabled", false) 
	elif value > 3:
		queue_free()
		print("itereationChanged! Heartbeat! Error/DQ!")
			
func _on_body_entered(body: Node3D) -> void:
	if  body.is_in_group("player"):
		GlobalVariables.iterations += 1
		print("Does it change?")
		quest_marker_.visible = false
		GlobalVariables.gameStart.emit()
		questHub.it_change()
		GlobalVariables.heart_beat = true
	
