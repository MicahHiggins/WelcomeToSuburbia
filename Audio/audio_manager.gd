extends Node3D

@onready var SFX = $SFX

func playBreathing():
	$AnimationPlayer.play("Start_Breathing")
	SFX.Breathing.play()
	
func StopBreathing():
	
	SFX.Breathing.play()
		
