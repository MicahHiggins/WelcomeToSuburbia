extends Node


class_name soundScape

@onready var birds: Node = $Birds
@onready var wind: Node = $Wind
@onready var children: Node = $children

@onready var bird_1: AudioStreamPlayer = $Birds/bird1
@onready var bird_2: AudioStreamPlayer = $Birds/bird2
@onready var bird_3: AudioStreamPlayer = $Birds/bird3
@onready var bird_4: AudioStreamPlayer = $Birds/bird4

@onready var wind_1: AudioStreamPlayer = $Wind/wind1
@onready var wind_2: AudioStreamPlayer = $Wind/wind2
@onready var wind_3: AudioStreamPlayer = $Wind/wind3
@onready var wind_4: AudioStreamPlayer = $Wind/wind4

@onready var child_1: AudioStreamPlayer = $children/child1
@onready var child_2: AudioStreamPlayer = $children/child2
@onready var child_3: AudioStreamPlayer = $children/child3
@onready var child_4: AudioStreamPlayer = $children/child4

@onready var soundArr = [bird_1, bird_2, bird_3, bird_4, wind_1, wind_2, wind_3, wind_4, child_1, child_2, child_3, child_4]
var sound


var soundToggle := false


signal playTrack3

#const for iteration range

#returns range of floats for audio maniuplation
func randNum(range1: float, range2: float):
	return randf_range(range1, range2)

func randomNumTransition():
	return randi_range(2, 10)
	
	
func randSound():
	return randi_range(0, 11)
	
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GlobalVariables.cellarLevel.connect(levelOut)
	soundToggle = true

func levelOut():
	#print("LEVL OUT!")
	soundToggle = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if soundToggle == false:
		#print("SOUND TOGGLE!")
		playTrack3.emit()
		soundToggle = true
		var master_bus_index = AudioServer.get_bus_index("soundScape")
		AudioServer.set_bus_mute(master_bus_index, true)
		
	
func soundManipulation(sound: AudioStreamPlayer):
	#print(sound)
	#sound.volume_db = 3
	var bus_index = AudioServer.get_bus_index("soundScape")
	var panner = AudioServer.get_bus_effect(bus_index, 0)

	
	var target_pan = randNum(-0.75, 0.75)
	var tween = create_tween()
	tween.tween_property(panner, "pan", target_pan, 0.5)
	match(GlobalVariables.iterations):
		0:
			sound.pitch_scale = randNum(1.0, 1.5)

			sound.play()
		1:
			
			sound.pitch_scale = randNum(0.8, 1.3)
			#sound.panning_strength = randNum(0, 3)
			sound.play()
		2:
			sound.pitch_scale = randNum(0.5, 1.0)
			#sound.panning_strength = randNum(0, 3)
			sound.play()
		3:
			sound.pitch_scale = randNum(0.3, 0.8)
			#sound.panning_strength = randNum(0, 3)
			sound.play()
			
		4:
			sound.pitch_scale = randNum(0.25, 0.5)
			#sound.panning_strength = randNum(0, 3)
			sound.play()
			
		5:
			sound.pitch_scale = randNum(0.15, 0.4)
			#sound.panning_strength = randNum(0, 3)
			sound.play()
			
		6:
			sound.pitch_scale = randNum(0.05, 0.3)
			#sound.panning_strength = randNum(0, 3)
			sound.play()
	#sound.finished
			


func pickRandSound():
	sound = soundArr[randSound()]
	#print(soundArr[randSound()])
	#print("Pick: ", sound)
	soundManipulation(sound)


	_on_audio_manager_game_start()
	
	
var start := false

func _on_audio_manager_game_start() -> void:
	if start == false:
		sound = soundArr[randSound()]
		soundManipulation(sound)
		start = true
		
	var num = randomNumTransition()
	#print(num)
	await get_tree().create_timer(num).timeout 
	pickRandSound()
