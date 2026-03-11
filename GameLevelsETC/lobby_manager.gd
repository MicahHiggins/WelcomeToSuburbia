extends Node3D
class_name LobbyManager
# Steam lobby + menu logic lives here (GameRoot-level, persists across levels)

@export var player_scene: PackedScene

const APP_ID: int = 480
const MAX_PLAYERS: int = 4
const SERVER_ID: int = 1

var steam_initialized: bool = false
var peer: MultiplayerPeer = null
var current_lobby_id: int = 0

# GameRoot tree refs
@export var menu_root_path: NodePath = NodePath("../Menu")
@export var player_spawner_path: NodePath = NodePath("../PlayerSpawner")
@export var players_root_path: NodePath = NodePath("../PlayersRoot")

# NEW: LevelFlowManager (loads Level1 into LevelContainer and places players)
@export var level_flow_manager_path: NodePath = NodePath("../LevelFlowManager")
var _level_flow: Node = null

var _menu_canvas: CanvasLayer = null
var _pause_menu: CanvasLayer = null
var _pause_lobby_label: Label = null
var _join_code_node: LineEdit = null

var _player_spawner: Node = null
var _players_root: Node3D = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_players_root = get_node_or_null(players_root_path) as Node3D
	if _players_root == null:
		push_error("[LobbyManager] PlayersRoot not found. Fix players_root_path.")
		return

	_player_spawner = get_node_or_null(player_spawner_path)
	if _player_spawner == null:
		push_error("[LobbyManager] PlayerSpawner not found. Fix player_spawner_path.")
		return

	_level_flow = get_node_or_null(level_flow_manager_path)
	if _level_flow == null:
		push_warning("[LobbyManager] LevelFlowManager not found. Fix level_flow_manager_path (needed to load Level1 after joining).")

	_init_menu_refs()
	_init_steam()

	# global multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)


func _process(_delta: float) -> void:
	if steam_initialized:
		Steam.run_callbacks()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if peer == null:
			_capture_mouse(false)
			if _menu_canvas != null:
				_menu_canvas.show()
		else:
			_toggle_pause_menu()


# =========================
#   MENU RESOLVE
# =========================
func _init_menu_refs() -> void:
	var menu_root := get_node_or_null(menu_root_path)
	if menu_root == null:
		push_warning("[LobbyManager] Menu root not found. Fix menu_root_path if you want UI.")
		return

	# Expected:
	# Menu/CanvasLayer
	# Menu/pause
	# Menu/pause/code
	_menu_canvas = menu_root.get_node_or_null("CanvasLayer") as CanvasLayer
	if _menu_canvas == null:
		push_warning("[LobbyManager] Menu/CanvasLayer not found.")
		return

	_pause_menu = menu_root.get_node_or_null("pause") as CanvasLayer
	if _pause_menu == null:
		push_warning("[LobbyManager] Menu/pause not found (pause menu disabled).")
	else:
		_pause_lobby_label = _pause_menu.get_node_or_null("code") as Label
		_pause_menu.hide()

	_join_code_node = _menu_canvas.get_node_or_null("joinCode") as LineEdit
	if _join_code_node == null:
		_join_code_node = _menu_canvas.get_node_or_null("JoinCode") as LineEdit

	if _join_code_node == null:
		for child in _menu_canvas.get_children():
			if child is LineEdit:
				_join_code_node = child as LineEdit
				break

	if _join_code_node == null:
		push_warning("[LobbyManager] Could not find join code LineEdit under Menu/CanvasLayer.")


func _toggle_pause_menu() -> void:
	if _pause_menu == null:
		return

	if _pause_menu.visible:
		_pause_menu.hide()
		_capture_mouse(true)
	else:
		_capture_mouse(false)
		_pause_menu.show()
		_update_pause_lobby_code_display()


func _update_pause_lobby_code_display() -> void:
	if _pause_lobby_label == null or _join_code_node == null:
		return
	_pause_lobby_label.text = _join_code_node.text


