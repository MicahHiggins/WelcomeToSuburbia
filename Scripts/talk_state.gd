extends NPCState
class_name TalkState

func enter(_msg := {}) -> void:
	# Stop movement while talking
	if npc != null:
		npc.velocity = Vector3.ZERO

func physics_update(_delta: float) -> void:
	# For now, do nothing. Later: face player, play anim, etc.
	pass
