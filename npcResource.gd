extends Node3D

class_name npcStats

@export var npc_name: String = "NPC"
@export var health: int = 100
@export var move_speed: float = 150.0





var in_area = false
var talking = false

signal dialogueSig


var local_dial := 0

func _ready():
	pass
	

	#label.text = dialogue_id.replace("\\n", "\n")
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()

	if in_area == true && Input.is_action_just_pressed("interact"):
		enter_dialogue()
		
func enter_dialogue():
	GlobalVariables.playerTalking = true
	if talking == false:
		dialogue.uniqueName = npc_name
		talking = true
		dialogue.toggle = true
		print(GlobalVariables.iterations)
		match(npc_name):
			"Bob":
				if (GlobalVariables.iterations >= 3):
					dialogue.uniqueDialogue =  npcDialogue.bobDialogue[2][local_dial]
				else:
					dialogue.uniqueDialogue = npcDialogue.bobDialogue[GlobalVariables.iterations][local_dial]
			"Abigail":
				if (GlobalVariables.iterations >= 3):
					dialogue.uniqueDialogue =  npcDialogue.abigailDialogue[2][local_dial]
				else:
					dialogue.uniqueDialogue = npcDialogue.abigailDialogue[GlobalVariables.iterations][local_dial]
			"The Campbells":
				if (GlobalVariables.iterations >= 3):
					dialogue.uniqueDialogue =  npcDialogue.campbellsDialogue[2][local_dial]
				else:
					dialogue.uniqueDialogue = npcDialogue.campbellsDialogue[GlobalVariables.iterations][local_dial]
				
				
		await dialogueSig
		dialogue.toggle = false
		local_dial = local_dial + 1
		if local_dial == 3:
			local_dial = 2
		await get_tree().create_timer(0.5).timeout
		talking = false
		GlobalVariables.playerTalking = false
	
	
	
	
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
