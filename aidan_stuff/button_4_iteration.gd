extends Control




func _on_button_pressed() -> void:
	GlobalVariables.iterations += 1
	GlobalVariables.ITERS += 1
	GlobalVariables.gameStart.emit()
	questHub.it_change()
