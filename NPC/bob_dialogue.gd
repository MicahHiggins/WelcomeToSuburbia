extends Node3D



var in_bob_area = false
var bob_talking = false

signal dialogueSig


var dialogueArray = [
	["What are you doing walking in my\n yard, kids?", "Oh, good morning to you two", "My neighbors are weird as hell, you two seem\n fine though"],
	["I tried going to work but I can’t get out\n of this damn neighborhood", "My neighbors keep staring at me. Be careful\n around these creeps.", "Something feels weird."],
	["I dont think its safe here. But I don’t\n think i can leave", "The new HOA rules are really\n strange.", "Don’t let them get you"]
]
var local_dial := 0
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()

	if in_bob_area == true && Input.is_action_just_pressed("interact"):
		enter_bob_dialogue()



func enter_bob_dialogue():
	#for i in range(3)
	if bob_talking == false:
		
		bob_talking = true
		dialogue.toggle = true
		print(GlobalVariables.iterations)
		dialogue.uniqueName = dialogueArray[GlobalVariables.iterations][local_dial]
		await dialogueSig
		dialogue.toggle = false
		local_dial = local_dial + 1
		if local_dial == 3:
			local_dial = 0
		
		await get_tree().create_timer(1).timeout
		bob_talking = false
	


func _on_talk_detection_body_entered(body: Node3D) -> void:
	GlobalVariables.interact.emit()
	in_bob_area = true
	print("TRUE")


func _on_talk_detection_body_exited(body: Node3D) -> void:
	GlobalVariables.interact.emit()
	in_bob_area = false
	print("FALSE")
