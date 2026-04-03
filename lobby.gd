# res://LobbyReady.gd
extends Node3D
class_name LobbyReady

const SERVER_ID: int = 1

@export var start_level_scene: PackedScene
@export var allow_force_start_with_one_player: bool = true

# Leave empty to auto-find LevelFlowManager by name
@export var level_flow_path: NodePath = NodePath("")
@export var min_players_to_start: int = 2

# Lobby UI lookup 
@export var lobby_ui_name: StringName = &"LobbyUI"
@export var start_button_name: StringName = &"VoteStart"
@export var force_start_button_name: StringName = &"ForceStart"
@export var status_label_name: StringName = &"PlayerCount"
@export var ready_popup_label_name: StringName = &"Ready"

@export var start_countdown_seconds: int = 5
@export var ready_popup_hold_seconds: float = 2.2
@export var ready_popup_fade_seconds: float = 1.4
@export var countdown_end_hold_seconds: float = 0.75

signal force_start_requested

var _lfm: Node = null


var _ui_root: Node = null
var _start_btn: Button = null
var _force_btn: Button = null
var _status: Label = null
var _ready_popup: Label = null

var _votes: Dictionary = {} # int(peer_id) -> bool
var _local_peer_id: int = -1
var _starting: bool = false
var _popup_tween: Tween = null

var _ui_refresh_accum: float = 0.0
@export var ui_refresh_interval_sec: float = 0.25


func _ready() -> void:
	_local_peer_id = multiplayer.get_unique_id()

	_lfm = _find_level_flow_manager()
	_resolve_lobby_ui_nodes()

	_set_ui_visible(false)

	if _start_btn != null:
		_start_btn.visible = false
		_start_btn.disabled = true
		if not _start_btn.pressed.is_connected(_on_start_pressed):
			_start_btn.pressed.connect(_on_start_pressed)

	if _force_btn != null:
		_force_btn.visible = false
		_force_btn.disabled = false
		_force_btn.text = "Force Start"
		if not _force_btn.pressed.is_connected(_on_force_start_pressed):
			_force_btn.pressed.connect(_on_force_start_pressed)

	if _ready_popup != null:
		_ready_popup.visible = false

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_change):
			multiplayer.peer_connected.connect(_on_peer_change)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_change):
			multiplayer.peer_disconnected.connect(_on_peer_change)

		var host_id: int = multiplayer.get_unique_id()
		if not _votes.has(host_id):
			_votes[host_id] = false

	if not multiplayer.connected_to_server.is_connected(_on_connected_refresh):
		multiplayer.connected_to_server.connect(_on_connected_refresh)

	call_deferred("_deferred_refresh")


func _process(dt: float) -> void:
	_ui_refresh_accum += dt
	if _ui_refresh_accum < ui_refresh_interval_sec:
		return
	_ui_refresh_accum = 0.0

	# UI may not exist yet if level just loaded; keep trying
	if _ui_root == null:
		_resolve_lobby_ui_nodes()

	_update_status()


func _deferred_refresh() -> void:
	_local_peer_id = multiplayer.get_unique_id()
	_resolve_lobby_ui_nodes()
	_on_peer_change(-1)
	_update_status()


func _on_connected_refresh() -> void:
	_local_peer_id = multiplayer.get_unique_id()
	_resolve_lobby_ui_nodes()
	_on_peer_change(-1)
	_update_status()


# ------------------------------------------------------------
# Find LevelFlowManager robustly
# ------------------------------------------------------------
func _find_level_flow_manager() -> Node:
	if String(level_flow_path) != "":
		var n1: Node = get_node_or_null(level_flow_path)
		if n1 != null:
			return n1
		var n2: Node = get_tree().root.get_node_or_null(level_flow_path)
		if n2 != null:
			return n2

	var scene: Node = get_tree().current_scene
	if scene != null:
		var found: Node = scene.find_child("LevelFlowManager", true, false)
		if found != null:
			return found

	return get_tree().root.find_child("LevelFlowManager", true, false)


