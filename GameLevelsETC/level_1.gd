extends Node3D

@export var player_scene: PackedScene

var peer: ENetMultiplayerPeer
@onready var menu := $Menu/CanvasLayer

func _ready() -> void:
	# make sure UI is clickable until game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# wire once
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)

func _on_host_pressed() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(1027, 32)
	if err != OK:
		push_error("Failed to host: %s" % err)
		return
	multiplayer.multiplayer_peer = peer

	# spawn host locally (authority = host id)
	_spawn_local_player(multiplayer.get_unique_id())
	menu.hide()

func _on_join_pressed() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", 1027)
	if err != OK:
		push_error("Failed to join: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	# wait for connected_to_server before hiding the menu

func _on_connected_ok() -> void:
	menu.hide()
	# server will announce all players to us in _on_peer_connected

func _on_connected_fail() -> void:
	menu.show()
	push_error("Connection failed")

func _on_peer_connected(id: int) -> void:
	# server tells the newcomer about everyone already here,
	# then announces the newcomer to everyone
	if multiplayer.is_server():
		# send existing players to the newcomer
		for child in get_children():
			# use a convention: player nodes are named by their peer id
			if child is Node and child.name.is_valid_int():
				rpc_id(id, "add_player", int(child.name))
		# now announce the new arrival to all (including host)
		rpc("add_player", id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		rpc("del_player", id)
	else:
		# in case the server rpc arrives late/early, also do local cleanup
		del_player(id)

# ---------- SPAWN HELPERS ----------

func _spawn_local_player(id: int) -> void:
	if player_scene == null:
		push_error("player_scene is not assigned in the inspector")
		return
	if has_node(str(id)):
		return
	var p := player_scene.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	add_child(p)

	# simple spacing so players don't overlap on spawn
	if p is Node3D:
		var idx := get_child_count()
		(p as Node3D).global_transform.origin = Vector3(2.0 * float(idx), 2.0, 0.0)

# Called on ALL peers (including the server) to create a player node
@rpc("call_local", "reliable")
func add_player(id: int) -> void:
	_spawn_local_player(id)

# Called on ALL peers (including the server) to delete a player node
@rpc("call_local", "reliable")
func del_player(id: int) -> void:
	var n := get_node_or_null(str(id))
	if n:
		n.queue_free()
