# res://DoorInteractable.gd
extends Node3D
class_name DoorInteractable

const SERVER_ID := 1

# -----------------------
# Inspector settings
# -----------------------
@export var required_iteration: int = 0

@export var open_anim: StringName = &"open"
@export var close_anim: StringName = &"close"

@export var auto_close_enabled: bool = true
@export var auto_close_seconds: float = 10.0
@export var allow_close_on_second_interact: bool = true

@export var start_open: bool = false
@export var debug_print: bool = false

# Path to the AnimationPlayer in this door scene
@export var anim_player_path: NodePath = NodePath("AnimationPlayer")

# If true, interaction does nothing until required_iteration is reached
@export var gate_blocks_interaction: bool = true

# -----------------------
# Runtime
# -----------------------
var _anim: AnimationPlayer = null
var _is_open: bool = false
var _auto_close_timer: Timer = null


func _ready() -> void:
	_anim = get_node_or_null(anim_player_path) as AnimationPlayer

	_auto_close_timer = Timer.new()
	_auto_close_timer.one_shot = true
	add_child(_auto_close_timer)
	_auto_close_timer.timeout.connect(_on_auto_close_timeout)

	_is_open = start_open
	if start_open and _anim != null:
		if _anim.has_animation(String(open_anim)):
			_anim.play(String(open_anim))
		_start_auto_close_if_needed()


# ============================================================
# Public API: called by your raycast interact system
# Some callers pass 1 arg, so accept it (typed) and ignore it.
# ============================================================
func interact(_unused: Variant = null) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_toggle(multiplayer.get_unique_id())
		else:
			rpc_id(SERVER_ID, "_rpc_request_toggle")
		return

	_server_toggle(0)


@rpc("any_peer", "reliable")
func _rpc_request_toggle() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_toggle(sender)


func _server_toggle(_sender_id: int) -> void:
	if gate_blocks_interaction and not _passes_iteration_gate():
		if debug_print:
			print("[Door] blocked. iters=", _get_iters(), " req=", required_iteration)
		return

	# if you don't want "close on 2nd interact", just ignore toggles when open
	if _is_open and not allow_close_on_second_interact:
		return

	_is_open = not _is_open

	# call_local = server also applies
	rpc("_rpc_apply_state", _is_open)


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_state(open_now: bool) -> void:
	_is_open = open_now

	if _anim == null:
		_anim = get_node_or_null(anim_player_path) as AnimationPlayer

	if _auto_close_timer != null:
		_auto_close_timer.stop()

	if _is_open:
		_play_open()
		_start_auto_close_if_needed()
	else:
		_play_close()


# ============================================================
# helpers
# ============================================================
func _passes_iteration_gate() -> bool:
	return int(_get_iters()) >= required_iteration


func _get_iters() -> int:
	if "iterations" in GlobalVariables:
		return int(GlobalVariables.iterations)
	if "ITERS" in GlobalVariables:
		return int(GlobalVariables.ITERS)
	return 0


func _play_open() -> void:
	if _anim == null:
		return
	var a: String = String(open_anim)
	if _anim.has_animation(a):
		_anim.play(a)
	elif debug_print:
		print("[Door] missing open anim:", a)


func _play_close() -> void:
	if _anim == null:
		return
	var a: String = String(close_anim)
	if _anim.has_animation(a):
		_anim.play(a)
	elif debug_print:
		print("[Door] missing close anim:", a)


func _start_auto_close_if_needed() -> void:
	if not auto_close_enabled:
		return
	if auto_close_seconds <= 0.0:
		return
	if _auto_close_timer == null:
		return
	_auto_close_timer.wait_time = auto_close_seconds
	_auto_close_timer.start()


func _on_auto_close_timeout() -> void:
	# server decides in multiplayer
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not _is_open:
		return

	_is_open = false
	rpc("_rpc_apply_state", _is_open)
