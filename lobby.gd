extends Node3D
class_name LobbyReady

const SERVER_ID: int = 1 # host is peer 1 in our setup

@export var level_flow_path: NodePath = NodePath("/root/Main/LevelFlowManager")
@export var min_players_to_start: int = 2

# UI nodes in the lobby scene
@export var lobby_ui_root_path: NodePath = NodePath("LobbyUI") # hide/show the whole lobby UI
@export var start_button_path: NodePath = NodePath("LobbyUI/VoteStart")
@export var status_label_path: NodePath = NodePath("LobbyUI/PlayerCount")

# shared popup/countdown label (LobbyUI/Ready)
@export var ready_popup_label_path: NodePath = NodePath("LobbyUI/Ready")

@export var start_countdown_seconds: int = 5 # CHANGED: a bit longer by default
@export var ready_popup_hold_seconds: float = 2.2 # ADDED: "X ready" stays up longer
@export var ready_popup_fade_seconds: float = 1.4 # ADDED: slower fade
@export var countdown_end_hold_seconds: float = 0.75 # ADDED: "Starting..." shows a bit longer

var _lfm: Node = null
var _ui_root: CanvasItem = null
var _start_btn: Button = null
var _status: Label = null
var _ready_popup: Label = null

# server keeps track of who voted
var _votes: Dictionary = {} # int(peer_id) -> bool

# local cache so we know if *this* player already voted (for button color/text)
var _local_peer_id: int = -1

# stop double-starts
var _starting: bool = false

# ADDED: used to stop popups from overlapping weirdly
var _popup_tween: Tween = null


func _ready() -> void:
	_lfm = _find_level_flow_manager()

	_ui_root = get_node_or_null(lobby_ui_root_path) as CanvasItem
	_start_btn = get_node_or_null(start_button_path) as Button
	_status = get_node_or_null(status_label_path) as Label
	_ready_popup = get_node_or_null(ready_popup_label_path) as Label

	_local_peer_id = multiplayer.get_unique_id()

	# hide everything until we are ACTUALLY hosted/joined
	if _ui_root != null:
		_ui_root.visible = false

	if _start_btn != null:
		_start_btn.visible = false
		_start_btn.disabled = true
		if not _start_btn.pressed.is_connected(_on_start_pressed):
			_start_btn.pressed.connect(_on_start_pressed)

	if _ready_popup != null:
		_ready_popup.visible = false

	# server listens for joins/leaves
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_change):
			multiplayer.peer_connected.connect(_on_peer_change)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_change):
			multiplayer.peer_disconnected.connect(_on_peer_change)

		# make sure host is tracked for voting
		var host_id := multiplayer.get_unique_id()
		if not _votes.has(host_id):
			_votes[host_id] = false

	# ADDED: refresh when client connects (joiner)
	if not multiplayer.connected_to_server.is_connected(_on_connected_refresh):
		multiplayer.connected_to_server.connect(_on_connected_refresh)

	# ADDED: host does NOT get connected_to_server, so we refresh on the next frame too
	call_deferred("_deferred_refresh_after_host_or_join")

	# one initial refresh (stays hidden if not hosted/joined)
	_update_status()


func _deferred_refresh_after_host_or_join() -> void:
	# If host just created the peer, we want UI to show 1/2 immediately.
	_local_peer_id = multiplayer.get_unique_id()
	_on_peer_change(-1)


func _on_connected_refresh() -> void:
	_local_peer_id = multiplayer.get_unique_id()
	_on_peer_change(-1)


func _find_level_flow_manager() -> Node:
	var n := get_node_or_null(level_flow_path)
	if n != null:
		return n

	var scene := get_tree().current_scene
	if scene != null:
		var found := scene.find_child("LevelFlowManager", true, false)
		if found != null:
			return found

	return null


func _on_peer_change(id: int) -> void:
	# keep vote list clean when people join/leave
	if _is_server_session_active() and multiplayer.is_server():
		if id != -1 and not _votes.has(id):
			_votes[id] = false

		var alive := {}
		alive[multiplayer.get_unique_id()] = true
		for pid in multiplayer.get_peers():
			alive[int(pid)] = true

		for k in _votes.keys():
			if not alive.has(int(k)):
				_votes.erase(k)

		_broadcast_votes()

	_update_status()


# -------------------------
# are we hosted/joined yet?
# -------------------------
func _is_session_active() -> bool:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null:
		return false

	# host counts as active as soon as the peer exists
	if multiplayer.is_server():
		return true

	# clients only count as active once actually connected
	return mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# server-side flavor
func _is_server_session_active() -> bool:
	return multiplayer.multiplayer_peer != null


# lobby player count uses NETWORK peers, not the "player" group
func _get_player_count() -> int:
	if not _is_session_active():
		return 0
	return 1 + multiplayer.get_peers().size()


