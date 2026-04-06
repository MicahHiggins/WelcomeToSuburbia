extends Label

class_name tutorial
@onready var pop_up: tutorial = $"."

#@onready var pop_up: Label = $"."

static var interact := false
static var tut_text := "F to interact"
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	#GlobalVariables.interact.connect(toggle_visibility)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if interact == true:
		visible = true
		pop_up.text = "F to Interact"
		if dialogue.toggle == true:
			pop_up.text = "Click to Continue"
		
		
	else:
		visible = false
		pop_up.text = "F to Interact"


#func toggle_visibility():
	#if pop_up.visible == true:
		#pop_up.visible = false
	#else:
		#pop_up.visible = true
