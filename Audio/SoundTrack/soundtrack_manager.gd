extends Node
@onready var track_3: AudioStreamPlayer = $track3
@onready var wttn_1: AudioStreamPlayer = $Track1/WTTN1
@onready var wttn_2: AudioStreamPlayer = $Track1/WTTN2
@onready var wttn_3: AudioStreamPlayer = $Track1/WTTN3


@onready var timer: Timer = $Track1/Timer



func randNum():
	return randi_range(1, 3)
	
func randNum_start():
	return randf_range(10, 15)
	



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(playTune)
	

func playTune(value: int):
	
	print("GOTTEN PLAYTUNE!")
	
	var num = randNum_start()
	print("playTune", num)
	await get_tree().create_timer(num).timeout
	
	match(GlobalVariables.iterations):
		0:
			wttn_1.play()
		1:
			wttn_1.play()
		2:
			wttn_2.play()
		3:
			wttn_2.play()
		4:
			wttn_3.play()
		5:
			wttn_3.play()
		6: 
			wttn_3.play()
			
			

func _on_sound_scape_audio_play_track_3() -> void:
	track_3.play()
