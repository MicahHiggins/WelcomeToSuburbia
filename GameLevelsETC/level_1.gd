extends Node3D
# Root multiplayer manager / lobby scene using SteamMultiplayerPeer.
# Responsibilities:
# - Initializes Steam (via GodotSteam)
# - Creates / joins Steam lobbies
# - Creates a SteamMultiplayerPeer host/client
# - Spawns and removes Player instances across all peers

# Player scene used for each connected peer (set this in the inspector).
@export var player_scene: PackedScene

# Steam test App ID (Spacewar). Replace with your own later.
const APP_ID: int = 480
const MAX_PLAYERS: int = 4

# Track whether Steamworks was initialized OK.
var steam_initialized: bool = false

# The actual MultiplayerPeer (SteamMultiplayerPeer under the hood).
var peer: MultiplayerPeer = null

# Simple main menu UI (Host / Join etc.)
@onready var menu: CanvasLayer = $Menu/CanvasLayer

# LineEdit for entering / showing the lobby ID.
@onready var join_code_node: LineEdit = null


func _ready() -> void:
	# UI needs mouse visible before game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Initialize Steam / GodotSteam
	_init_steam()

	# Resolve JoinCode node robustly
	_init_join_code_node()

	# Connect global multiplayer signals (works with SteamMultiplayerPeer too)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)


func _process(_delta: float) -> void:
	# GodotSteam needs its callbacks pumped every frame.
	if steam_initialized:
		Steam.run_callbacks()


func _unhandled_input(event: InputEvent) -> void:
	# ESC to free mouse + show menu again
	if event.is_action_pressed("ui_cancel"):
		_capture_mouse(false)
		if menu:
			menu.show()


# =========================
#   RESOLVE JOINCODE NODE
# =========================
func _init_join_code_node() -> void:
	if menu == null:
		push_error("Menu/CanvasLayer not found; cannot resolve JoinCode LineEdit.")
		return

	var canvas := menu

	# 1) Try 'joinCode'
	var node := canvas.get_node_or_null("joinCode")
	# 2) Try 'JoinCode'
	if node == null:
		node = canvas.get_node_or_null("JoinCode")
	# 3) Fallback: first LineEdit child under CanvasLayer
	if node == null:
		for child in canvas.get_children():
			if child is LineEdit:
				node = child
				break

	if node == null:
		push_error("Could not find a LineEdit for lobby join code under Menu/CanvasLayer.")
		return

	join_code_node = node as LineEdit
	print("JoinCode LineEdit resolved as: ", join_code_node.get_path())


# =========================
#       STEAM SETUP
# =========================
func _init_steam() -> void:
	# Make sure Steam client is running
	if not Steam.isSteamRunning():
		push_error("Steam is not running. Start Steam before launching the game.")
		return

	# Initialize Steamworks with APP_ID
	var init_result: Dictionary = Steam.steamInitEx(APP_ID, false)
	if init_result.has("status") and int(init_result["status"]) == 0:
		steam_initialized = true
		print("Steamworks initialized. User: %s (%s)" % [
			Steam.getPersonaName(),
			str(Steam.getSteamID())
		])

		# Hook up Steam lobby signals
		Steam.lobby_created.connect(_on_lobby_created)
		Steam.lobby_joined.connect(_on_lobby_joined)
	else:
		steam_initialized = false
		var msg: String = str(init_result.get("verbal", "Unknown error"))
		push_error("Failed to initialize Steamworks: %s" % msg)


