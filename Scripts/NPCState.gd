extends Node
class_name NPCState

var npc: CharacterBody3D
var sm: NPCStateMachine
signal change_state(new_state: NPCState)

func initialize():
	pass

func enter(_msg := {}):
	pass

func exit():
	pass

func physics_update(_delta: float):
	pass
	
func look_at(position):
	pass
