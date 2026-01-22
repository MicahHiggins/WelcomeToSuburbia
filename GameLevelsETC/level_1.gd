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

# Track current lobby so we can leave it when going back to main menu.
var current_lobby_id: int = 0

# Simple main menu UI (Host / Join etc.)
@onready var menu: CanvasLayer = $Menu/CanvasLayer

# Pause / ESC menu UI (you create this in the scene).
# Expected path: PauseMenu/CanvasLayer (or just PauseMenu if it's a CanvasLayer).
@onready var pause_menu: CanvasLayer = $InGameMenu/CanvasLayer

# Label (or other text control) inside the pause menu to show lobby code.
# Expected node name under pause_menu: LobbyCodeLabel
@onready var pause_lobby_label: Label = $InGameMenu/CanvasLayer/lobbycode

# LineEdit for entering / showing the lobby ID on the main menu.
@onready var join_code_node: LineEdit = $Menu/CanvasLayer/joinCode


func _ready() -> void:
	# UI needs mouse visible before game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Initialize Steam / GodotSteam
	_init_steam()

	# Resolve JoinCode node robustly (main menu)
	_init_join_code_node()

	# Resolve pause menu + lobby label (ESC menu)
	_init_pause_menu_ui()

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
	# ESC behavior:
	# - Before connecting (peer == null): show main menu.
	# - After connecting (peer != null): toggle pause menu with lobby code.
	if event.is_action_pressed("ui_cancel"):
		if peer == null:
			# Not in a game yet, just show the main menu.
			_capture_mouse(false)
			if menu:
				menu.show()
		else:
			_toggle_pause_menu()


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
#   PAUSE MENU / LOBBY UI
# =========================
func _init_pause_menu_ui() -> void:
	# Try PauseMenu/CanvasLayer
	if has_node("PauseMenu/CanvasLayer"):
		pause_menu = get_node("PauseMenu/CanvasLayer") as CanvasLayer
	elif has_node("PauseMenu"):
		# Or just PauseMenu if that's already a CanvasLayer
		var n := get_node("PauseMenu")
		if n is CanvasLayer:
			pause_menu = n as CanvasLayer

	if pause_menu == null:
		# Not fatal: you just won't have an ESC menu until you wire it up.
		push_warning("PauseMenu CanvasLayer not found. ESC pause menu will be disabled.")
		return

	# Optional label inside pause menu that displays the lobby code.
	var label_node := pause_menu.get_node_or_null("LobbyCodeLabel")
	if label_node is Label:
		pause_lobby_label = label_node as Label

	# Hide pause menu initially.
	pause_menu.hide()


func _toggle_pause_menu() -> void:
	if pause_menu == null:
		return

	if pause_menu.visible:
		# Close pause menu, recapture mouse
		pause_menu.hide()
		_capture_mouse(true)
	else:
		# Open pause menu, release mouse and update lobby code text
		_capture_mouse(false)
		pause_menu.show()
		_update_pause_lobby_code_display()


func _update_pause_lobby_code_display() -> void:
	if pause_lobby_label == null:
		return
	if join_code_node == null:
		return

	pause_lobby_label.text = join_code_node.text


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
		current_lobby_id = lobby_id

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
		current_lobby_id = lobby_id
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

	# Player.gd will handle camera ownership for the authority player.

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
#      PAUSE MENU BUTTONS
# =========================
func _on_pause_quit_pressed() -> void:
	# Hook this up to a "Quit" button in your pause menu.
	get_tree().quit()


func _on_pause_back_to_menu_pressed() -> void:
	# Hook this up to a "Back to Main Menu" button in your pause menu.
	# 1) Leave lobby if possible (host or client)
	if current_lobby_id != 0 and Steam.isSteamRunning():
		Steam.leaveLobby(current_lobby_id)
		current_lobby_id = 0

	# 2) Drop the multiplayer peer
	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null

	# 3) Remove all player nodes whose names are numeric
	for child in get_children():
		if child.name.is_valid_int():
			child.queue_free()

	# 4) Switch UI: hide pause menu, show main menu, free mouse
	if pause_menu:
		pause_menu.hide()
	if menu:
		menu.show()
	_capture_mouse(false)


func _on_pause_copy_code_pressed() -> void:
	# Hook this up to a "Copy Code" button in your pause menu.
	var code_text := ""
	if join_code_node != null:
		code_text = join_code_node.text
	elif pause_lobby_label != null:
		code_text = pause_lobby_label.text

	if code_text == "":
		push_warning("No lobby code to copy.")
		return

	DisplayServer.clipboard_set(code_text)
	print("Lobby code copied to clipboard: ", code_text)


# =========================
#      MOUSE / UI HELPERS
# =========================
func _capture_mouse(capture: bool) -> void:
	Input.set_mouse_mode(
		Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	)
