extends Node3D

class_name npcStats

@export var npc_name: String = "NPC"
@export var health: int = 100
@export var move_speed: float = 150.0



var bob_local := 0
var abi_local := 0
var camp_local := 0
var iss_local := 0

var in_area = false
var talking = false

signal dialogueSig

var campbell_talked := false
var local_dial := 0

func _ready():
	
	#global signal connection
	questHub.iteration_changed.connect(iterationChange)
	

#detects iteration change within dialogue
func iterationChange(value: int):
	#print("NPC RESOURCE: iteration ", value)

	bob_local = 0
	abi_local = 0
	camp_local = 0
	
	
#func questSig():
	#if campbell_talked == false:
		#campbell_talked = true
	
	
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()

	if in_area == true && Input.is_action_just_pressed("interact"):
		enter_dialogue()
		
func bobDial():
		if (GlobalVariables.iterations >= 2):
			dialogue.uniqueDialogue =  npcDialogue.bobDialogue[2][bob_local]
			
		else:
			dialogue.uniqueDialogue = npcDialogue.bobDialogue[GlobalVariables.iterations][bob_local]
			
		bob_local += 1
		
		print(bob_local)
		
		
		
func abiDial():
		if (GlobalVariables.iterations >= 3):
			dialogue.uniqueDialogue =  npcDialogue.abigailDialogue[2][abi_local]
		else:
			dialogue.uniqueDialogue = npcDialogue.abigailDialogue[GlobalVariables.iterations][abi_local]
			
		abi_local += 1
		
func campDial():
	if campbell_talked == false && GlobalVariables.iterations >= 2:
		campbell_talked = true
		print("Campbell Talked To! in iter 3")
		questHub.campbellTalk()
	if (GlobalVariables.iterations >= 3):
		dialogue.uniqueDialogue =  npcDialogue.campbellsDialogue[2][camp_local]
	else:
		dialogue.uniqueDialogue = npcDialogue.campbellsDialogue[GlobalVariables.iterations][camp_local]
	camp_local += 1
		
func dialogueMan(npc_name):
	match(npc_name):
			"Bob":
				if bob_local == 3:
					bob_local = 2
				bobDial()
				
			"Abigail":
				if abi_local == 3:
					abi_local = 2
				abiDial()
			
			"The Campbells":
				if camp_local == 3:
					camp_local = 2
				campDial()

		


		
func enter_dialogue():
	var number = 0
	GlobalVariables.playerTalking = true
	if talking == false:
		#Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
		dialogue.uniqueName = npc_name
		talking = true
		dialogue.toggle = true
		print("Curr Iteration: ", GlobalVariables.iterations)
		
		match(npc_name):
			"Bob":
				number = bob_local
			"Abigail":
				number = abi_local
			"The Campbells":
				number = camp_local
		
		if number >= 2:
			dialogueMan(npc_name)
			await dialogueSig
		else: 
			dialogueMan(npc_name)
			await dialogueSig
			dialogueMan(npc_name)
			await dialogueSig
			dialogueMan(npc_name)
			await dialogueSig
			


	


		await get_tree().create_timer(0.005).timeout
		#Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		dialogue.toggle = false
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
