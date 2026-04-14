extends Control

const SERVER_ID := 1

func _on_button_pressed() -> void:
	
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_iter_up()
		else:
			rpc_id(SERVER_ID, "_rpc_request_iter_up")
			#_server_iter_up() #4 single player
		return

	_server_iter_up()

@rpc("any_peer", "reliable")
func _rpc_request_iter_up() -> void:
	if not multiplayer.is_server():
		return
	_server_iter_up()

func _server_iter_up() -> void:
	#GlobalVariables.iterations += 1

	print("QUEST BUTTON CHANGE!")
	GlobalVariables.gameStart.emit()
	# 
	var it: int = int(GlobalVariables.iterations)
	rpc("_rpc_apply_iters", it)

@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_iters(it: int) -> void:
	GlobalVariables.iterations = it
	print("QUEST BUTTON CHANGE!")
	GlobalVariables.gameStart.emit()
	questHub.it_change()
