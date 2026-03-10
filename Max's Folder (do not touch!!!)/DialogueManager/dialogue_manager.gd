extends NinePatchRect

class_name dialogue

@onready var npcName: Label = $Name
@onready var npcText: Label = $Text


static var uniqueName := "default"
static var uniqueDialogue := "default"
static var toggle := false

#@onready var text: Label = $Text
#@onready var name: Label = $Name


#static var name := "default"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	npcText.text = uniqueName
	if toggle == true:
		
		visible = true
	else:
		visible = false;
