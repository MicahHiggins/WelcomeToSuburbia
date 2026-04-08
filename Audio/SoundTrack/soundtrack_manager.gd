extends Node
@onready var track_3: AudioStreamPlayer = $track3




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



	


func _on_sound_scape_audio_play_track_3() -> void:
	track_3.play()
