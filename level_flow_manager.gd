extends Node
class_name LevelFlowManager

const SERVER_ID: int = 1

# Where levels get instanced (GameRoot-level)
@export var level_container_path: NodePath = NodePath("../LevelContainer")
@export var players_root_path: NodePath = NodePath("../PlayersRoot")

# Optional: initial level to load once lobby starts
@export var default_level: PackedScene

# Spawn marker inside each level
@export var spawn_marker_path_in_level: NodePath = NodePath("Spawn")

# Small lift so players don't clip floor
@export var spawn_y_lift: float = 1.5

# If true: when a player spawns late, we snap them into the current level spawn.
@export var snap_late_joiners_to_spawn: bool = true

# Cached
var _level_container: Node = null
var _players_root: Node3D = null

var _current_level: Node = null
var _current_level_scene_path: String = ""

# Typed spawn cache
var _has_spawn_xform: bool = false
var _cached_spawn_xform: Transform3D = Transform3D.IDENTITY

# Level-load readiness handshake.
# Fixes "RPC requested node not found" by ensuring clients have the level
# before the server sends RPCs that reference nodes inside the level.
var _ready_peers: Dictionary = {} # int(peer_id) -> bool
var _waiting_for_ready: bool = false


func _ready() -> void:
	_level_container = get_node_or_null(level_container_path)
	if _level_container == null:
		push_error("[LevelFlowManager] LevelContainer not found. Fix level_container_path.")
		return

	_players_root = get_node_or_null(players_root_path) as Node3D
	if _players_root == null:
		push_error("[LevelFlowManager] PlayersRoot not found. Fix players_root_path.")
		return

	# Server re-sends current level to late joiners so their node tree matches.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

	# Optional auto-load (server only in multiplayer)
	if default_level != null:
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				load_level_server(default_level)
		else:
			_load_level_local(default_level)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _current_level_scene_path == "":
		return

	# Send the same level to the new peer (stable name keeps paths consistent)
	rpc_id(peer_id, "_rpc_load_level_all", _current_level_scene_path)


func load_level_server(scene: PackedScene) -> void:
	if scene == null:
		push_error("[LevelFlowManager] load_level_server got null scene.")
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		push_warning("[LevelFlowManager] load_level_server called on a client. Ignoring.")
		return

	# To sync across peers, we need a resource_path.
	var p: String = scene.resource_path
	if p == "":
		push_error("[LevelFlowManager] Level scene has no resource_path. Save it as a .tscn and assign that PackedScene.")
		return

	_current_level_scene_path = p

	# Reset readiness tracking for this load.
	_ready_peers.clear()
	_waiting_for_ready = true

	# Server is tracked too; it will flip to true after it loads locally.
	_ready_peers[multiplayer.get_unique_id()] = false

	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_load_level_all", _current_level_scene_path)
	else:
		_load_level_local(scene)


@rpc("any_peer", "call_local", "reliable")
func _rpc_load_level_all(scene_path: String) -> void:
	if scene_path == "":
		push_error("[LevelFlowManager] Empty scene_path in _rpc_load_level_all.")
		return

	var ps: PackedScene = load(scene_path) as PackedScene
	if ps == null:
		push_error("[LevelFlowManager] Could not load level: " + scene_path)
		return

	_load_level_local(ps)

	# Clients ack to server. The host/server must mark itself ready too.
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_try_finish_ready()
		else:
			rpc_id(SERVER_ID, "_rpc_client_level_ready", scene_path)


@rpc("any_peer", "reliable")
func _rpc_client_level_ready(scene_path: String) -> void:
	# Server receives client acks, then checks if everyone is ready.
	if not multiplayer.is_server():
		return
	if scene_path != _current_level_scene_path:
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return

	_ready_peers[sender] = true
	_server_try_finish_ready()


func _server_try_finish_ready() -> void:
	# Shared server-side "are all peers ready?" check.
	# Called after:
	# 1) server finishes loading locally
	# 2) server receives each client ready ack
	if not multiplayer.is_server():
		return
	if not _waiting_for_ready:
		return

	_ready_peers[multiplayer.get_unique_id()] = (_current_level != null)

	for pid in multiplayer.get_peers():
		if not _ready_peers.has(pid) or _ready_peers[pid] != true:
			return

	_waiting_for_ready = false
	call_deferred("_deferred_server_place_all")


func _load_level_local(scene: PackedScene) -> void:
	# Clear container
	# Change: use immediate free, not queue_free.
	# queue_free is end-of-frame, which can cause name collisions that become "@Node3D@2"
	# and break RPC paths like "LevelContainer/Level1/...".
	var kids: Array = _level_container.get_children()
	for c_any in kids:
		var c: Node = c_any as Node
		if c != null and is_instance_valid(c):
			c.free()

	_current_level = null

	_current_level = scene.instantiate()
	if _current_level == null:
		return

	# Stable level node name across peers.
	# This prevents paths like "@Node3D@2" and stops node-not-found RPC spam.
	var rp: String = scene.resource_path
	var stable_name: String = "Level"
	if rp != "":
		stable_name = rp.get_file().get_basename() # ex: "Level1"
	_current_level.name = stable_name

	_level_container.add_child(_current_level)

	_cache_spawn_transform()

	print("[LevelFlowManager] Loaded level:", scene.resource_path)


func teleport_all_players_to_current_spawn_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_cache_spawn_transform()
	if not _has_spawn_xform:
		return

	# Server tells each owner to teleport their own player.
	var kids: Array = _players_root.get_children()
	for child_any in kids:
		var p: Node3D = child_any as Node3D
		if p == null:
			continue

		var owner_id: int = int(p.get_multiplayer_authority())
		if owner_id <= 0:
			continue

		if p.has_method("server_teleport_to"):
			p.rpc_id(owner_id, "server_teleport_to", _cached_spawn_xform)
		else:
			p.global_transform = _cached_spawn_xform


func on_lobby_ready_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if default_level != null:
		load_level_server(default_level)


func _deferred_server_place_all() -> void:
	teleport_all_players_to_current_spawn_server()


func server_place_player_if_needed(player: Node3D) -> void:
	if player == null:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if not snap_late_joiners_to_spawn:
		return
	if _current_level == null:
		return

	_cache_spawn_transform()
	if not _has_spawn_xform:
		return

	var owner_id: int = int(player.get_multiplayer_authority())
	if owner_id <= 0:
		return

	if player.has_method("server_teleport_to"):
		player.rpc_id(owner_id, "server_teleport_to", _cached_spawn_xform)


func _cache_spawn_transform() -> void:
	_has_spawn_xform = false
	_cached_spawn_xform = Transform3D.IDENTITY

	if _current_level == null:
		return

	var spawn: Node3D = _current_level.get_node_or_null(spawn_marker_path_in_level) as Node3D
	if spawn == null:
		push_error("[LevelFlowManager] Spawn marker not found in level at: " + String(spawn_marker_path_in_level))
		return

	var xform: Transform3D = spawn.global_transform
	xform.origin.y += spawn_y_lift

	_cached_spawn_xform = xform
	_has_spawn_xform = true
