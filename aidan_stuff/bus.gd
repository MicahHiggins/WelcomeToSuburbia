extends Node3D

@onready var trigger_area_1: Area3D = $Area3D
@onready var trigger_area_2: Area3D = $Area3D2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var cooldown_timer: Timer = $BusCooldownTimer
@onready var bus_mesh: Node3D = $busssss

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

	$busssss.visible = true

	trigger_area_1.body_entered.connect(_on_trigger_area_1_body_entered)
	trigger_area_2.body_entered.connect(_on_trigger_area_2_body_entered)
	cooldown_timer.timeout.connect(_on_cooldown_timeout)


func _on_trigger_area_1_body_entered(body: Node) -> void:
	if not _is_valid_trigger_body(body):
		return

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_try_trigger_bus("Bus_move")
		else:
			rpc_id(1, "_rpc_request_trigger_bus", "Bus_move")
	else:
		_server_try_trigger_bus("Bus_move")

func _on_trigger_area_2_body_entered(body: Node) -> void:
	if not _is_valid_trigger_body(body):
		return

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_try_trigger_bus("Bus_move2")
		else:
			rpc_id(1, "_rpc_request_trigger_bus", "Bus_move2")
	else:
		_server_try_trigger_bus("Bus_move2")

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

	if roll < 0.5:
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
	bus_mesh.visible = true

	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)
		print("Playing animation: ", animation_name)
	else:
		print("No animation named: ", animation_name)
		print("Available animations: ", animation_player.get_animation_list())

func _on_cooldown_timeout() -> void:
	can_trigger = true
	print("Bus cooldown ended")
