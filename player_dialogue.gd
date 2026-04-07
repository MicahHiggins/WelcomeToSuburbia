extends CanvasLayer

@export var playerSpeech = RichTextLabel
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	change_dialogue()

func change_dialogue() -> void:
	if GlobalVariables.iterations == 0:
		await get_tree().create_timer(2).timeout
		playerSpeech.visible = true
		playerSpeech.text = "Evan: Alright, looks like we need to find our way home."
		await get_tree().create_timer(6).timeout
		playerSpeech.visible = false
		await get_tree().create_timer(2).timeout
		playerSpeech.visible = true
		playerSpeech.text = "Lucy: Does our neighborhood look different to you? Where is #130?"
		await get_tree().create_timer(6).timeout
		playerSpeech.visible = false
	if GlobalVariables.iterations == 1:
		return