# ------------------------------------------------------------
# Find LobbyUI inside the loaded lobby level 
# ------------------------------------------------------------
func _resolve_lobby_ui_nodes() -> void:
	_ui_root = null
	_start_btn = null
	_force_btn = null
	_status = null
	_ready_popup = null

	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var ui_any: Node = scene.find_child(String(lobby_ui_name), true, false)
	if ui_any == null:
		ui_any = get_tree().root.find_child(String(lobby_ui_name), true, false)
	if ui_any == null:
		return

	_ui_root = ui_any

	_start_btn = ui_any.get_node_or_null(NodePath(String(start_button_name))) as Button
	_force_btn = ui_any.get_node_or_null(NodePath(String(force_start_button_name))) as Button
	_status = ui_any.get_node_or_null(NodePath(String(status_label_name))) as Label
	_ready_popup = ui_any.get_node_or_null(NodePath(String(ready_popup_label_name))) as Label

	if _start_btn != null and not _start_btn.pressed.is_connected(_on_start_pressed):
		_start_btn.pressed.connect(_on_start_pressed)
	if _force_btn != null and not _force_btn.pressed.is_connected(_on_force_start_pressed):
		_force_btn.pressed.connect(_on_force_start_pressed)


func _set_ui_visible(v: bool) -> void:
	if _ui_root == null:
		return
	if _ui_root is CanvasLayer:
		(_ui_root as CanvasLayer).visible = v
	elif _ui_root is CanvasItem:
		(_ui_root as CanvasItem).visible = v
	elif _ui_root is Node:
		# last resort: try property if present
		if _ui_root.has_method("set_visible"):
			_ui_root.call("set_visible", v)


func _on_peer_change(id: int) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if id != -1 and not _votes.has(id):
			_votes[id] = false

		var alive: Dictionary = {}
		alive[multiplayer.get_unique_id()] = true
		for pid_any in multiplayer.get_peers():
			alive[int(pid_any)] = true

		for k_any in _votes.keys():
			var k: int = int(k_any)
			if not alive.has(k):
				_votes.erase(k)

		_broadcast_votes()

	_update_status()


func _get_player_count() -> int:
	var players: Array = get_tree().get_nodes_in_group("player")
	return players.size()


func _get_vote_count() -> int:
	var c: int = 0
	for k_any in _votes.keys():
		if bool(_votes[k_any]) == true:
			c += 1
	return c


func _update_status() -> void:
	var count: int = _get_player_count()
	var votes: int = _get_vote_count()

	var player_exists: bool = count >= 1
	var lobby_full: bool = count >= min_players_to_start
	var can_force: bool = allow_force_start_with_one_player and count == 1

	_set_ui_visible(player_exists)

	if not player_exists:
		if _status != null:
			_status.text = ""
		if _start_btn != null:
			_start_btn.visible = false
		if _force_btn != null:
			_force_btn.visible = false
		return

	if _status != null:
		if lobby_full:
			_status.text = "Players: %d / %d   Votes: %d / %d" % [count, min_players_to_start, votes, min_players_to_start]
		else:
			_status.text = "Players: %d / %d" % [count, min_players_to_start]

	if _start_btn != null:
		_start_btn.visible = lobby_full

	if _force_btn != null:
		_force_btn.visible = can_force
		_force_btn.disabled = _starting

	_update_button_visuals()


func _update_button_visuals() -> void:
	if _start_btn != null:
		if _starting:
			_start_btn.disabled = true
			_start_btn.text = "Starting..."
			_start_btn.modulate = Color(1, 1, 1, 1)
			return

		if _get_player_count() < min_players_to_start:
			_start_btn.disabled = true
			_start_btn.text = "Vote to Start"
			_start_btn.modulate = Color(1, 1, 1, 1)
			return

		var i_voted: bool = false
		if _local_peer_id != -1 and _votes.has(_local_peer_id):
			i_voted = bool(_votes[_local_peer_id])

		if i_voted:
			_start_btn.text = "Voted ✓"
			_start_btn.disabled = true
			_start_btn.modulate = Color(0.55, 1.0, 0.55, 1.0)
		else:
			_start_btn.text = "Vote to Start"
			_start_btn.disabled = false
			_start_btn.modulate = Color(1, 1, 1, 1)

	if _force_btn != null:
		_force_btn.text = "Starting..." if _starting else "Force Start"


func _on_start_pressed() -> void:
	if _starting:
		return

	var my_name: String = _get_local_display_name()

	if not multiplayer.has_multiplayer_peer():
		_starting = true
		_update_button_visuals()
		await _do_countdown_local(start_countdown_seconds)
		_try_start_scene_server()
		return

	if not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_submit_vote", my_name)
		return

	_register_vote(multiplayer.get_unique_id(), my_name)


