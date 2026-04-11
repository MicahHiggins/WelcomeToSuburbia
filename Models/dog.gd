extends Node3D
@onready var quest_marker_: questMarker = $"../QuestMarker!"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var dog: Node3D = $"."

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_player.play("DogWalk")
	questHub.iteration_changed.connect(iterationChange)
	questHub.questTalk.connect(talkedTo)
	quest_marker_.visible = false
	if questMarker.campbells == true:
		visible = false
		quest_marker_.visible = true


		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	#if questHub.
	
	

func iterationChange(value: int):
	
	#Dog disappears at iteration 3 (2), "teleports" to random location (house near abigail)
	if value >= 2:
		dog.visible = false
		quest_marker_.visible = true
		questMarker.campbells = true
		
	else:
		dog.visible = true
	
func talkedTo(value: int):
	print("Talked! Marker!")
	quest_marker_.visible = false
