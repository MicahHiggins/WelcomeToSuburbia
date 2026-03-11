extends Node3D

class_name npcStats

@export var npc_name: String = "NPC"
@export var health: int = 100
@export var move_speed: float = 150.0
@export var dialogue_id: Array = []


var in_area = false
var talking = false

signal dialogueSig


var local_dial := 0
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()

	if in_area == true && Input.is_action_just_pressed("interact"):
		enter_dialogue()
		
func enter_dialogue():
	if talking == false:
		
		talking = true
		dialogue.toggle = true
		print(GlobalVariables.iterations)
		if (GlobalVariables.iterations >= 3):
			dialogue.uniqueName = dialogue_id[2][local_dial]
		else:
			dialogue.uniqueName = dialogue_id[GlobalVariables.iterations][local_dial]
		await dialogueSig
		dialogue.toggle = false
		local_dial = local_dial + 1
		if local_dial == 3:
			local_dial = 0
		get_tree().create_timer(1).timeout
		talking = false
	
	
	
func _on_talk_detection_body_entered(body: Node3D) -> void:
	if body.is_multiplayer_authority():	
		tutorial.interact = true
		in_area = true
		print("TRUE")


func _on_talk_detection_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		GlobalVariables.interact.emit()
		tutorial.interact = false
		in_area = false
		print("FALSE")
