extends Node3D
@onready var quest_marker_: Node3D = $"../QuestMarkerBlue"

@onready var quest_anim: AnimationPlayer = $"../QuestMarker!/AnimationPlayer"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var dog: Node3D = $"."

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_player.play("DogWalk")
	
	questHub.iteration_changed.connect(iterationChange)
	questHub.campbellQuest.connect(campbellProgression)
	quest_marker_.visible = false
	
	match(questHub.campbellProg):
		0:
			quest_marker_.visible = false
			dog.visible = true
		1:
			quest_marker_.visible = true
			dog.visible = false
		2:
			quest_marker_.visible = false
			dog.visible = false
		3:
			quest_marker_.visible = true
			dog.visible = false
		4:
			quest_marker_.visible = false
			dog.visible = false
	#if questMarker.campbells == true:
		#visible = false
		#quest_marker_.visible = true


		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	#if questHub.
	
	

func iterationChange(value: int):
	
	#Dog disappears at iteration 3 (2), "teleports" to random location (house near abigail)
	if value >= 2 && questHub.campbellProg == 0:
		#questHub.campbellProg = 1
		#print("DOG DISAPPEARS!")
		#quest_anim.play("Move_blue")
		#questHub.campbellTrigger()
		
		dog.visible = false
		quest_marker_.visible = true
		#questMarker.campbells = true
		
	else:
		dog.visible = true
	
func campbellProgression(value: int):
	
	#bro this system is so good bro i stfg this shit is so ass
	match(questHub.campbellProg):
		0:
			quest_marker_.visible = false
			dog.visible = true
		1:
			quest_marker_.visible = true
			dog.visible = false
		2:
			quest_marker_.visible = false
			dog.visible = false
		3:
			quest_marker_.visible = true
			dog.visible = false
		4:
			quest_marker_.visible = false
			dog.visible = false
	
