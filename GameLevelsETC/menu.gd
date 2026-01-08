# NetworkManager.gd
extends Node

@export var player_scene: PackedScene
@export var listen_port: int = 1027
@export var server_ip: String = "127.0.0.1"

var peer := ENetMultiplayerPeer.new()
var _signals_connected := false

func _ready() -> void:
	# Optional: keep menu visible until we host/join
	# Ensure buttons call _on_host_pressed / _on_join_pressed
	pass

func _connect_mp_signals() -> void:
	if _signals_connected:
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	_signals_connected = true

func _on_host_pressed() -> void:
	_connect_mp_signals()
	var err := peer.create_server(listen_port, 32)
	if err != OK:
		push_error("Server create failed: %s" % err)
		return
	multiplayer.multiplayer_peer = peer

	# Spawn host player (server is usually peer id 1)
	_spawn_player(multiplayer.get_unique_id())
	_capture_mouse(true)
	_hide_menu(true)

func _on_join_pressed() -> void:
	_connect_mp_signals()
	var err := peer.create_client(server_ip, listen_port)
	if err != OK:
		push_error("Client connect failed: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	# We hide menu only after connected_to_server
	# to avoid trapping user if connection fails.

func _on_connected_ok() -> void:
	_hide_menu(true)
	_capture_mouse(true)

func _on_connected_fail() -> void:
	_hide_menu(false)
	_capture_mouse(false)
	push_error("Failed to connect to server.")

func _on_peer_connected(id: int) -> void:
	# Server will spawn remote players on connect.
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		rpc("despawn_player", id)

func _spawn_player(peer_id: int) -> void:
	if player_scene == null:
		push_error("player_scene not set.")
		return
	if has_node(str(peer_id)):
		return

	var p := player_scene.instantiate()
	p.name = str(peer_id)
	p.set_multiplayer_authority(peer_id)
	# Stagger spawns slightly so they don't collide
	var idx := get_tree().get_nodes_in_group("player").size()
	var x := 2.0 * float(idx % 5)
	var z := 2.0 * float(idx / 5)
	if "global_transform" in p:
		p.global_transform.origin = Vector3(x, 1.5, z)

	add_child(p)

@rpc("call_local", "reliable")
func despawn_player(id: int) -> void:
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func _hide_menu(hide: bool) -> void:
	var menu := $CanvasLayer if has_node("CanvasLayer") else null
	if menu:
		menu.visible = not hide

func _capture_mouse(capture: bool) -> void:
	Input.set_mouse_mode(
		Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	)
