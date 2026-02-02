extends CharacterBody3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
signal dialogueClick

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
	dialogue.toggle = true
	dialogue.uniqueName = "Dave"
	
	
	dialogue.uniqueDialogue = "Hi I'm dave"
	await dialogueClick
	print("TESTSTESTest")
	dialogue.uniqueName = "Im a kill u foo"
	await dialogueClick
	dialogue.toggle = false
