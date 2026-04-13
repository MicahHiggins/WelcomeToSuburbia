extends Node3D

@onready var peek_anim: AnimationPlayer = $peekAnim
@onready var quest_marker_: questMarker = $"QuestMarker!"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChanged)
	questHub.isaacQuest.connect(isaacProgression)
	quest_marker_.visible = false
	
	match(GlobalVariables.isaac_quest_progression):
		4:
			quest_marker_.visible = true
		5: 
			quest_marker_.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func isaacProgression(value: int):
	if GlobalVariables.isaac_quest_progression == 3:
		GlobalVariables.isaac_quest_progression = 4
		questHub.isaacTrigger()
		
	if GlobalVariables.isaac_quest_progression == 4:
		quest_marker_.visible = true
		
		
	
	
	
		
		
		
		
	
	
func iterationChanged(value: int):
	pass

func _on_area_4_quest_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") && body.is_multiplayer_authority():
		peek_anim.play("peek")
		if GlobalVariables.isaac_quest_progression == 4:
			GlobalVariables.isaac_quest_progression = 5
			quest_marker_.visible = false
			questHub.isaacTrigger()
			
