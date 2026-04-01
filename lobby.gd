extends Node3D
class_name LobbyReady

const SERVER_ID: int = 1 # ADDED: host is peer 1 in our setup

@export var level_flow_path: NodePath = NodePath("/root/Main/LevelFlowManager")
@export var min_players_to_start: int = 2

# UI nodes in the lobby scene
@export var start_button_path: NodePath = NodePath("LobbyUI/VoteStart")
@export var status_label_path: NodePath = NodePath("LobbyUI/PlayerCount")

# quick popup label that fades out (LobbyUI/Ready)
@export var ready_popup_label_path: NodePath = NodePath("LobbyUI/Ready")

var _lfm: Node = null
var _start_btn: Button = null
var _status: Label = null
var _ready_popup: Label = null

# server keeps track of who voted
var _votes: Dictionary = {} # int(peer_id) -> bool

# local cache so we know if *this* player already voted (for button color/text)
var _local_peer_id: int = -1


func _ready() -> void:
	_lfm = get_node_or_null(level_flow_path)

	_start_btn = get_node_or_null(start_button_path) as Button
	_status = get_node_or_null(status_label_path) as Label
	_ready_popup = get_node_or_null(ready_popup_label_path) as Label

	_local_peer_id = multiplayer.get_unique_id()

	if _start_btn != null:
		# start hidden until enough players are in
		_start_btn.visible = false
		_start_btn.disabled = true

		# prevents the "pressed already connected" error
		if not _start_btn.pressed.is_connected(_on_start_pressed):
			_start_btn.pressed.connect(_on_start_pressed)

	if _ready_popup != null:
		_ready_popup.visible = false

	_update_status()

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


func _on_peer_change(id: int) -> void:
	# keep vote list clean when people join/leave
	if multiplayer.is_server():
		# if someone joined, add them (not voted yet)
		if not _votes.has(id):
			_votes[id] = false

		# remove votes for peers that no longer exist
		var alive := {}
		alive[multiplayer.get_unique_id()] = true
		for pid in multiplayer.get_peers():
			alive[int(pid)] = true

		for k in _votes.keys():
			if not alive.has(int(k)):
				_votes.erase(k)

		# send the current vote state to everyone so UI stays in sync
		_broadcast_votes()

	_update_status()


func _get_player_count() -> int:
	var players := get_tree().get_nodes_in_group("player")
	return players.size()


func _get_vote_count() -> int:
	var c := 0
	for k in _votes.keys():
		if bool(_votes[k]) == true:
			c += 1
	return c


func _update_status() -> void:
	var count := _get_player_count()
	var votes := _get_vote_count()

	# button hidden until lobby is full
	if _start_btn != null:
		_start_btn.visible = count >= min_players_to_start

	# status text
	if _status != null:
		if _start_btn != null and _start_btn.visible:
			_status.text = "Players: %d / %d   Votes: %d / %d" % [count, min_players_to_start, votes, min_players_to_start]
		else:
			_status.text = "Players: %d / %d" % [count, min_players_to_start]

	_update_button_visuals()


func _update_button_visuals() -> void:
	if _start_btn == null:
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
	# singleplayer: start immediately
	if not multiplayer.has_multiplayer_peer():
		if _lfm != null and _lfm.has_method("request_level_change"):
			_lfm.call("request_level_change", 1)
		return

	# multiplayer: clients send a vote to the server, host just records it
	var my_name := _get_local_display_name()

	if not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_submit_vote", my_name)
		return

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

	# popup for everyone
	rpc("_rpc_show_ready_popup", "%s ready" % display_name)

	_broadcast_votes()

	# if everyone voted, start level 1
	if _get_vote_count() >= min_players_to_start:
		if _lfm != null and _lfm.has_method("request_level_change"):
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


@rpc("any_peer", "call_local", "unreliable")
func _rpc_show_ready_popup(msg: String) -> void:
	if _ready_popup == null:
		return

	_ready_popup.text = msg
	_ready_popup.visible = true

	# reset alpha
	var c := _ready_popup.modulate
	c.a = 1.0
	_ready_popup.modulate = c

	# fade out
	var tw := create_tween()
	tw.tween_property(_ready_popup, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if _ready_popup != null:
			_ready_popup.visible = false
	)


func _get_local_display_name() -> String:
	var pid := multiplayer.get_unique_id()

	# try to pull Steam persona name if Steam singleton exists
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		if steam != null and steam.has_method("getPersonaName"):
			var n := String(steam.call("getPersonaName"))
			if n.strip_edges() != "":
				return n

	return "Player %d" % pid
