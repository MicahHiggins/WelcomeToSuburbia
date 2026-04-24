extends Node3D
@onready var jumpscare: AnimationPlayer = $"../jumpscare"
@onready var audio_stream_player_3d: AudioStreamPlayer3D = $"../jumpscare/AudioStreamPlayer3D"




var jumpscared_played := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChanged)
	questHub.isaacQuest.connect(isaacProgression)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_talk_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") && body.is_multiplayer_authority():
		if jumpscared_played == false:
			jumpscared_played = true
			audio_stream_player_3d.play()
			await get_tree().create_timer(0.2).timeout
			jumpscare.play("duck")
		


#func _on_jumpscare_animation_finished(anim_name: StringName) -> void:
	#if anim_name == "duck":
func isaacProgression(value: int):
	pass
		
func iterationChanged(value: int):
	pass
