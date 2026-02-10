extends NPCState
class_name TalkState

@export var talk_detection : Area3D
var potential_talk : Array

func enter(_msg := {}) -> void:
	# Stop movement while talking
	npc.velocity = Vector3.ZERO

func physics_update(_delta: float) -> void:
	# For now, do nothing. Later: face player, play anim, etc.
	potential_talk = talk_detection.get_overlapping_bodies()
	if (potential_talk.is_empty()):
		change_state.emit(&"PatrolState")
