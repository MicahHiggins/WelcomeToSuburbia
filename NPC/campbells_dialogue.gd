extends Node



var in_campbell_area = false
var campbell_talking = false

signal dialogueSig


var dialogueArray = [
	["“Hey there neighbors!”", "This old dog just can’t keep up.", "*the daughter looks visibly frightened*"],
	["You just aren’t cutting it anymore doggy", "I think we need to take you out...", "*the daughter starts to sob*"],
	["He is such a good boy now. I love him!", "Me too", "*Gargled Animal Sounds*"]
]
var local_dial := 0
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()

	if in_campbell_area == true && Input.is_action_just_pressed("interact"):
		enter_abigail_dialogue()



func enter_abigail_dialogue():
	#for i in range(3)
	if campbell_talking == false:
		
		campbell_talking = true
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
		campbell_talking = false
	








func _on_talk_detection_body_entered(body: Node3D) -> void:
	GlobalVariables.interact.emit()
	in_campbell_area = true
	print("TRUE")


func _on_talk_detection_body_exited(body: Node3D) -> void:
	GlobalVariables.interact.emit()
	in_campbell_area = false
	print("FALSE")
