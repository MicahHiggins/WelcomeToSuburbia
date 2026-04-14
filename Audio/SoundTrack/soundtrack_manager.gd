extends Node
@onready var track_3: AudioStreamPlayer = $track3
@onready var wttn_1: AudioStreamPlayer = $Track1/WTTN1
@onready var wttn_2: AudioStreamPlayer = $Track1/WTTN2
@onready var wttn_3: AudioStreamPlayer = $Track1/WTTN3





func randNum():
	return randi_range(1, 3)
	



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(playTune)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



	
func playTune(value: int):
	print("Play Tune!")
	match(value):
		0:
			wttn_1.play()
		1:
			wttn_1.play()
		3:
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
