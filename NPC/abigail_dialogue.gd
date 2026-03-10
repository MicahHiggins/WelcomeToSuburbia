extends Node



var in_abigail_area = false
var abigail_talking = false

signal dialogueSig


var dialogueArray = [
	["Without the Home Owners Association,\n this neighborhood wouldn’t be so pretty", "You two look like trouble", "..."],
	["if you don’t follow the HOA rules,\n there will be penalties!\n haha", "...", "..."],
	["I can’t wait for the new HOA\n rules to be put in place. It will be so\n pretty around here", "...", "Run"]
]
var local_dial := 0
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()

	if in_abigail_area == true && Input.is_action_just_pressed("interact"):
		enter_abigail_dialogue()



func enter_abigail_dialogue():
	#for i in range(3)
	if abigail_talking == false:
		
		abigail_talking = true
		dialogue.toggle = true
		print(GlobalVariables.iterations)
		if (GlobalVariables.iterations >= 3):
			dialogue.uniqueName = dialogueArray[2][local_dial]
		else:
			dialogue.uniqueName = dialogueArray[GlobalVariables.iterations][local_dial]
		await dialogueSig
		dialogue.toggle = false
		local_dial = local_dial + 1
		if local_dial == 3:
			local_dial = 0
		
		await get_tree().create_timer(1).timeout
		abigail_talking = false
	


func _on_talk_detection_body_entered(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		tutorial.interact = true
		in_abigail_area = true
		print("TRUE")


func _on_talk_detection_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		tutorial.interact = false
		in_abigail_area = false
		print("FALSE")
