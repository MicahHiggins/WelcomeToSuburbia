extends Area3D

var toggle_detection = true

func _on_body_entered(body: Node3D) -> void:
	# 1. Only the local player who touched it sends the request
	if body.is_in_group("player") and body.is_multiplayer_authority():
		if toggle_detection:
			toggle_detection = false # Prevent local spam
			rpc_id(1, "server_trigger_event")

@rpc("any_peer", "call_local", "reliable")
func server_trigger_event():
	# 2. Only the server actually processes the logic
	if not multiplayer.is_server():
		return
	
	print("Server: Triggering global iteration change")
	if GlobalVariables.iterations >=  1:
		return null
	questHub.it_change()
	
	# 3. Tell everyone to remove this node from their game
	sync_despawn.rpc()

@rpc("authority", "call_local", "reliable")
func sync_despawn():
	print("Despawning trigger for everyone")
	queue_free()