func _on_force_start_pressed() -> void:
	request_force_start()


func request_force_start() -> void:
	emit_signal("force_start_requested")

	if _starting:
		return
	if not allow_force_start_with_one_player:
		return
	if _get_player_count() != 1:
		return

	_starting = true
	_update_button_visuals()

	await _do_countdown_local(start_countdown_seconds)
	_try_start_scene_server()


@rpc("any_peer", "reliable")
func _rpc_submit_vote(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_register_vote(sender, display_name)


func _register_vote(peer_id: int, display_name: String) -> void:
	if not multiplayer.is_server():
		return

	if _get_player_count() < min_players_to_start:
		_broadcast_votes()
		return

	if _votes.has(peer_id) and bool(_votes[peer_id]) == true:
		_broadcast_votes()
		return

	_votes[peer_id] = true

	rpc("_rpc_show_ready_popup", "%s ready" % display_name)
	_broadcast_votes()

	if _get_vote_count() >= min_players_to_start and not _starting:
		_starting = true
		rpc("_rpc_set_starting", true)
		rpc("_rpc_start_countdown", start_countdown_seconds)

		await _server_wait_seconds(float(start_countdown_seconds) + countdown_end_hold_seconds)
		_try_start_scene_server()


func _try_start_scene_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if start_level_scene == null:
		push_warning("[LobbyReady] start_level_scene is empty. Drag a scene into it in the inspector.")
		_starting = false
		_update_status()
		return

	if _lfm == null:
		_lfm = _find_level_flow_manager()
	if _lfm == null:
		push_warning("[LobbyReady] LevelFlowManager not found, can't start.")
		_starting = false
		_update_status()
		return

	if _lfm.has_method("load_level_server"):
		_lfm.call("load_level_server", start_level_scene)
	else:
		push_warning("[LobbyReady] LevelFlowManager missing load_level_server(scene).")
		_starting = false
		_update_status()


func _broadcast_votes() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	var payload: Array = []
	for k_any in _votes.keys():
		payload.append([int(k_any), bool(_votes[k_any])])

	rpc("_rpc_apply_votes", payload)


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_votes(payload: Array) -> void:
	_votes.clear()
	for entry_any in payload:
		if typeof(entry_any) != TYPE_ARRAY:
			continue
		var a: Array = entry_any
		if a.size() != 2:
			continue
		_votes[int(a[0])] = bool(a[1])

	_update_status()


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_starting(v: bool) -> void:
	_starting = v
	_update_button_visuals()


@rpc("any_peer", "call_local", "reliable")
func _rpc_start_countdown(seconds: int) -> void:
	if not is_inside_tree():
		return
	await _do_countdown_local(seconds)


func _do_countdown_local(seconds: int = 3) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if _ready_popup == null:
		return

	_ready_popup.visible = true
	_ready_popup.modulate = Color(1, 1, 1, 1)

	for i: int in range(seconds, 0, -1):
		if not is_inside_tree():
			return
		_ready_popup.text = "Starting in %d..." % i
		await tree.create_timer(1.0).timeout

	_ready_popup.text = "Starting..."
	await tree.create_timer(countdown_end_hold_seconds).timeout
	_ready_popup.visible = false


func _server_wait_seconds(s: float) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.create_timer(s).timeout


@rpc("any_peer", "call_local", "unreliable")
func _rpc_show_ready_popup(msg: String) -> void:
	if _ready_popup == null:
		return

	if _popup_tween != null and is_instance_valid(_popup_tween):
		_popup_tween.kill()
	_popup_tween = null

	_ready_popup.text = msg
	_ready_popup.visible = true

	var c: Color = _ready_popup.modulate
	c.a = 1.0
	_ready_popup.modulate = c

	_popup_tween = create_tween()
	_popup_tween.tween_interval(ready_popup_hold_seconds)
	_popup_tween.tween_property(_ready_popup, "modulate:a", 0.0, ready_popup_fade_seconds)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	_popup_tween.tween_callback(func() -> void:
		if _ready_popup != null and not _starting:
			_ready_popup.visible = false
	)


func _get_local_display_name() -> String:
	var pid: int = multiplayer.get_unique_id()
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		if steam != null and steam.has_method("getPersonaName"):
			var n: String = String(steam.call("getPersonaName"))
			if n.strip_edges() != "":
				return n
	return "Player %d" % pid
