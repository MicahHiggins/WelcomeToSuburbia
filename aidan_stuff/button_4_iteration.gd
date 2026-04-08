extends Control

const SERVER_ID := 1

func _on_button_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_iter_up")
		return
	_rpc_iter_up()

@rpc("any_peer", "call_local", "reliable")
func _rpc_iter_up() -> void:
	GlobalVariables.iterations += 1
	GlobalVariables.ITERS += 1
	GlobalVariables.gameStart.emit()
	questHub.it_change()
