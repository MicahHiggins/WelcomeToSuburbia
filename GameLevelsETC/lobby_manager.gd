extends Node3D
class_name LobbyManager

@onready var menu_root = $"../Menu"
@onready var main_menu = $"../Menu/CanvasLayer"
@onready var pause_menu = $"../Menu/pause"
@onready var settings_menu = $"../Menu/SettingsMenu"
# Steam lobby + menu logic lives here (GameRoot-level, persists across levels)


#@onready var page_flip: AudioStreamPlayer = $"../UI Sounds/PageFlip"
@export var player_scene: PackedScene

const APP_ID: int = 480
const MAX_PLAYERS: int = 4
const SERVER_ID: int = 1

# ------------------------------------------------------------
# 4-digit join code system
# ------------------------------------------------------------
const LOBBY_CODE_KEY: String = "join_code"
@export var join_code_digits: int = 4
@export var join_code_allow_leading_zeros: bool = true
@export var join_code_search_worldwide: bool = true
@export var debug_join_code: bool = false

var _pending_join_code: String = ""

var steam_initialized: bool = false
var peer: MultiplayerPeer = null
var current_lobby_id: int = 0

# GameRoot tree refs
@export var menu_root_path: NodePath = NodePath("../Menu")
@export var player_spawner_path: NodePath = NodePath("../PlayerSpawner")
@export var players_root_path: NodePath = NodePath("../PlayersRoot")

# LevelFlowManager (loads Level1 into LevelContainer and places players)
@export var level_flow_manager_path: NodePath = NodePath("../LevelFlowManager")
var _level_flow: Node = null

var _menu_canvas: CanvasLayer = null
var _pause_menu: CanvasLayer = null
var _pause_lobby_label: Label = null
var _join_code_node: LineEdit = null

var _player_spawner: Node = null
var _players_root: Node3D = null

# ------------------------------------------------------------
# Pause menu LevelSelect buttons 
# Menu/pause/LevelSelect/lvl1Button
# Menu/pause/LevelSelect/lvl2Button
# Menu/pause/LevelSelect/lvl3Button
# ------------------------------------------------------------
@export var level_select_root_path: NodePath = NodePath("../Menu/pause/LevelSelect")
@export var lvl1_button_name: StringName = &"lvl1Button"
@export var lvl2_button_name: StringName = &"lvl2Button"
@export var lvl3_button_name: StringName = &"lvl3Button"

var _lvl1_btn: Button = null
var _lvl2_btn: Button = null
var _lvl3_btn: Button = null

# ============================================================
# PRESS ANY BUTTON INTRO (INSPECTOR-DRIVEN)
# ============================================================
@export var use_press_any_intro: bool = true

# Drag your AnimationPlayer here in inspector (inside Menu/CanvasLayer somewhere)
@export var intro_anim_player: AnimationPlayer = null
@export var intro_anim_name: StringName = &"postcard switch"

# Drag ONLY the UI you want hidden until the intro finishes:
# Host / Join / Quit buttons, JoinCode LineEdit, etc.

@export var intro_gate_nodes: Array[CanvasItem] = []

# “Press Any Key” prompt (will hide when intro starts)
@export var press_any_node: CanvasItem = null

var _intro_started: bool = false
var _intro_finished: bool = false


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

	# hook up pause menu level select buttons
	_init_level_select_buttons()

	# press-any intro setup (ONLY hides the nodes you drag into intro_gate_nodes)
	_init_press_any_intro()

	# global multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)


func _process(_delta: float) -> void:
	if steam_initialized:
		Steam.run_callbacks()


func _unhandled_input(event: InputEvent) -> void:
	# Gate everything until intro is done
	if use_press_any_intro and not _intro_finished:
		if _event_counts_as_any_press(event):
			_start_intro()
		return

	# existing behavior after intro
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

	# (Optional) If your buttons are connected via the editor already, leave them.
	# If not, you can connect Host/Join/Quit in editor to these methods:
	# - _on_host_pressed
	# - _on_join_pressed
	# - _on_pause_quit_pressed (or Quit button can just call get_tree().quit())


