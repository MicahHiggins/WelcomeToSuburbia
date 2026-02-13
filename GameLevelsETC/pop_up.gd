extends Label

@onready var pop_up: Label = $"."

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pop_up.visible = false
	GlobalVariables.interact.connect(toggle_visibility)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func toggle_visibility():
	if pop_up.visible == true:
		pop_up.visible = false
	else:
		pop_up.visible = true
