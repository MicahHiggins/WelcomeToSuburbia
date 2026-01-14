extends Node3D
# Root multiplayer manager / lobby scene.
# Responsibilities:
# - Hosts or joins an ENet server
# - Listens for peer connection/disconnection signals
# - Spawns and removes player instances across all peers

# PackedScene for the Player (set this in the inspector)
@export var player_scene: PackedScene

# Underlying ENet peer object
var peer: ENetMultiplayerPeer

# Simple main menu UI (Host / Join buttons etc.)
@onready var menu := $Menu/CanvasLayer


func _ready() -> void:
	# Ensure the mouse is visible so UI can be clicked before the game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Connect global multiplayer signals (done once)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)


# =========================
#     HOST / JOIN BUTTONS
# =========================

func _on_host_pressed() -> void:
	# Create an ENet server on port 1027 with max 32 clients
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(1027, 32)
	if err != OK:
		push_error("Failed to host: %s" % err)
		return

	# Tell Godot's MultiplayerAPI to use this ENet peer
	multiplayer.multiplayer_peer = peer

	# Spawn the host (server) as a local player
	# multiplayer.get_unique_id() is the server's peer ID
	_spawn_local_player(multiplayer.get_unique_id())

	# Hide the menu once hosting starts
	menu.hide()


func _on_join_pressed() -> void:
	# Create a client ENet peer and try to connect to the host
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", 1027)
	if err != OK:
		push_error("Failed to join: %s" % err)
		return

	# Assign the client peer to Godot's MultiplayerAPI
	multiplayer.multiplayer_peer = peer

	# Menu is hidden only after a successful connection
	# (handled in _on_connected_ok)


# =========================
#   CONNECTION CALLBACKS
# =========================

func _on_connected_ok() -> void:
	# Client successfully connected to server
	menu.hide()
	# Server will later inform this client about existing players
	# via _on_peer_connected -> add_player RPCs


func _on_connected_fail() -> void:
	# Connection attempt failed; restore the menu
	menu.show()
	push_error("Connection failed")


func _on_peer_connected(id: int) -> void:
	# Called on the server whenever a new peer connects.

	if multiplayer.is_server():
		# Step 1: send the newcomer information about all existing players
		for child in get_children():
			# Convention: player nodes are named by their peer ID (e.g. "1", "2", ...)
			if child is Node and child.name.is_valid_int():
				# Tell the newcomer to create a player with this existing ID
				rpc_id(id, "add_player", int(child.name))

		# Step 2: announce the newcomer to everyone (including the host)
		# This RPC triggers add_player on all peers, spawning the new player's node
		rpc("add_player", id)


func _on_peer_disconnected(id: int) -> void:
	# Called when a peer disconnects.

	if multiplayer.is_server():
		# Server tells everyone to delete that player's node
		rpc("del_player", id)
	else:
		# Clients also attempt local cleanup in case RPC ordering is odd
		del_player(id)


# =========================
#        SPAWN HELPERS
# =========================

func _spawn_local_player(id: int) -> void:
	# Instantiates a player scene locally and attaches it under this node.
	# Name is set to the peer ID so _player_for_peer logic can find it.

	if player_scene == null:
		push_error("player_scene is not assigned in the inspector")
		return

	# Avoid spawning a duplicate if a node with this ID already exists
	if has_node(str(id)):
		return

	# Instantiate and configure the player node
	var p := player_scene.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	add_child(p)

	# Basic spawn spacing so players do not overlap at origin
	if p is Node3D:
		var idx := get_child_count()
		(p as Node3D).global_transform.origin = Vector3(2.0 * float(idx), 2.0, 0.0)


# Called on ALL peers (server + every client) to create a player node
@rpc("call_local", "reliable")
func add_player(id: int) -> void:
	_spawn_local_player(id)


# Called on ALL peers (server + every client) to delete a player node
@rpc("call_local", "reliable")
func del_player(id: int) -> void:
	var n := get_node_or_null(str(id))
	if n:
		n.queue_free()