# =========================
#   INTRO (PRESS ANY)
# =========================
func _init_press_any_intro() -> void:
	if not use_press_any_intro:
		_intro_finished = true
		return

	_intro_started = false
	_intro_finished = false

	# IMPORTANT:
	# - We do NOT hide the whole CanvasLayer.
	# - We ONLY hide the nodes in intro_gate_nodes.
	_set_gate_nodes_visible(false)

	
	if press_any_node != null:
		press_any_node.visible = true

	# Auto-wire the anim finished signal if we have an anim player
	if intro_anim_player != null:
		if not intro_anim_player.animation_finished.is_connected(_on_intro_anim_finished):
			intro_anim_player.animation_finished.connect(_on_intro_anim_finished)


func _event_counts_as_any_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _start_intro() -> void:
	if _intro_started:
		return
	_intro_started = true

	if press_any_node != null:
		press_any_node.visible = false

	# If no anim player, just instantly reveal UI
	if intro_anim_player == null:
		_finish_intro()
		return

	var a := String(intro_anim_name)
	
	
	if a == "" or not intro_anim_player.has_animation(a):
		push_warning("[LobbyManager] Intro animation missing: " + a)
		_finish_intro()
		return

	# Play intro animation. We do NOT hide the animated nodes, so the result stays on screen.
	intro_anim_player.play(a)


func _on_intro_anim_finished(anim: StringName) -> void:
	# Only finish when our intro anim finishes
	if String(anim) != String(intro_anim_name):
		return
	_finish_intro()


func _finish_intro() -> void:
	_intro_finished = true
	_set_gate_nodes_visible(true)
	# Leave the animation result visible; we do nothing to your title/animated nodes.


func _set_gate_nodes_visible(on: bool) -> void:
	for n in intro_gate_nodes:
		if n != null:
			n.visible = on


# ------------------------------------------------------------
# pause menu LevelSelect wiring
# ------------------------------------------------------------
func _init_level_select_buttons() -> void:
	var ls_root: Node = get_node_or_null(level_select_root_path)
	if ls_root == null:
		push_warning("[LobbyManager] LevelSelect root not found. Fix level_select_root_path.")
		return

	_lvl1_btn = ls_root.get_node_or_null(NodePath(String(lvl1_button_name))) as Button
	_lvl2_btn = ls_root.get_node_or_null(NodePath(String(lvl2_button_name))) as Button
	_lvl3_btn = ls_root.get_node_or_null(NodePath(String(lvl3_button_name))) as Button

	if _lvl1_btn != null and not _lvl1_btn.pressed.is_connected(_on_lvl1_pressed):
		_lvl1_btn.pressed.connect(_on_lvl1_pressed)
	if _lvl2_btn != null and not _lvl2_btn.pressed.is_connected(_on_lvl2_pressed):
		_lvl2_btn.pressed.connect(_on_lvl2_pressed)
	if _lvl3_btn != null and not _lvl3_btn.pressed.is_connected(_on_lvl3_pressed):
		_lvl3_btn.pressed.connect(_on_lvl3_pressed)

func _on_lvl1_pressed() -> void:
	_request_level_change(1)

func _on_lvl2_pressed() -> void:
	_request_level_change(2)

func _on_lvl3_pressed() -> void:
	_request_level_change(3)

func _request_level_change(level_index: int) -> void:
	if _level_flow == null:
		push_warning("[LobbyManager] Cannot change level; LevelFlowManager missing.")
		return

	if _level_flow.has_method("request_level_change"):
		_level_flow.call("request_level_change", level_index)
	else:
		push_warning("[LobbyManager] LevelFlowManager missing request_level_change(level_index).")


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
		Steam.lobby_match_list.connect(_on_lobby_match_list)
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
	GlobalVariables.menuMusic.emit()
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
		push_error("Enter a 4-digit code.")
		return
	if not code_str.is_valid_int():
		push_error("Join code must be numeric.")
		return

	code_str = _normalize_join_code(code_str)
	if code_str == "":
		push_error("Join code must be %d digits." % join_code_digits)
		return
	GlobalVariables.menuMusic.emit()
	_find_lobby_by_4_digit_code(code_str)


