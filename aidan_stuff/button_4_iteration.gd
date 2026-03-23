extends Control




func _on_button_pressed() -> void:
	GlobalVariables.iterations += 1
	questHub.it_change()
