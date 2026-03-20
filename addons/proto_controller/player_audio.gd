extends Node3D

@onready var heart_beat: AudioStreamPlayer3D = $heartBeat

var reverb_bus_index: int



func _ready()->void:
	reverb_bus_index = AudioServer.get_bus_index("Reverb")
	print("Reverb: ", reverb_bus_index)

func _process(delta: float) -> void:
	if GlobalVariables.heart_beat == true:
		print("HeartBeat Play!")
		GlobalVariables.heart_beat = false
		heart_beat.playing = true
		await get_tree().create_timer(10).timeout
		heart_beat.playing = false
