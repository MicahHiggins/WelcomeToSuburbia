extends Node
class_name State

signal change_state(new_state: State)
var body : CharacterBody2D

#var main_sprite : Sprite2D
#var body : CharacterStateMachine

func initialize():
	pass

func on_enter_state():
	pass

func on_exit_state():
	pass

func process_state(delta: float):
	pass

func physics_process_state(delta: float):
	pass

func process_input(event: InputEvent):
	pass

func look_at(position):
	pass
