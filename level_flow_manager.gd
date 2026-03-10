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

# cached
var _level_container: Node = null
var _players_root: Node3D = null

var _current_level: Node = null
var _current_level_scene_path: String = ""

# typed spawn cache (NO Variant inference)
var _has_spawn_xform: bool = false
var _cached_spawn_xform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_level_container = get_node_or_null(level_container_path)
	if _level_container == null:
		push_error("[LevelFlowManager] LevelContainer not found. Fix level_container_path.")
		return

	_players_root = get_node_or_null(players_root_path) as Node3D
	if _players_root == null:
		push_error("[LevelFlowManager] PlayersRoot not found. Fix players_root_path.")
		return

	# Optional auto-load (server only in multiplayer)
	if default_level != null:
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				load_level_server(default_level)
		else:
			_load_level_local(default_level)


# ============================================================
# PUBLIC: Server-only level load (in multiplayer)
# ============================================================
func load_level_server(scene: PackedScene) -> void:
	if scene == null:
		push_error("[LevelFlowManager] load_level_server got null scene.")
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		push_warning("[LevelFlowManager] load_level_server called on a client. Ignoring.")
		return

	# IMPORTANT: to sync across peers, we need a resource_path
	var p: String = scene.resource_path
	if p == "":
		push_error("[LevelFlowManager] Level scene has no resource_path. Save it as a .tscn and assign that PackedScene.")
		return

	_current_level_scene_path = p

	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_load_level_all", _current_level_scene_path)
	else:
		_load_level_local(scene)


# ============================================================
# RPC: everyone loads the same level scene path
# ============================================================
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

	# singleplayer fallback placement
	if not multiplayer.has_multiplayer_peer():
		_place_all_players_local_to_spawn()


# ============================================================
# LOCAL level load (runs on every peer)
# ============================================================
func _load_level_local(scene: PackedScene) -> void:
	# clear container
	var kids: Array[Node] = _level_container.get_children()
	for c: Node in kids:
		c.queue_free()

	_current_level = scene.instantiate()
	_level_container.add_child(_current_level)

	# cache spawn transform for quick access (typed)
	_cache_spawn_transform()

	print("[LevelFlowManager] Loaded level:", scene.resource_path)


# ============================================================
# SERVER: teleport everyone to spawn (owning client applies teleport)
# ============================================================
func teleport_all_players_to_current_spawn_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_cache_spawn_transform()
	if not _has_spawn_xform:
		return

	# server tells each owner to teleport their own player
	var kids: Array[Node] = _players_root.get_children()
	for child: Node in kids:
		var p: Node3D = child as Node3D
		if p == null:
			continue

		var owner_id: int = int(p.get_multiplayer_authority())
		if owner_id <= 0:
			continue

		if p.has_method("server_teleport_to"):
			p.rpc_id(owner_id, "server_teleport_to", _cached_spawn_xform)
		else:
			# fallback: hard set
			p.global_transform = _cached_spawn_xform


# ============================================================
# Call this after lobby starts (server)
# ============================================================
func on_lobby_ready_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if default_level != null:
		load_level_server(default_level)

	# wait 1 frame so the level exists on peers, then place everyone
	call_deferred("_deferred_server_place_all")


func _deferred_server_place_all() -> void:
	teleport_all_players_to_current_spawn_server()


# ============================================================
# Late join support: call this from PlayerSpawner when new player appears
# ============================================================
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


# ============================================================
# Helpers
# ============================================================
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


func _place_all_players_local_to_spawn() -> void:
	_cache_spawn_transform()
	if not _has_spawn_xform:
		return

	var kids: Array[Node] = _players_root.get_children()
	for child: Node in kids:
		var p: Node3D = child as Node3D
		if p == null:
			continue
		p.global_transform = _cached_spawn_xform
