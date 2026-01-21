extends Node3D
# Root multiplayer manager / lobby scene using SteamMultiplayerPeer.
# Responsibilities:
# - Initializes Steam (via GodotSteam)
# - Creates / joins Steam lobbies
# - Creates a SteamMultiplayerPeer host/client
# - Spawns and removes Player instances across all peers

# Player scene used for each connected peer.
@export var player_scene: PackedScene

# Steam test App ID (Spacewar). Replace with your own later.
const APP_ID := 480
const MAX_PLAYERS := 4

# Track whether Steamworks was initialized OK.
var steam_initialized: bool = false

# The actual MultiplayerPeer (SteamMultiplayerPeer under the hood).
var peer: MultiplayerPeer = null

# Simple main menu UI (Host / Join etc.)
@onready var menu: CanvasLayer = $Menu/CanvasLayer

# Node used to show / type the lobby ID.
# Can be a Label or LineEdit – both have a .text property.
@onready var join_code_node: Node = (
	$Menu/CanvasLayer/JoinCode if has_node("Menu/CanvasLayer/JoinCode") else null
)

func _ready() -> void:
	# UI needs mouse visible before game starts
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Initialize Steam / GodotSteam
	_init_steam()

	# Connect SceneMultiplayer signals (generic, works with SteamMultiplayerPeer too)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)


func _process(_delta: float) -> void:
	# GodotSteam needs its callbacks pumped every frame.
	if steam_initialized:
		Steam.run_callbacks()


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
	if init_result.has("status") and init_result["status"] == 0:
		steam_initialized = true
		print("Steamworks initialized. User: %s (%s)" % [
			Steam.getPersonaName(),
			Steam.getSteamID()
		])

		# Hook up Steam lobby signals
		Steam.lobby_created.connect(_on_lobby_created)
		Steam.lobby_joined.connect(_on_lobby_joined)
		# (Optional) Steam.lobby_match_list.connect(...) if you want a list UI
	else:
		steam_initialized = false
		var msg: String = str(init_result.get("verbal", "Unknown error"))
		push_error("Failed to initialize Steamworks: %s" % msg)


# =========================
#     HOST / JOIN BUTTONS
# =========================
func _on_host_pressed() -> void:
	# Called by the Host button in your Menu.
	if not steam_initialized:
		push_error("Steam not initialized; cannot host.")
		return

	print("Requesting Steam lobby creation...")
	# Public lobby, up to MAX_PLAYERS players.
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)


func _on_join_pressed() -> void:
	# Called by the Join button in your Menu.
	if not steam_initialized:
		push_error("Steam not initialized; cannot join.")
		return

	if join_code_node == null or not ("text" in join_code_node):
		push_error("JoinCode node missing or has no .text property.")
		return

	var code_str: String = str(join_code_node.text).strip_edges()
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
	# Called by GodotSteam after Steam.createLobby(...)
	# result == 1 usually means success (Steam.RESULT_OK).
	if result == 1:
		print("Lobby created successfully. Lobby ID:", lobby_id)

		# Show lobby ID in UI so friends can type it as a join code.
		if join_code_node != null and "text" in join_code_node:
			join_code_node.text = str(lobby_id)

		# Optional: give the lobby a human-friendly name
		Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Lobby")

		# Start hosting the actual game
		_host_game(lobby_id)
	else:
		push_error("Failed to create lobby. Result code: %s" % result)


func _on_lobby_joined(
		lobby_id: int,
		_permissions,
		_locked: bool,
		chat_response: int
	) -> void:
	# Called by GodotSteam after Steam.joinLobby(...)
	if chat_response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Entered lobby successfully. Lobby ID:", lobby_id)
		_join_game(lobby_id)
	else:
		push_error("Failed to enter lobby. Response code: %s" % chat_response)


# =========================
#     START HOST / CLIENT
# =========================
func _host_game(_lobby_id: int) -> void:
	# Create the SteamMultiplayerPeer host and set it on SceneMultiplayer.
	if peer != null:
		# Already have a peer; avoid double-hosting.
		return

	var steam_peer: MultiplayerPeer = SteamMultiplayerPeer.new()
	# Per working examples: create_host() takes no arguments.
	steam_peer.create_host()

	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	print("SteamMultiplayerPeer host created.")

	# Hide lobby UI and spawn the host's local player.
	menu.hide()
	_capture_mouse(true)
	_spawn_local_player(multiplayer.get_unique_id())


func _join_game(lobby_id: int) -> void:
	# Create the SteamMultiplayerPeer client and set it on SceneMultiplayer.
	if peer != null:
		# If this was invoked on the host, ignore; host already has a peer.
		return

	var steam_peer: MultiplayerPeer = SteamMultiplayerPeer.new()
	var host_id: int = Steam.getLobbyOwner(lobby_id)
	steam_peer.create_client(host_id)

	peer = steam_peer
	multiplayer.multiplayer_peer = peer
	print("SteamMultiplayerPeer client created. Host SteamID:", host_id)

	menu.hide()
	_capture_mouse(true)
	_spawn_local_player(multiplayer.get_unique_id())


# =========================
#   MULTIPLAYER CALLBACKS
# =========================
func _on_connected_ok() -> void:
	# This may be emitted when the client finishes connecting to the host.
	print("Multiplayer: connected_to_server")


func _on_connected_fail() -> void:
	print("Multiplayer: connection_failed")
	_capture_mouse(false)
	menu.show()


func _on_peer_connected(id: int) -> void:
	# Called on ALL peers when a new peer connects.
	# We only drive spawn logic from the host.
	if multiplayer.is_server():
		# Step 1: send the newcomer info about existing players
		for child in get_children():
			if child is Node and child.name.is_valid_int():
				rpc_id(id, "add_player", int(child.name))

		# Step 2: announce the newcomer to everyone (including host)
		rpc("add_player", id)


func _on_peer_disconnected(id: int) -> void:
	# Called when a peer disconnects.
	if multiplayer.is_server():
		rpc("del_player", id)
	else:
		# Clients also clean up just in case
		del_player(id)


# =========================
#        SPAWN HELPERS
# =========================
func _spawn_local_player(id: int) -> void:
	# Instantiates a Player scene locally and attaches it under this node.
	# Name is set to the peer ID so Player.gd can use name.to_int()
	# as its authority.

	if player_scene == null:
		push_error("player_scene is not assigned in the inspector.")
		return

	# Avoid duplicates
	if has_node(str(id)):
		return

	var p: Node = player_scene.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	add_child(p)

	# Basic spacing so players don't overlap on spawn.
	if p is Node3D:
		var idx: int = get_child_count()
		(p as Node3D).global_transform.origin = Vector3(2.0 * float(idx), 2.0, 0.0)


# Called on ALL peers (server + clients) to create a player node
@rpc("call_local", "reliable")
func add_player(id: int) -> void:
	_spawn_local_player(id)


# Called on ALL peers (server + clients) to delete a player node
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
