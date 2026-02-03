extends CharacterBody3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
signal dialogueClick


var dialogueArray: Array[Array] = [
	["Hi I'm Dave", "I love my neighbors!", "Have a good day!"],
	["Hello", "Im changing", "bye"],
	["Hahaha", "fucking dead", "You are really trapped"]
]
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if dialogue.toggle == true:
		if Input.is_action_just_pressed("interact"):
			print("YIPEEEE")
			dialogueClick.emit()


func _on_area_3d_body_entered(body: Node3D) -> void:
	print("TESTTTTTTTT")
	var dia = 0
	dialogue.toggle = true
	print(GlobalVariables.iterations)
	dialogue.uniqueName = dialogueArray[GlobalVariables.iterations][dia]
	dia += 1
	
	
	#dialogue.uniqueDialogue = "Hi I'm dave"
	await dialogueClick
	dialogue.uniqueName = dialogueArray[GlobalVariables.iterations][dia]
	dia += 1
	await dialogueClick
	dialogue.uniqueName = dialogueArray[GlobalVariables.iterations][dia]
	dia += 1
	await dialogueClick
	dialogue.toggle = false