# =========================
#     HOST / JOIN BUTTONS
# =========================
func _on_host_pressed() -> void:
	# Host button -> Steam.createLobby -> _on_lobby_created -> _host_game()

	if not steam_initialized:
		push_error("Steam not initialized; cannot host.")
		return

	print("Requesting Steam lobby creation...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)


func _on_join_pressed() -> void:
	# Join button -> Steam.joinLobby -> _on_lobby_joined -> _join_game()

	if not steam_initialized:
		push_error("Steam not initialized; cannot join.")
		return

	if join_code_node == null:
		push_error("JoinCode LineEdit missing; could not resolve it under Menu/CanvasLayer.")
		return

	var code_str: String = join_code_node.text.strip_edges()
	if code_str == "":
		push_error("Enter a lobby ID first.")
		return
	if not code_str.is_valid_int():
		push_error("Join code must be a numeric Steam lobby ID.")
		return

	var lobby_id: int = int(code_str)
	print("Requesting to join Steam lobby: ", lobby_id)
	Steam.joinLobby(lobby_id)


# =========================
#     STEAM LOBBY CALLBACKS
# =========================
func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result == 1:
		print("Lobby created successfully. Lobby ID:", lobby_id)

		if join_code_node != null:
			join_code_node.text = str(lobby_id)

		Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Lobby")

		_host_game(lobby_id)
	else:
		push_error("Failed to create lobby. Result code: %s" % str(result))


func _on_lobby_joined(
		lobby_id: int,
		_permissions,
		_locked: bool,
		chat_response: int
	) -> void:
	if chat_response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Entered lobby successfully. Lobby ID:", lobby_id)
		_join_game(lobby_id)
	else:
		push_error("Failed to enter lobby. Response code: %s" % str(chat_response))


# =========================
#     START HOST / CLIENT
# =========================
func _host_game(_lobby_id: int) -> void:
	if peer != null:
		return

	var steam_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var err: int = steam_peer.create_host()
	if err != OK:
		push_error("SteamMultiplayerPeer.create_host failed with code: %d" % err)
		return

	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	print("SteamMultiplayerPeer host created. My unique_id:", multiplayer.get_unique_id())

	var p := _spawn_local_player(multiplayer.get_unique_id())
	if p == null:
		push_error("Failed to spawn local player on host.")
		return

	if menu:
		menu.hide()
	_capture_mouse(true)


func _join_game(lobby_id: int) -> void:
	if peer != null:
		return

	var steam_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var host_id: int = Steam.getLobbyOwner(lobby_id)
	var err: int = steam_peer.create_client(host_id)
	if err != OK:
		push_error("SteamMultiplayerPeer.create_client failed with code: %d" % err)
		return

	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	print("SteamMultiplayerPeer client created. Host SteamID:", host_id)

	var p := _spawn_local_player(multiplayer.get_unique_id())
	if p == null:
		push_error("Failed to spawn local player on client.")
		return

	if menu:
		menu.hide()
	_capture_mouse(true)


# =========================
#   MULTIPLAYER CALLBACKS
# =========================
func _on_connected_ok() -> void:
	print("Multiplayer: connected_to_server")


func _on_connected_fail() -> void:
	print("Multiplayer: connection_failed")
	_capture_mouse(false)
	if menu:
		menu.show()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for child in get_children():
			if child is Node and child.name.is_valid_int():
				rpc_id(id, "add_player", int(child.name))

		rpc("add_player", id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		rpc("del_player", id)
	else:
		del_player(id)


# =========================
#        SPAWN HELPERS
# =========================
func _spawn_local_player(id: int) -> Node3D:
	if player_scene == null:
		push_error("player_scene not set (assign it in the inspector).")
		return null

	# If already there, just return it
	if has_node(str(id)):
		var existing := get_node(str(id))
		if existing is Node3D:
			return existing as Node3D
		return null

	var p := player_scene.instantiate()
	if not (p is Node3D):
		push_error("player_scene root is not a Node3D/CharacterBody3D.")
		add_child(p)
		return null

	var p3d := p as Node3D
	p3d.name = str(id)
	p3d.set_multiplayer_authority(id)
	add_child(p3d)

	# Simple spawn position
	var idx: int = get_child_count()
	p3d.global_transform.origin = Vector3(2.0 * float(idx), 2.0, 0.0)

	# Try to force this player's camera current, in case Player.gd doesn't yet.
	var cam_node := p3d.get_node_or_null("Head/Camera3D")
	if cam_node is Camera3D:
		(cam_node as Camera3D).current = true

	print("Spawned local player with id:", id, " at ", p3d.global_transform.origin)
	return p3d


@rpc("call_local", "reliable")
func add_player(id: int) -> void:
	_spawn_local_player(id)


@rpc("call_local", "reliable")
func del_player(id: int) -> void:
	var n: Node = get_node_or_null(str(id))
	if n:
		n.queue_free()


# =========================
#      MOUSE / UI HELPERS
# =========================
func _capture_mouse(capture: bool) -> void:
	Input.set_mouse_mode(
		Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	)
