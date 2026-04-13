extends Node3D

class_name isaacQuest




@onready var quest_marker_: questMarker = $"../QuestMarker!"


static var isaacQToggle := false
static var ISAACQUEST_TURN_IN = 3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	questHub.iteration_changed.connect(iterationChange)
	questHub.isaacQuest.connect(isaacProgress)
	
	
	#4 saving progression when loaded in
	match(GlobalVariables.isaac_quest_progression):
		0: 
			quest_marker_.visible = false
		1:
			quest_marker_.visible = true
		2: 
			quest_marker_.visible = false
		5:
			quest_marker_.visible = true
		6: 
			quest_marker_.visible = false
		
			
			


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func isaacProgress(value: int):
	print("ISACC QUEST MARKER NOT WORKING?: ", GlobalVariables.isaac_quest_progression)
	if value >= 1 && GlobalVariables.isaac_quest_progression == 1:
		print("Is this thing on?")
		GlobalVariables.isaac_quest_progression = 2
		quest_marker_.visible = false
	
	if GlobalVariables.isaac_quest_progression == 5:
		quest_marker_.visible = true
		
		
		#QUEST BRUH
		
	
	if GlobalVariables.isaac_quest_progression == 6:
		quest_marker_.visible = false
		
		

func iterationChange(value: int):
	print("Isaaac: Marker!")
	if value == 1:
		isaacQToggle = true
		GlobalVariables.isaac_quest_progression = 1
		quest_marker_.visible = true
		

		

	
