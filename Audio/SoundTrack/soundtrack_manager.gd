extends Node
@onready var track_3: AudioStreamPlayer = $track3
@onready var wttn_1: AudioStreamPlayer = $Track1/WTTN1
@onready var wttn_2: AudioStreamPlayer = $Track1/WTTN2
@onready var wttn_3: AudioStreamPlayer = $Track1/WTTN3


@onready var timer: Timer = $Track1/Timer


var toggle_menu_music := false


func randNum():
	return randi_range(1, 3)
	
func randNum_start():
	return randf_range(10, 15)
	



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(playTune)
	GlobalVariables.menuMusic.connect(menuMusicPlay)
	

func menuMusicPlay():
	
	if toggle_menu_music == false:
		wttn_1.play()
		toggle_menu_music = true
	
	else:
		wttn_1.stop()
	

func playTune(value: int):
	
	wttn_1.stop()
	wttn_2.stop()
	wttn_3.stop()
	
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
		_:
			wttn_3.play()
			
			

func _on_sound_scape_audio_play_track_3() -> void:
	track_3.play()