# =========================
#       STEAM SETUP
# =========================
func _init_steam() -> void:
	if not Steam.isSteamRunning():
		push_error("Steam is not running. Start Steam before launching the game.")
		return

	var init_result: Dictionary = Steam.steamInitEx(APP_ID, false)
	if init_result.has("status") and int(init_result["status"]) == 0:
		steam_initialized = true
		print("Steamworks initialized. User: %s (%s)" % [
			Steam.getPersonaName(),
			str(Steam.getSteamID())
		])

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
	if not steam_initialized:
		push_error("Steam not initialized; cannot host.")
		return
	print("Requesting Steam lobby creation...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)


func _on_join_pressed() -> void:
	if not steam_initialized:
		push_error("Steam not initialized; cannot join.")
		return
	if _join_code_node == null:
		push_error("JoinCode LineEdit missing; check Menu/CanvasLayer/joinCode.")
		return

	var code_str: String = _join_code_node.text.strip_edges()
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
	if result != 1:
		push_error("Failed to create lobby. Result code: %s" % str(result))
		return

	print("Lobby created successfully. Lobby ID:", lobby_id)
	current_lobby_id = lobby_id

	if _join_code_node != null:
		_join_code_node.text = str(lobby_id)

	Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Lobby")
	_host_game(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions, _locked: bool, chat_response: int) -> void:
	if chat_response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Failed to enter lobby. Response code: %s" % str(chat_response))
		return

	print("Entered lobby successfully. Lobby ID:", lobby_id)
	current_lobby_id = lobby_id
	_join_game(lobby_id)


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

	# ============================================================
	# ✅ CRITICAL FIX (RPC PATH SYNC)
	# Godot's SceneMultiplayer encodes NodePaths in RPC packets.
	# If the multiplayer "root path" differs per peer, Godot can't
	# simplify/resolve paths consistently and you get infinite spam:
	#   - process_simplify_path: node is null
	#   - Invalid packet received. Requested node was not found
	#   - get_node: Node not found: ".../@Node3D@2/..."
	# Force the root to the current scene (your GameRoot).
	# ============================================================
	multiplayer.set_root_path(get_tree().current_scene.get_path())

	print("SteamMultiplayerPeer host created. My unique_id:", multiplayer.get_unique_id())

	# spawn local player through PlayerSpawner (under PlayersRoot)
	_player_spawner.call("spawn_local_player", multiplayer.get_unique_id(), player_scene)

	# NEW: server kicks off the game level load once the lobby is ready
	if _level_flow != null and _level_flow.has_method("on_lobby_ready_server"):
		_level_flow.call("on_lobby_ready_server")

	if _menu_canvas != null:
		_menu_canvas.hide()
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

	# ============================================================
	# ✅ CRITICAL FIX (RPC PATH SYNC)
	# Same reason as host: make sure the root path for RPC node paths
	# matches the host. This prevents @Node3D@X paths + "node not found"
	# loops on clients when level instances differ.
	# ============================================================
	multiplayer.set_root_path(get_tree().current_scene.get_path())

	print("SteamMultiplayerPeer client created. Host SteamID:", host_id)

	# spawn local player through PlayerSpawner (under PlayersRoot)
	_player_spawner.call("spawn_local_player", multiplayer.get_unique_id(), player_scene)

	if _menu_canvas != null:
		_menu_canvas.hide()
	_capture_mouse(true)


# =========================
#   MULTIPLAYER CALLBACKS
# =========================
func _on_connected_ok() -> void:
	print("Multiplayer: connected_to_server")


func _on_connected_fail() -> void:
	print("Multiplayer: connection_failed")
	_capture_mouse(false)
	if _menu_canvas != null:
		_menu_canvas.show()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return

	# send existing player ids to the joining peer
	for child in _players_root.get_children():
		if String(child.name).is_valid_int():
			rpc_id(id, "add_player", int(String(child.name)))

	# then broadcast the new player
	rpc("add_player", id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		rpc("del_player", id)
	else:
		del_player(id)


# =========================
#   RPC: spawn/remove players on all peers
# =========================
@rpc("any_peer", "call_local", "reliable")
func add_player(id: int) -> void:
	_player_spawner.call("spawn_remote_player", id, player_scene)

@rpc("any_peer", "call_local", "reliable")
func del_player(id: int) -> void:
	_player_spawner.call("despawn_player", id)


# =========================
#      PAUSE MENU BUTTONS
# =========================
func _on_pause_quit_pressed() -> void:
	get_tree().quit()


func _on_pause_back_to_menu_pressed() -> void:
	# leave lobby
	if current_lobby_id != 0 and Steam.isSteamRunning():
		Steam.leaveLobby(current_lobby_id)
		current_lobby_id = 0

	# drop peer
	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null

	# despawn all players (under PlayersRoot)
	for child in _players_root.get_children():
		child.queue_free()

	# show menu again
	if _pause_menu != null:
		_pause_menu.hide()
	if _menu_canvas != null:
		_menu_canvas.show()
	_capture_mouse(false)


func _on_pause_copy_code_pressed() -> void:
	var code_text := ""
	if _join_code_node != null:
		code_text = _join_code_node.text
	elif _pause_lobby_label != null:
		code_text = _pause_lobby_label.text

	if code_text == "":
		push_warning("No lobby code to copy.")
		return

	DisplayServer.clipboard_set(code_text)
	print("Lobby code copied to clipboard: ", code_text)


# =========================
#      MOUSE / UI HELPERS
# =========================
func _capture_mouse(capture: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)
