extends Node3D

@onready var trigger_area_1: Area3D = $Area3D
@onready var trigger_area_2: Area3D = $Area3D2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var cooldown_timer: Timer = $BusCooldownTimer
@onready var bus_mesh: Node3D = $busssss2

var can_trigger: bool = true

func _ready() -> void:
	if trigger_area_1 == null:
		print("Bus: Area3D not found")
		return
	if trigger_area_2 == null:
		print("Bus: Area3D2 not found")
		return
	if animation_player == null:
		print("Bus: AnimationPlayer not found")
		return
	if cooldown_timer == null:
		print("Bus: BusCooldownTimer not found")
		return
	if bus_mesh == null:
		print("Bus: busssss not found")
		return

	bus_mesh.visible = false

	trigger_area_1.body_entered.connect(_on_trigger_area_1_body_entered)
	trigger_area_2.body_entered.connect(_on_trigger_area_2_body_entered)
	cooldown_timer.timeout.connect(_on_cooldown_timeout)


func _on_trigger_area_1_body_entered(body: Node) -> void:
	if not _is_valid_trigger_body(body):
		return

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_try_trigger_bus("BUS_MOVE")
		else:
			rpc_id(1, "_rpc_request_trigger_bus", "BUS_MOVE")
	else:
		_server_try_trigger_bus("BUS_MOVE")

func _on_trigger_area_2_body_entered(body: Node) -> void:
	if not _is_valid_trigger_body(body):
		return

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_try_trigger_bus("BUS_MOVE2")
		else:
			rpc_id(1, "_rpc_request_trigger_bus", "BUS_MOVE2")
	else:
		_server_try_trigger_bus("BUS_MOVE2")

func _is_valid_trigger_body(body: Node) -> bool:
	if body == null:
		return false
	if not body.is_in_group("player"):
		return false
	if multiplayer.has_multiplayer_peer() and not body.is_multiplayer_authority():
		return false
	return true

func _server_try_trigger_bus(animation_name: String) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not can_trigger:
		print("Bus still on cooldown")
		return

	# cooldown starts whether the 50% roll succeeds or fails
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_start_bus_cooldown")
	else:
		_rpc_start_bus_cooldown()

	var roll := randf()
	print("Bus roll for ", animation_name, ": ", roll)

	if roll < 1.0:
		if multiplayer.has_multiplayer_peer():
			rpc("_rpc_play_bus_animation", animation_name)
		else:
			_rpc_play_bus_animation(animation_name)
	else:
		print("Bus roll failed for ", animation_name)

@rpc("any_peer", "reliable")
func _rpc_request_trigger_bus(animation_name: String) -> void:
	if not multiplayer.is_server():
		return

	_server_try_trigger_bus(animation_name)

@rpc("call_local", "reliable")
func _rpc_start_bus_cooldown() -> void:
	can_trigger = false
	cooldown_timer.stop()
	cooldown_timer.start()
	print("Bus cooldown started")

@rpc("call_local", "reliable")
func _rpc_play_bus_animation(animation_name: String) -> void:
	var player := get_tree().get_first_node_in_group("player")

	bus_mesh.visible = true
	bus_mesh.show()

	for child in bus_mesh.get_children():
		if child is Node3D:
			child.show()

	if player:
		bus_mesh.global_position = player.global_position + (-player.global_transform.basis.z * 8.0)
		bus_mesh.global_position.y = player.global_position.y + 1.0
		print("Moved bus in front of player: ", bus_mesh.global_position)

	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)
		print("Playing animation: ", animation_name)
	else:
		print("No animation named: ", animation_name)
func _on_cooldown_timeout() -> void:
	can_trigger = true
	print("Bus cooldown ended")
