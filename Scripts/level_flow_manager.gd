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

# Level Select scenes
@export var level_1_scene: PackedScene = preload("res://Assets/RandomObjects/symbol/SymbolPuzzle.tscn")
@export var level_2_scene: PackedScene = preload("res://GameLevelsETC/kidnap.tscn")
@export var level_3_scene: PackedScene = preload("res://GameLevelsETC/CellarLevel.tscn")

# Cached
var _level_container: Node = null
var _players_root: Node3D = null

var _current_level: Node = null
var _current_level_scene_path: String = ""

# Typed spawn cache
var _has_spawn_xform: bool = false
var _cached_spawn_xform: Transform3D = Transform3D.IDENTITY

# ADDED: optional split spawns under Spawn (Level2 only, but safe for any level)
var _has_split_spawns: bool = false
var _spawn_host_xform: Transform3D = Transform3D.IDENTITY
var _spawn_join_xform: Transform3D = Transform3D.IDENTITY

# Level-load readiness handshake.
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

	rpc_id(peer_id, "_rpc_load_level_all", _current_level_scene_path)


func request_level_change(level_index: int) -> void:
	# Singleplayer: keep your existing behavior
	if not multiplayer.has_multiplayer_peer():
		var ps_local: PackedScene = _scene_for_index(level_index)
		if ps_local == null:
			push_warning("[LevelFlowManager] request_level_change: invalid level index: %d" % level_index)
			return
		_load_level_local(ps_local)
		_place_all_players_local_to_spawn()
		return

	# Multiplayer: server decides
	if multiplayer.is_server():
		_server_change_level(level_index)
	else:
		var mp: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		rpc_id(SERVER_ID, "_rpc_request_level_change", level_index)


@rpc("any_peer", "reliable")
func _rpc_request_level_change(level_index: int) -> void:
	if not multiplayer.is_server():
		return
	_server_change_level(level_index)


func _server_change_level(level_index: int) -> void:
	var ps: PackedScene = _scene_for_index(level_index)
	if ps == null:
		push_warning("[LevelFlowManager] _server_change_level: invalid level index: %d" % level_index)
		return
	load_level_server(ps)
	#if level_index == 2:
		#GlobalVariables.level_2_cutscene.visible = true
		#GlobalVariables.level_2_cutscene.paused = false
		#await get_tree().create_timer(18).timeout
		#GlobalVariables.level_2_cutscene.visible = false


func _scene_for_index(level_index: int) -> PackedScene:
	match level_index:
		1:
			return level_1_scene
		2:
			return level_2_scene
		3:
			return level_3_scene
		_:
			return null


func load_level_server(scene: PackedScene) -> void:
	if scene == null:
		push_error("[LevelFlowManager] load_level_server got null scene.")
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		push_warning("[LevelFlowManager] load_level_server called on a client. Ignoring.")
		return

	var p: String = scene.resource_path
	if p == "":
		push_error("[LevelFlowManager] Level scene has no resource_path. Save it as a .tscn and assign that PackedScene.")
		return

	_current_level_scene_path = p

	_ready_peers.clear()
	_waiting_for_ready = true
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

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_try_finish_ready()
		else:
			rpc_id(SERVER_ID, "_rpc_client_level_ready", scene_path)


@rpc("any_peer", "reliable")
func _rpc_client_level_ready(scene_path: String) -> void:
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
	var kids: Array = _level_container.get_children()
	for c_any in kids:
		var c: Node = c_any as Node
		if c != null and is_instance_valid(c):
			c.free()

	_current_level = null

	_current_level = scene.instantiate()
	if _current_level == null:
		return

	var rp: String = scene.resource_path
	var stable_name: String = "Level"
	if rp != "":
		stable_name = rp.get_file().get_basename()
	_current_level.name = stable_name

	_level_container.add_child(_current_level)

	_cache_spawn_transform()
	_cache_split_spawns() # ADDED

	print("[LevelFlowManager] Loaded level:", scene.resource_path)


func teleport_all_players_to_current_spawn_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_cache_spawn_transform()
	_cache_split_spawns() # ADDED: refresh in case the level changed

	# Server tells each owner to teleport their own player.
	var kids: Array = _players_root.get_children()
	for child_any in kids:
		var p: Node3D = child_any as Node3D
		if p == null:
			continue

		var owner_id: int = int(p.get_multiplayer_authority())
		if owner_id <= 0:
			continue

		# ADDED: if this level has SpawnHost/SpawnJoin under Spawn, split by peer id
		var target_xf: Transform3D = _cached_spawn_xform
		if _has_split_spawns:
			target_xf = _spawn_host_xform if owner_id == SERVER_ID else _spawn_join_xform

		if p.has_method("server_teleport_to"):
			p.rpc_id(owner_id, "server_teleport_to", target_xf)
		else:
			p.global_transform = target_xf


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

	# ADDED: use the same split-spawn logic for late joiners
	_cache_spawn_transform()
	_cache_split_spawns()

	var owner_id: int = int(player.get_multiplayer_authority())
	if owner_id <= 0:
		return

	var target_xf: Transform3D = _cached_spawn_xform
	if _has_split_spawns:
		target_xf = _spawn_host_xform if owner_id == SERVER_ID else _spawn_join_xform

	if player.has_method("server_teleport_to"):
		player.rpc_id(owner_id, "server_teleport_to", target_xf)
	else:
		player.global_transform = target_xf


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


# ADDED: looks for Spawn/SpawnHost and Spawn/SpawnJoin under your existing Spawn node
func _cache_split_spawns() -> void:
	_has_split_spawns = false
	_spawn_host_xform = Transform3D.IDENTITY
	_spawn_join_xform = Transform3D.IDENTITY

	if _current_level == null:
		return

	var spawn: Node3D = _current_level.get_node_or_null(spawn_marker_path_in_level) as Node3D
	if spawn == null:
		return

	var sh: Node3D = spawn.get_node_or_null("SpawnHost") as Node3D
	var sj: Node3D = spawn.get_node_or_null("SpawnJoin") as Node3D

	if sh == null or sj == null:
		return

	_spawn_host_xform = sh.global_transform
	_spawn_join_xform = sj.global_transform

	_spawn_host_xform.origin.y += spawn_y_lift
	_spawn_join_xform.origin.y += spawn_y_lift

	_has_split_spawns = true


# Used by request_level_change singleplayer branch (unchanged)
func _place_all_players_local_to_spawn() -> void:
	_cache_spawn_transform()
	if not _has_spawn_xform:
		return

	var kids: Array = _players_root.get_children()
	for child_any in kids:
		var p: Node3D = child_any as Node3D
		if p == null:
			continue
		p.global_transform = _cached_spawn_xform
