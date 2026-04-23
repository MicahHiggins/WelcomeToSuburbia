extends Node3D

@onready var breathing: AudioStreamPlayer = %Breathing
@onready var anim: AnimationPlayer = $AnimationPlayer

signal gameStart


signal fleshWall



const BREATH_MIN_DB := -80.0
const BREATH_MAX_DB := -70.0

func playBreathing() -> void:
	# If it isn't already playing, start it quietly first.
	if not breathing.playing:
		breathing.volume_db = BREATH_MIN_DB
		breathing.play()

	# Fade up (won't restart the sound, just animates volume_db)
	anim.play("Start_Breathing")

func StopBreathing() -> void:
	if not breathing.playing:
		return
	# Fade down; we will stop playback when the animation finishes
	anim.play("Stop_Breathing")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Stop_Breathing":
		breathing.stop()
		breathing.volume_db = BREATH_MIN_DB
