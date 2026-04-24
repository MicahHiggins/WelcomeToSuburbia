extends Node3D

@onready var peek_anim: AnimationPlayer = $peekAnim
@onready var quest_marker_: questMarker = $"QuestMarker!"

@onready var jumpscare_1: AudioStreamPlayer3D = $jumpscare1

#@onready var audio_stream_player_3d: AudioStreamPlayer3D = $AudioStreamPlayer3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChanged)
	questHub.isaacQuest.connect(isaacProgression)
	quest_marker_.visible = false
	
	match(GlobalVariables.isaac_quest_progression):
		2:
			quest_marker_.visible = true
		3: 
			quest_marker_.visible = false
		_:
			quest_marker_.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func isaacProgression(value: int):
	#if GlobalVariables.isaac_quest_progression == 2:
		#GlobalVariables.isaac_quest_progression = 4
		#questHub.isaacTrigger()
		
	if GlobalVariables.isaac_quest_progression == 2:
		quest_marker_.visible = true
	
	if GlobalVariables.isaac_quest_progression == 3:
		quest_marker_.visible = false
		
		
	
	
	
		
		
		
		
	
	
func iterationChanged(value: int):
	pass


func _on_area_4_quest_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") && body.is_multiplayer_authority():
		peek_anim.play("peek")
		if GlobalVariables.isaac_quest_progression == 2:
			
			#await get_tree().create_timer(1.0).timeout
			jumpscare_1.play()
			
			#GlobalVariables.isaac_quest_progression = 5
			
			questHub.isaacTrigger()
			#quest_marker_.visible = false
			
