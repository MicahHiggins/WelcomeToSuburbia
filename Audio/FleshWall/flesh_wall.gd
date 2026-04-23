extends Node

@onready var slime_1: AudioStreamPlayer = $Slime1
@onready var slime_2: AudioStreamPlayer = $Slime2
@onready var slime_3: AudioStreamPlayer = $Slime3
@onready var slime_long: AudioStreamPlayer = $SlimeLong
@onready var bang_1: AudioStreamPlayer = $Bang1
@onready var bang_2: AudioStreamPlayer = $Bang2
@onready var __chase_slow_reverbed: AudioStreamPlayer = $"'chase'Slow+reverbed"

func randiBang():
	return randi_range(1, 2)
	
func randiSlime():
	return randi_range(1, 3)
	
func randInterval():
	return randi_range(1, 2)
	
func randfPitch():
	return randf_range(0.1, 1.0)
		


func _ready() -> void:
	AudioManager.fleshWall.connect(activateFleshWall)
	activateFleshWall()
	
func activateFleshWall():
	slime_long.play()
	__chase_slow_reverbed.play()
	
	
	activateBang()
	await get_tree().create_timer(2.0).timeout
	activateSlime()
	
	
func activateBang():
	var randNum = randiBang()
	match(randNum):
		1:
			bang_1.pitch_scale = randfPitch()
			bang_1.play()
		2:
			bang_2.pitch_scale = randfPitch()
			bang_2.play()
			
	await get_tree().create_timer(randInterval()).timeout
	
	if GlobalVariables.winPuzzle3 == true:
		return
	activateBang()
	
	
func activateSlime():
	var randNum = randiSlime()
	match(randNum):
		1:
			slime_1.pitch_scale = randfPitch()
			slime_1.play()
		2:
			slime_2.pitch_scale = randfPitch()
			slime_2.play()
		3:
			slime_3.pitch_scale = randfPitch()
			slime_3.play()
			
	await get_tree().create_timer(randInterval()).timeout
	
	if GlobalVariables.winPuzzle3 == true:
		return
	activateSlime()
	
	
	
