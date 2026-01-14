# NetworkManager.gd
# ------------------
# Lives on the main level scene.
# Handles:
#   - Hosting / joining an ENet server
#   - Spawning Player scenes for each peer
#   - Despawning players when they disconnect
#   - Hiding/showing the main menu and capturing mouse

extends Node

# Player scene to instantiate for each connected peer.
# Make sure this is assigned in the inspector.
@export var player_scene: PackedScene

# Port and server IP for ENet
@export var listen_port: int = 1027
@export var server_ip: String = "127.0.0.1"

# Underlying ENet peer (server or client)
var peer := ENetMultiplayerPeer.new()

# Guard so multiplayer signals are only connected once
var _signals_connected := false


func _ready() -> void:
	# Called when this node enters the scene tree.
	# UI buttons on the menu should be wired to _on_host_pressed / _on_join_pressed.
	# We don't do anything here by default so the menu stays visible.
	pass


# =========================
#   MULTIPLAYER SIGNALS
# =========================
func _connect_mp_signals() -> void:
	# Attach to MultiplayerAPI signals only once.
	if _signals_connected:
		return

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)

	_signals_connected = true


# =========================
#        HOST / JOIN
# =========================
func _on_host_pressed() -> void:
	# Called by the "Host" button in your menu.

	# Ensure MP signals are wired before starting
	_connect_mp_signals()

	# Start an ENet server
	var err := peer.create_server(listen_port, 32)
	if err != OK:
		push_error("Server create failed: %s" % err)
		return

	# Tell Godot to use this ENet peer
	multiplayer.multiplayer_peer = peer

	# Spawn the host player's avatar (server usually has peer id 1)
	_spawn_player(multiplayer.get_unique_id())

	# Hide the menu and capture mouse for FPS controls
	_capture_mouse(true)
	_hide_menu(true)


func _on_join_pressed() -> void:
	# Called by the "Join" button in your menu.

	# Ensure MP signals are wired before connecting
	_connect_mp_signals()

	# Start an ENet client and attempt to connect to server_ip:listen_port
	var err := peer.create_client(server_ip, listen_port)
	if err != OK:
		push_error("Client connect failed: %s" % err)
		return

	# Tell Godot to use this ENet client
	multiplayer.multiplayer_peer = peer

	# We only hide the menu after successful connection
	# in _on_connected_ok, so we don't trap the player if it fails.


# =========================
#  CONNECTION CALLBACKS
# =========================
func _on_connected_ok() -> void:
	# Called on the client when connection to server succeeds.
	_hide_menu(true)
	_capture_mouse(true)


func _on_connected_fail() -> void:
	# Called on the client when connection fails.
	_hide_menu(false)
	_capture_mouse(false)
	push_error("Failed to connect to server.")


func _on_peer_connected(id: int) -> void:
	# Called on ALL peers when a new peer connects.
	# We only spawn the logical Player on the server.
	if multiplayer.is_server():
		_spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	# Called on ALL peers when a peer disconnects.
	if multiplayer.is_server():
		# Server tells everyone to remove that player's node.
		rpc("despawn_player", id)


# =========================
#    SPAWN / DESPAWN
# =========================
func _spawn_player(peer_id: int) -> void:
	# Creates a Player node for the given peer_id on the SERVER.
	# add_child() + RPC below makes it appear on all peers.

	if player_scene == null:
		push_error("player_scene not set.")
		return

	# Avoid duplicate nodes with same name
	if has_node(str(peer_id)):
		return

	var p := player_scene.instantiate()
	p.name = str(peer_id)                     # Name == peer id (e.g. "1", "2", ...)
	p.set_multiplayer_authority(peer_id)      # Authority belongs to that peer

	# Stagger spawn positions in a small grid so players don't overlap
	var idx := get_tree().get_nodes_in_group("player").size()
	var x := 2.0 * float(idx % 5)
	var z := 2.0 * float(idx / 5)

	if "global_transform" in p:
		p.global_transform.origin = Vector3(x, 1.5, z)

	add_child(p)


@rpc("call_local", "reliable")
func despawn_player(id: int) -> void:
	# Called on all peers (server + clients) to remove a player's node.
	if has_node(str(id)):
		get_node(str(id)).queue_free()


# =========================
#   MENU / MOUSE HELPERS
# =========================
func _hide_menu(hide: bool) -> void:
	# Looks for a CanvasLayer as the menu root (e.g. your UI with Host/Join).
	var menu := $CanvasLayer if has_node("CanvasLayer") else null
	if menu:
		menu.visible = not hide


func _capture_mouse(capture: bool) -> void:
	# Switches between visible mouse (for UI) and captured mouse (for FPS).
	Input.set_mouse_mode(
		Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	)