func _get_vote_count() -> int:
	var c := 0
	for k in _votes.keys():
		if bool(_votes[k]) == true:
			c += 1
	return c


func _update_status() -> void:
	var active := _is_session_active()

	# IMPORTANT: no hosting/joining = UI stays hidden and blank
	if _ui_root != null:
		_ui_root.visible = active

	if not active:
		if _start_btn != null:
			_start_btn.visible = false
		if _status != null:
			_status.text = ""
		return

	# from here on, we are hosted/joined, so show 1/2, 2/2, etc
	var count := _get_player_count()
	var votes := _get_vote_count()
	var lobby_full := count >= min_players_to_start

	if _start_btn != null:
		_start_btn.visible = lobby_full

	if _status != null:
		if lobby_full:
			_status.text = "Players: %d / %d   Votes: %d / %d" % [count, min_players_to_start, votes, min_players_to_start]
		else:
			_status.text = "Players: %d / %d" % [count, min_players_to_start]

	_update_button_visuals()


func _update_button_visuals() -> void:
	if _start_btn == null:
		return

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

	var i_voted := false
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


func _on_start_pressed() -> void:
	if _starting:
		return

	# singleplayer: just start
	if not multiplayer.has_multiplayer_peer():
		_starting = true
		_update_button_visuals()
		await _do_countdown_local(start_countdown_seconds)
		_try_start_level_1_server()
		return

	var my_name := _get_local_display_name()

	# clients send a vote to the server
	if not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_submit_vote", my_name)
		return

	# host vote
	_register_vote(multiplayer.get_unique_id(), my_name)


@rpc("any_peer", "reliable")
func _rpc_submit_vote(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
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

	# popup for everyone (now lasts longer)
	rpc("_rpc_show_ready_popup", "%s ready" % display_name)

	_broadcast_votes()

	# if everyone voted, start countdown + level change
	if _get_vote_count() >= min_players_to_start and not _starting:
		_starting = true
		rpc("_rpc_set_starting", true)
		rpc("_rpc_start_countdown", start_countdown_seconds)

		await _server_wait_seconds(float(start_countdown_seconds) + countdown_end_hold_seconds)
		_try_start_level_1_server()


func _try_start_level_1_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if _lfm == null:
		_lfm = _find_level_flow_manager()

	if _lfm == null:
		push_warning("[LobbyReady] LevelFlowManager not found, can't start.")
		return

	if _lfm.has_method("request_level_change"):
		_lfm.call("request_level_change", 1)


func _broadcast_votes() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	var payload: Array = []
	for k in _votes.keys():
		payload.append([int(k), bool(_votes[k])])

	rpc("_rpc_apply_votes", payload)


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_votes(payload: Array) -> void:
	_votes.clear()
	for entry in payload:
		if typeof(entry) != TYPE_ARRAY:
			continue
		var a: Array = entry
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
	# ADDED: if this node got unloaded, don't crash
	if not is_inside_tree():
		return
	await _do_countdown_local(seconds)


func _do_countdown_local(seconds: int = 3) -> void:
	# ADDED: protect against level switching while we are counting down
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return

	if _ready_popup == null:
		return

	_ready_popup.visible = true
	_ready_popup.modulate = Color(1, 1, 1, 1)

	for i in range(seconds, 0, -1):
		if not is_inside_tree():
			return
		if tree == null:
			return

		_ready_popup.text = "Starting in %d..." % i
		await tree.create_timer(1.0).timeout

	_ready_popup.text = "Starting..."
	await tree.create_timer(countdown_end_hold_seconds).timeout

	if not is_inside_tree():
		return
	_ready_popup.visible = false


func _server_wait_seconds(s: float) -> void:
	# ADDED: don't crash if server swaps levels mid-wait
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(s).timeout


@rpc("any_peer", "call_local", "unreliable")
func _rpc_show_ready_popup(msg: String) -> void:
	if _ready_popup == null:
		return

	# ADDED: stop any old tween so messages don't fight each other
	if _popup_tween != null and is_instance_valid(_popup_tween):
		_popup_tween.kill()
	_popup_tween = null

	_ready_popup.text = msg
	_ready_popup.visible = true

	var c := _ready_popup.modulate
	c.a = 1.0
	_ready_popup.modulate = c

	# ADDED: keep it visible longer, then fade slower
	_popup_tween = create_tween()
	_popup_tween.tween_interval(ready_popup_hold_seconds)
	_popup_tween.tween_property(_ready_popup, "modulate:a", 0.0, ready_popup_fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_callback(func():
		if _ready_popup != null and not _starting:
			_ready_popup.visible = false
	)


func _get_local_display_name() -> String:
	var pid := multiplayer.get_unique_id()

	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		if steam != null and steam.has_method("getPersonaName"):
			var n := String(steam.call("getPersonaName"))
			if n.strip_edges() != "":
				return n

	return "Player %d" % pid
