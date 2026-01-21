# NetworkManager.gd
# ------------------
# Lives on the main level scene.
# Handles:
#   - Hosting / joining a Steam lobby
#   - Creating a SteamMultiplayerPeer (host or client)
#   - Spawning Player scenes for each peer (server authoritative)
#   - Despawning players when they disconnect
#   - Hiding/showing the main menu and capturing mouse
#
# NOTE:
#   - Requires the Steam singleton (GodotSteam or the official Steam extension)
#   - Requires the "SteamMultiplayerPeer" class (Steam MP extension)

extends Node

# Player scene to instantiate for each connected peer.
# Make sure this is assigned in the inspector.
@export var player_scene: PackedScene

# Maximum players allowed in the Steam lobby.
@export var max_players: int = 4

# Optional: If you want to join a specific lobby by code/ID, you can put
# that ID here before pressing Join, or set it from a LineEdit in your UI.
@export var manual_lobby_id: String = ""

# Underlying Steam peer (host or client).
# We don't type it as SteamMultiplayerPeer so the script still compiles
# even if the extension isn't installed; we instantiate via ClassDB.
var peer

# Guard so multiplayer signals are only connected once
var _signals_connected := false
var _steam_signals_connected := false

# Current Steam lobby ID (0 = none)
var current_lobby_id: int = 0


func _ready() -> void:
	# Called when this node enters the scene tree.
	# UI buttons on the menu should be wired to:
	#   - _on_host_pressed()
	#   - _on_join_pressed()
	#
	# We don't hide the menu here so it stays visible at startup.
	_connect_mp_signals()
	_connect_steam_signals()


func _process(_delta: float) -> void:
	# Pump Steam callbacks so lobby events and such get processed.
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		steam.run_callbacks()


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


func _connect_steam_signals() -> void:
	# Attach to Steam-specific lobby signals only once.
	if _steam_signals_connected:
		return

	if not Engine.has_singleton("Steam"):
		push_error("Steam singleton not found. Make sure the Steam plugin is installed and enabled.")
		return

	var steam := Engine.get_singleton("Steam")
	# These signal names may differ depending on the Steam plugin you use.
	# Adjust accordingly if your plugin uses different names.
	steam.lobby_created.connect(_on_steam_lobby_created)
	steam.lobby_match_list.connect(_on_steam_lobby_match_list)
	steam.lobby_joined.connect(_on_steam_lobby_joined)

	_steam_signals_connected = true


# =========================
#        HOST / JOIN
# =========================
func _on_host_pressed() -> void:
	# Called by the "Host" button in your menu.
	if not Engine.has_singleton("Steam"):
		push_error("Steam not available; cannot host via Steam.")
		return

	_connect_mp_signals()
	_connect_steam_signals()

	var steam := Engine.get_singleton("Steam")

	# Create a PUBLIC lobby with max_players slots.
	# Result will come back in _on_steam_lobby_created().
	steam.createLobby(steam.LOBBY_TYPE_PUBLIC, max_players)


func _on_join_pressed() -> void:
	# Called by the "Join" button in your menu.
	if not Engine.has_singleton("Steam"):
		push_error("Steam not available; cannot join via Steam.")
		return

	_connect_mp_signals()
	_connect_steam_signals()

	var steam := Engine.get_singleton("Steam")

	var trimmed := manual_lobby_id.strip_edges()
	if trimmed != "":
		# If you entered a specific lobby ID (e.g. host read it to you),
		# join that lobby directly.
		var lobby_id := int(trimmed)
		current_lobby_id = lobby_id
		steam.joinLobby(lobby_id)
		print("Attempting to join lobby by ID: ", lobby_id)
	else:
		# Otherwise, request a list of available lobbies and auto-join the first one.
		steam.requestLobbyList()
		print("Requesting lobby list from Steam...")


# =========================
#      STEAM CALLBACKS
# =========================
func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	# Called after createLobby(). Result code 1 usually means success.
	if result != 1:
		push_error("Steam lobby creation failed. Result code: %d" % result)
		_hide_menu(false)
		_capture_mouse(false)
		return

	current_lobby_id = lobby_id
	var steam := Engine.get_singleton("Steam")

	# Give the lobby a readable name (e.g., your Steam persona).
	var lobby_name: String = str(steam.getPersonaName()) + "'s Lobby"
	steam.setLobbyData(lobby_id, "name", lobby_name)

	# Create the SteamMultiplayerPeer as the HOST.
	peer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		push_error("SteamMultiplayerPeer class not found. Check your Steam multiplayer extension.")
		return

	peer.create_host()  # Host side
	multiplayer.multiplayer_peer = peer

	# Host spawns their own player immediately (server usually has peer id 1)
	_spawn_player(multiplayer.get_unique_id())

	# Lock in the UI and mouse for game control
	_hide_menu(true)
	_capture_mouse(true)

	# Print lobby ID so you can share it with friends as a "code"
	print("Steam lobby created. Lobby ID (share this as join code): ", lobby_id)


func _on_steam_lobby_match_list(lobbies: Array) -> void:
	# Called after requestLobbyList().
	if lobbies.is_empty():
		push_error("No Steam lobbies found to join.")
		_hide_menu(false)
		_capture_mouse(false)
		return

	# For now, auto-join the first lobby in the list.
	var lobby_id := int(lobbies[0])
	current_lobby_id = lobby_id

	var steam := Engine.get_singleton("Steam")
	steam.joinLobby(lobby_id)
	print("Attempting to join first lobby in list: ", lobby_id)


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, chat_response: int) -> void:
	# Called after joinLobby().
	var steam := Engine.get_singleton("Steam")

	if chat_response != steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Failed to enter Steam lobby. Response code: %d" % chat_response)
		_hide_menu(false)
		_capture_mouse(false)
		return

	current_lobby_id = lobby_id

	# Host SteamID (we connect to this via SteamMultiplayerPeer)
	var host_id: int = steam.getLobbyOwner(lobby_id)

	if peer != null:
		print("Steam peer already exists; ignoring extra join.")
	else:
		peer = ClassDB.instantiate("SteamMultiplayerPeer")
		if peer == null:
			push_error("SteamMultiplayerPeer class not found. Check your Steam multiplayer extension.")
			return

		peer.create_client(host_id)   # Connect to host via Steam P2P
		multiplayer.multiplayer_peer = peer

	print("Joined Steam lobby ", lobby_id, " (host SteamID: ", host_id, ")")

	_hide_menu(true)
	_capture_mouse(true)


# =========================
#  CONNECTION CALLBACKS
# =========================
func _on_connected_ok() -> void:
	# May still be useful with Steam peer; called when MultiplayerAPI
	# reports a successful connection.
	print("Multiplayer connected OK.")


func _on_connected_fail() -> void:
	# Called if MultiplayerAPI reports a failure.
	_hide_menu(false)
	_capture_mouse(false)
	push_error("Failed to connect to server / host.")


func _on_peer_connected(id: int) -> void:
	# Called on ALL peers when a new peer connects.
	# We only spawn the logical Player on the server. Godot's SceneMultiplayer
	# will replicate that node to clients automatically.
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
	# Because SceneMultiplayer replicates children, clients will
	# also see the same Player node appear.

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
