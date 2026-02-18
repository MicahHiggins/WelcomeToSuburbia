extends Node3D

# What to spawn under the map
@export var cellar_scene: PackedScene

# Where we instance the cellar (container node in Level1)
@export var cellar_root_path: NodePath = NodePath("../CellarRoot")

# Where to read spawn marker inside the cellar scene
@export var cellar_spawn_marker_path: NodePath = NodePath("SpawnPoints/Spawn")

# Where to place the whole cellar scene (under the map)
@export var cellar_world_offset: Vector3 = Vector3(0, -80, 0)

var _cellar_instance: Node3D = null

func request_enter_cellar(from_player: Node = null) -> void:
	# SOLO: just do it locally
	if not multiplayer.has_multiplayer_peer():
		_ensure_cellar_spawned()
		_teleport_all_local_players()
		return

	# MULTI: server decides and tells everyone
	if multiplayer.is_server():
		_ensure_cellar_spawned()
		rpc("_rpc_teleport_everyone_to_cellar")
	else:
		# client asks server
		rpc_id(1, "_rpc_request_enter_cellar")

@rpc("any_peer", "reliable")
func _rpc_request_enter_cellar() -> void:
	if not multiplayer.is_server():
		return
	_ensure_cellar_spawned()
	rpc("_rpc_teleport_everyone_to_cellar")

@rpc("any_peer", "call_local", "reliable")
func _rpc_teleport_everyone_to_cellar() -> void:
	_ensure_cellar_spawned()
	_teleport_all_local_players()

func _ensure_cellar_spawned() -> void:
	if _cellar_instance != null and is_instance_valid(_cellar_instance):
		return

	if cellar_scene == null:
		push_error("[TeleportManager] cellar_scene not assigned.")
		return

	var root := get_node_or_null(cellar_root_path) as Node3D
	if root == null:
		push_error("[TeleportManager] CellarRoot not found. Fix cellar_root_path.")
		return

	_cellar_instance = cellar_scene.instantiate() as Node3D
	if _cellar_instance == null:
		push_error("[TeleportManager] Failed to instance cellar_scene.")
		return

	root.add_child(_cellar_instance)

	# put the whole cellar under the map
	_cellar_instance.global_position = root.global_position + cellar_world_offset

func _teleport_all_local_players() -> void:
	if _cellar_instance == null or not is_instance_valid(_cellar_instance):
		return

	var spawn := _cellar_instance.get_node_or_null(cellar_spawn_marker_path) as Node3D
	if spawn == null:
		push_error("[TeleportManager] Spawn marker not found in cellar. Expected SpawnPoints/Spawn.")
		return

	var spawn_pos := spawn.global_position

	# teleport every player node that exists on THIS peer
	for p in get_tree().get_nodes_in_group("player"):
		var player := p as Node3D
		if player == null:
			continue

		# small y lift so you don't clip
		player.global_position = spawn_pos + Vector3(0, 1.5, 0)
