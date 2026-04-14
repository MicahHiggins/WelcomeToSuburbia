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
const FIDOFOUND = 3
const FIDOLOST = 4

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
	iss_local = 0
	
	
	
#func questSig():
	#if campbell_talked == false:
		#campbell_talked = true
	
	
func _input(event: InputEvent) -> void:

	#if talking == true && event.is_action("interact"):
		#return
	if event.is_action_pressed("use-attack"):
		dialogueSig.emit()
#
	#if in_area == true && Input.is_action_just_pressed("interact"):
		#enter_dialogue()
		
func bobDial():
		if (GlobalVariables.iterations >= 2):
			dialogue.uniqueDialogue =  npcDialogue.bobDialogue[2][bob_local]
			
		else:
			dialogue.uniqueDialogue = npcDialogue.bobDialogue[GlobalVariables.iterations][bob_local]
			
		bob_local += 1
		
		
		
		
func abiDial():
		if (GlobalVariables.iterations >= 3):
			dialogue.uniqueDialogue =  npcDialogue.abigailDialogue[2][abi_local]
		else:
			dialogue.uniqueDialogue = npcDialogue.abigailDialogue[GlobalVariables.iterations][abi_local]
			
		abi_local += 1
		
		
var DBToggle := false
func campDial():

	if GlobalVariables.iterations >= 2 && questHub.campbellProg == 1:
	
		
		print("Campbell Talked To! in iter 3-5")
		questHub.it_change()
		questHub.campbellProg = 2
		questHub.campbellTrigger()
		
	if (GlobalVariables.iterations >= 2):
		dialogue.uniqueDialogue =  npcDialogue.campbellsDialogue[2][camp_local]
	
		if GlobalVariables.iterations < 6 && questHub.campbellProg >= 3:
			#if camp_local == 2 && DBToggle == false:
				#DBToggle = true
				#camp_local = 0
			dialogue.uniqueDialogue = npcDialogue.campbellsDialogue[FIDOFOUND][camp_local]
			questHub.campbellProg = 4
			questHub.campbellTrigger()
		elif GlobalVariables.iterations > 6:
			dialogue.uniqueDialogue = npcDialogue.campbellsDialogue[FIDOLOST][camp_local]
			
				
	else:
		dialogue.uniqueDialogue = npcDialogue.campbellsDialogue[GlobalVariables.iterations][camp_local]
	camp_local += 1

func issDial():
	
	if GlobalVariables.iterations >= 1 && GlobalVariables.isaac_quest_progression == 0:
		#isaacQuest.isaacQToggle = false
		
		#GlobalVariables.iterations += 1
		questHub.isaacTrigger()
		questHub.it_change()
		questHub.campbellTrigger()
		
		print("DM: After issac talking trigger!")
	
	if (GlobalVariables.iterations >= 3):
		dialogue.uniqueDialogue =  npcDialogue.issDialogue[2][iss_local]
		
		##QMAIN QUEST!
		if GlobalVariables.isaac_quest_progression >= 5:
			
			dialogue.uniqueDialogue = npcDialogue.issDialogue[isaacQuest.ISAACQUEST_TURN_IN][iss_local]
			#questHub.it_change()
			GlobalVariables.isaac_quest_progression = 6
			questHub.isaacTrigger()
			
	
	else:
		dialogue.uniqueDialogue = npcDialogue.issDialogue[GlobalVariables.iterations][iss_local]
	iss_local += 1
		
		
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
				
			"Isaac":
				if iss_local == 3:
					iss_local = 2
				issDial()
				

		


		
func enter_dialogue():
	var number = 0
	
	#GlobalVariables.playerTalking = true
	print(GlobalVariables.playerTalking)
	if talking == false:
		#Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
		dialogue.uniqueName = npc_name
		talking = true
		dialogue.toggle = true
		#print("Curr Iteration: ", GlobalVariables.iterations)

		match(npc_name):
			"Bob":
				number = bob_local
			"Abigail":
				number = abi_local
			"The Campbells":
				number = camp_local
			"Isaac":
				number = iss_local
		
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
		#GlobalVariables.playerTalking = false
		print(GlobalVariables.playerTalking)
	
	
	
	
func _on_talk_detection_body_entered(body: Node3D) -> void:
	#print("SSSSs"
# Use the class name 'player' to filter out NPCs or other objects
	if body is player and body.is_multiplayer_authority():
		body.current_npc = self
		tutorial.interact = true
		in_area = true
		#print("TRUE")


func _on_talk_detection_body_exited(body: Node3D) -> void:
	if body is player and body.is_multiplayer_authority():
		if body.current_npc == self:
			body.current_npc = null
		tutorial.interact = false
		in_area = false


#func find_descendant_in_group(node: Node, group: String) -> Node:
	#if node.is_in_group(group):
		#return node
		#
	#for child in node.get_children():
		#var result = find_descendant_in_group(child, group)
		#if result:
			#return result
			#
	#return null
	
	#To find the animation for talking and playing it
	#var npc: CharacterBody3D
	#var npc3d := npc as NPC
	#if npc3d == null:
		#return
	#var model_node = find_descendant_in_group(npc3d, "NPC_Body")
	#if model_node:
		#var anim_player = find_descendant_in_group(model_node, "NPC_Animation")
		#if anim_player:
			#anim_player.play("NewTalking")
