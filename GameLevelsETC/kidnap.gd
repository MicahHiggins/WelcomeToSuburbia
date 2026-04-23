extends Node3D

@onready var cohesion: AnimationPlayer = $Cohesion

@export var replicate_last_anim_to_late_joiners: bool = true

# NEW: server-approved state for the gate to read
var puzzle2_done: bool = false

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""

func _ready() -> void:
	# NEW: so the gate can find this node
	if not is_in_group("puzzle_state"):
		add_to_group("puzzle_state")

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and replicate_last_anim_to_late_joiners:
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

func _process(_delta: float) -> void:
	pass

func _on_toy_piano_puzzle_one_complete() -> void:
	play_anim_networked(&"puzzle1Complete")

func _on_drawing_puzzle_two_complete() -> void:
	play_anim_networked(&"puzzle2Complete")

func _get_anim_player() -> AnimationPlayer:
	if _anim_player != null and is_instance_valid(_anim_player):
		return _anim_player
	_anim_player = get_node_or_null("Cohesion") as AnimationPlayer
	return _anim_player

func _server_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return -1
	if multiplayer.is_server():
		return multiplayer.get_unique_id()
	var peers: Array = multiplayer.get_peers()
	if peers.is_empty():
		return -1
	var best: int = int(peers[0])
	for p_any in peers:
		var p: int = int(p_any)
		if p < best:
			best = p
	return best

func play_anim_networked(anim: StringName) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_play_anim_server(anim)
		else:
			var sid := _server_peer_id()
			if sid > 0:
				rpc_id(sid, "_rpc_request_play_anim", String(anim))
	else:
		_play_anim_local(anim)

@rpc("any_peer", "reliable")
func _rpc_request_play_anim(anim_name: String) -> void:
	if not multiplayer.is_server():
		return

	var anim := StringName(anim_name)

	# ensure server flag is set even if animation repeats / race conditions
	if anim == &"puzzle2Complete":
		puzzle2_done = true

	_play_anim_server(anim)

func _play_anim_server(anim: StringName) -> void:
	if _last_anim == anim:
		return
	_last_anim = anim

	# NEW: flip the server flag when puzzle2 completes
	if anim == &"puzzle2Complete":
		puzzle2_done = true

	_play_anim_local(anim)

	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_play_anim", String(anim))

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_anim(anim_name: String) -> void:
	_last_anim = StringName(anim_name)
	_play_anim_local(_last_anim)

func _play_anim_local(anim: StringName) -> void:
	var ap := _get_anim_player()
	if ap == null:
		return
	var a := String(anim)
	if ap.has_animation(a):
		ap.play(a)

func _on_peer_connected(peer_id: int) -> void:
	if _last_anim == &"":
		return
	rpc_id(peer_id, "_rpc_play_anim", String(_last_anim))
