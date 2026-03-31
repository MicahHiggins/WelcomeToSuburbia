extends Node3D

@onready var quest_marker_: questMarker = $"../QuestMarker!"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChange)
	#questHub.questTalk.connect(talkedTo)
	quest_marker_.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func iterationChange(value: int):
	print("Isaaac: Marker!")
	if value == 5:
		quest_marker_.visible = true
		

	
