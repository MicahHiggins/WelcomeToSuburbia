extends Node3D
@onready var drawing: Node2D = $Drawing
@onready var seeing: Node2D = $Seeing
@onready var exit: Button = $Buttons/Exit
@onready var label: Label = $Buttons/Label
@onready var button: Button = $Buttons/Button
@onready var clear: Button = $Buttons/Clear

@onready var interact: Label = $interact
@onready var buttons: Control = $Buttons

var in_area = false
var see = false
var do = false

const SERVER_ID: int = 1

# ADDED: cache the authoritative type on this node
var _puzzle_type: int = -1


func _ready() -> void:
	seeing.visible = false
	buttons.visible = false
	drawing.visible = false
	buttons.visible = false

	# SINGLEPLAYER: keep old behavior
	if not multiplayer.has_multiplayer_peer():
		_puzzle_type = randi_range(1, 3)
		GlobalVariables.puzzleType = _puzzle_type
		print("NUMM:, ", GlobalVariables.puzzleType)
		return

	# MULTIPLAYER: server decides once, clients never roll locally
	if multiplayer.is_server():
		if _puzzle_type == -1:
			_puzzle_type = randi_range(1, 3)
		GlobalVariables.puzzleType = _puzzle_type
		rpc("_rpc_set_puzzle_type", _puzzle_type)

		# ADDED: late joiners get the same puzzle type
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		# ADDED: joining client asks server for current puzzle type
		rpc_id(SERVER_ID, "_rpc_request_puzzle_type")

	print("NUMM:, ", GlobalVariables.puzzleType)


func randPuzzle():
	# MULTIPLAYER: server rerolls and broadcasts
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_puzzle_type = randi_range(1, 3)
			GlobalVariables.puzzleType = _puzzle_type
			rpc("_rpc_set_puzzle_type", _puzzle_type)
		return

	# SINGLEPLAYER
	_puzzle_type = randi_range(1, 3)
	GlobalVariables.puzzleType = _puzzle_type


# ADDED: joining client asks server for the current type
@rpc("any_peer", "reliable")
func _rpc_request_puzzle_type() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if _puzzle_type == -1:
		_puzzle_type = randi_range(1, 3)
	GlobalVariables.puzzleType = _puzzle_type
	rpc_id(sender, "_rpc_set_puzzle_type", _puzzle_type)


# ADDED: server sends the type to new peers
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _puzzle_type == -1:
		return
	rpc_id(peer_id, "_rpc_set_puzzle_type", _puzzle_type)


# apply authoritative puzzle type on every peer (including host)
@rpc("any_peer", "call_local", "reliable")
func _rpc_set_puzzle_type(t: int) -> void:
	_puzzle_type = int(t)
	GlobalVariables.puzzleType = _puzzle_type


func _process(delta: float) -> void:
	if in_area == true:
		interact.visible = true
	else:
		interact.visible = false


func _input(event: InputEvent) -> void:
	if in_area == true && event.is_action("interact") && see == true:
		seeing.visible = true
		buttons.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif in_area == true && event.is_action_pressed("interact") && do == true:
		drawing.visible = true
		buttons.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_obs_area_body_entered(body: Node3D) -> void:
	print("TESTETES")
	if body.is_multiplayer_authority():
		in_area = true
		print("IN")
		see = true


func _on_obs_area_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		in_area = false
		see = false


func _on_do_area_body_entered(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		in_area = true
		do = true


func _on_do_area_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		in_area = false
		do = false


func _on_exit_pressed() -> void:
	seeing.visible = false
	buttons.visible = false
	drawing.visible = false
	buttons.visible = false
