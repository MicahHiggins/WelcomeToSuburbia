extends CanvasLayer

@export var playerSpeech = RichTextLabel

#GlobalVariables.gameStart == true

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	change_dialogue()

func change_dialogue() -> void:
	if GlobalVariables.gameStart == true:
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
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: Haven't we seen that house before?"
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: We definitely have seen that house before."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
		if GlobalVariables.iterations == 2:
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: We should help find their dog."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: I think I saw him go by House 120."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
		if GlobalVariables.iterations == 3:
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: Does something feel off about this neighborhood?"
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: The people here don't act right..."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
