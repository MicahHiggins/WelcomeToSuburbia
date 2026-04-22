extends Area3D
class_name BatSwingGate

const SERVER_ID: int = 1

@export var required_unique_swings: int = 2
@export var anim_player: AnimationPlayer = null
@export var anim_name: StringName = &""
@export var change_level_after: bool = true
@export var level_index_to_load: int = 3

var _inside: Dictionary = {} # int -> bool
var _swung: Dictionary = {}  # int -> bool
var _done: bool = false

func _ready() -> void:
	add_to_group("bat_swing_gate")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group("player"):
		return
	var pid := int(body.get_multiplayer_authority())
	if pid <= 0:
		return
	_inside[pid] = true

func _on_body_exited(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group("player"):
		return
	var pid := int(body.get_multiplayer_authority())
	if pid <= 0:
		return
	_inside.erase(pid)

func notify_swing(peer_id: int) -> void:
	if _done:
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_request_swing", peer_id)
		return

	_server_register_swing(peer_id)

@rpc("any_peer", "reliable")
func _rpc_request_swing(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_server_register_swing(peer_id)

func _server_register_swing(peer_id: int) -> void:
	if _done:
		return
	if not _inside.has(peer_id):
		return
	if _swung.has(peer_id):
		return

	_swung[peer_id] = true

	if _swung.size() < required_unique_swings:
		return

	_done = true
	_server_complete()

func _server_complete() -> void:
	if anim_player != null:
		var a := String(anim_name)
		if a != "" and anim_player.has_animation(a):
			anim_player.play(a)
			if multiplayer.has_multiplayer_peer():
				rpc("_rpc_play_anim", a)
			await anim_player.animation_finished

	if change_level_after:
		var lf := get_tree().get_first_node_in_group("level_flow_manager")
		if lf != null and lf.has_method("request_level_change"):
			lf.call("request_level_change", level_index_to_load)

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_anim(a: String) -> void:
	if anim_player == null:
		return
	if anim_player.has_animation(a):
		anim_player.play(a)
