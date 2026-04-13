extends CanvasLayer

@export var playerSpeech = RichTextLabel

#GlobalVariables.gameStart.emit()

func _ready() -> void:
	GlobalVariables.gameStart.connect(change_dialogue)

func _process(delta: float) -> void:
	pass

func change_dialogue() -> void:
	match GlobalVariables.iterations:
		0:
			await get_tree().create_timer(10).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: Alright, looks like we need to find our way home."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: Does our neighborhood look different to you? Where is #130?"
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
		1:
			await get_tree().create_timer(10).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: Haven't we seen that house before?"
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: We definitely have seen that house before."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
		2:
			await get_tree().create_timer(10).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: I'm Scared Lucy, where is the way out!"
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: We should keep investigating like Isaac said, he seems friendly, unlike the other people here..."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
		3:
			await get_tree().create_timer(10).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Evan: I'm kinda starting to freak out"
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
			await get_tree().create_timer(2).timeout
			playerSpeech.visible = true
			playerSpeech.text = "Lucy: Me too..."
			await get_tree().create_timer(6).timeout
			playerSpeech.visible = false
