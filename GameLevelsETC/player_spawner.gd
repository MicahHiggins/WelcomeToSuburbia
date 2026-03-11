extends Node3D
class_name PlayerSpawner

@export var players_root_path: NodePath = NodePath("../PlayersRoot")

# LevelFlowManager is GameRoot-level, so keep this as a configurable path
# instead of hardcoding "../LevelFlowManager" (which breaks if you move nodes).
@export var level_flow_manager_path: NodePath = NodePath("../LevelFlowManager")

var _players_root: Node3D = null
var _level_flow: Node = null


func _ready() -> void:
	_players_root = get_node_or_null(players_root_path) as Node3D
	if _players_root == null:
		push_error("[PlayerSpawner] PlayersRoot not found. Fix players_root_path.")
		return

	# Cache LevelFlowManager once (avoid repeated get_node calls).
	_level_flow = get_node_or_null(level_flow_manager_path)


# called by LobbyManager for local spawn (host/client)
func spawn_local_player(id: int, player_scene: PackedScene) -> Node3D:
	return _spawn_player(id, player_scene)

# called by LobbyManager RPC add_player (remote spawn)
func spawn_remote_player(id: int, player_scene: PackedScene) -> Node3D:
	return _spawn_player(id, player_scene)

func despawn_player(id: int) -> void:
	if _players_root == null:
		return
	var n: Node = _players_root.get_node_or_null(str(id))
	if n != null:
		n.queue_free()


func _spawn_player(id: int, player_scene: PackedScene) -> Node3D:
	if _players_root == null:
		return null
	if player_scene == null:
		push_error("[PlayerSpawner] player_scene not set.")
		return null

	# already spawned
	if _players_root.has_node(str(id)):
		var existing: Node = _players_root.get_node(str(id))
		return existing as Node3D if existing is Node3D else null

	var p: Node = player_scene.instantiate()
	if not (p is Node3D):
		push_error("[PlayerSpawner] Player scene root must be Node3D/CharacterBody3D.")
		_players_root.add_child(p)
		return null

	var p3d: Node3D = p as Node3D
	p3d.name = str(id)
	p3d.set_multiplayer_authority(id)
	_players_root.add_child(p3d)

	# temp spawn position (LevelFlowManager will move them to Spawn markers later)
	var idx: int = _players_root.get_child_count()
	p3d.global_transform = Transform3D(Basis(), Vector3(2.0 * float(idx), 2.0, 0.0))

	print("[PlayerSpawner] Spawned player id:", id, " at ", p3d.global_transform.origin)

	# Server-side late-join placement:
	# We call LevelFlowManager so the server tells the owning client to teleport
	# to the current level spawn (after the level-load handshake is complete).
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if _level_flow == null:
			_level_flow = get_node_or_null(level_flow_manager_path)
		if _level_flow != null and _level_flow.has_method("server_place_player_if_needed"):
			_level_flow.call("server_place_player_if_needed", p3d)

	return p3d
