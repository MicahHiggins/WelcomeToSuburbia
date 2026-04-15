extends Node3D

@onready var heart_beat: AudioStreamPlayer3D = $heartBeat

var reverb_bus_index: int
@onready var talk_1: AudioStreamPlayer = $Talk1
@onready var talk_2: AudioStreamPlayer = $Talk2
@onready var talk_3: AudioStreamPlayer = $Talk3
@onready var talk_4: AudioStreamPlayer = $Talk4



func _ready()->void:
	questHub.talkingNpc.connect(talkAudio)
	reverb_bus_index = AudioServer.get_bus_index("Reverb")
	print("Reverb: ", reverb_bus_index)

func _process(delta: float) -> void:
	if GlobalVariables.heart_beat == true:
		print("HeartBeat Play!")
		GlobalVariables.heart_beat = false
		heart_beat.playing = true
		await get_tree().create_timer(10).timeout
		heart_beat.playing = false
		
func talkAudio(value: int):
	print("YIPEE?")
	var num = randi_range(0, 3)
	
	match(num):
		0: 
			talk_1.pitch_scale 
			talk_1.play()
		1:
			talk_2.play()
		2: 
			talk_3.play()
		3:
			talk_4.play()
			
			
	