# =========================
#   4-DIGIT CODE HELPERS
# =========================
func _normalize_join_code(code_str: String) -> String:
	var s := code_str.strip_edges()
	if not s.is_valid_int():
		return ""
	if s.length() > join_code_digits:
		return ""

	if join_code_allow_leading_zeros:
		while s.length() < join_code_digits:
			s = "0" + s
	else:
		if s.length() != join_code_digits:
			return ""

	return s


func _make_join_code_4_digit() -> String:
	var digits := maxi(1, join_code_digits)
	var max_val := 1
	for _i in range(digits):
		max_val *= 10

	var v := randi() % max_val
	var s := str(v)
	if join_code_allow_leading_zeros:
		while s.length() < digits:
			s = "0" + s
	return s


func _find_lobby_by_4_digit_code(code: String) -> void:
	_pending_join_code = code

	if join_code_search_worldwide and Steam.has_method("addRequestLobbyListDistanceFilter"):
		Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)

	Steam.addRequestLobbyListStringFilter(LOBBY_CODE_KEY, code, 0)

	if debug_join_code:
		print("[LobbyManager] searching lobby list for code=", code)

	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	var code := _pending_join_code
	_pending_join_code = ""

	if code == "":
		return

	if lobbies != null and lobbies.size() > 0:
		var lobby_id: int = int(lobbies[0])
		if debug_join_code:
			print("[LobbyManager] found lobby for code ", code, " -> lobby_id=", lobby_id)
		Steam.joinLobby(lobby_id)
		return

	push_error("No lobby found for code: " + code)


# =========================
#     STEAM LOBBY CALLBACKS
# =========================
func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		push_error("Failed to create lobby. Result code: %s" % str(result))
		return

	print("Lobby created successfully. Lobby ID:", lobby_id)
	current_lobby_id = lobby_id

	var join_code := _make_join_code_4_digit()
	Steam.setLobbyData(lobby_id, LOBBY_CODE_KEY, join_code)

	if _join_code_node != null:
		_join_code_node.text = join_code

	Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Lobby")
	_host_game(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions, _locked: bool, chat_response: int) -> void:
	if chat_response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Failed to enter lobby. Response code: %s" % str(chat_response))
		return

	print("Entered lobby successfully. Lobby ID:", lobby_id)
	current_lobby_id = lobby_id

	if _join_code_node != null:
		var code := str(Steam.getLobbyData(lobby_id, LOBBY_CODE_KEY))
		if code != "" and code != "0":
			_join_code_node.text = code

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

	# CRITICAL FIX (RPC PATH SYNC)
	multiplayer.set_root_path(get_tree().current_scene.get_path())

	print("SteamMultiplayerPeer host created. My unique_id:", multiplayer.get_unique_id())

	_player_spawner.call("spawn_local_player", multiplayer.get_unique_id(), player_scene)

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

	# CRITICAL FIX (RPC PATH SYNC)
	multiplayer.set_root_path(get_tree().current_scene.get_path())

	print("SteamMultiplayerPeer client created. Host SteamID:", host_id)

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

	for child in _players_root.get_children():
		if String(child.name).is_valid_int():
			rpc_id(id, "add_player", int(String(child.name)))

	rpc("add_player", id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		rpc("del_player", id)
	else:
		del_player(id)


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
	if current_lobby_id != 0 and Steam.isSteamRunning():
		Steam.leaveLobby(current_lobby_id)
		current_lobby_id = 0

	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null

	for child in _players_root.get_children():
		child.queue_free()

	if _pause_menu != null:
		_pause_menu.hide()
	if _menu_canvas != null:
		_menu_canvas.show()
	_capture_mouse(false)

func _on_pause_settings_pressed() -> void:
	if pause_menu != null:
		pause_menu.hide()

	if settings_menu != null:
		settings_menu.open_from("pause")
	else:
		push_error("SettingsMenu node was not found.")

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
