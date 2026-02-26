extends Node3D
class_name TeleportManager

# What to spawn under the map
@export var cellar_scene: PackedScene

# Where we instance the cellar (container node in Level1)
@export var cellar_root_path: NodePath = NodePath("../CellarRoot")

# Where to read spawn marker inside the cellar scene
@export var cellar_spawn_marker_path: NodePath = NodePath("SpawnPoints/Spawn")

# Where to place the whole cellar scene (under the map)
@export var cellar_world_offset: Vector3 = Vector3(0, -80, 0)

# --- NEW: fog / atmosphere root to disable when cellar starts ---
# Put your FogVolume / WorldEnvironment / fog parent here (whatever you want to hide)
@export var fog_root_path: NodePath = NodePath("../Fog") # <- set this in inspector

# --- NEW: cellar roles ---
@export var leader_speed_multiplier: float = 0.35  # leader moves slower
@export var follower_height: float = 2.2           # follower hovers above leader
@export var follower_forward_offset: float = 0.25  # tiny offset so they don't clip
@export var server_follow_update_hz: float = 20.0  # how often server pushes follower position

var _cellar_instance: Node3D = null

# role state
var _cellar_active: bool = false
var _leader_peer_id: int = -1
var _follower_peer_ids: Array[int] = []

var _follow_accum: float = 0.0

func _ready() -> void:
	set_process(false)
	set_physics_process(true)

func request_enter_cellar(from_player: Node = null) -> void:
	# SOLO: do it locally (still uses same code paths)
	if not multiplayer.has_multiplayer_peer():
		_ensure_cellar_spawned()
		_local_disable_fog()
		_local_apply_roles_solo()
		return

	# MULTI: server decides and tells everyone
	if multiplayer.is_server():
		_ensure_cellar_spawned()
		_server_begin_cellar(from_player)
	else:
		# client asks server
		rpc_id(1, "_rpc_request_enter_cellar")

@rpc("any_peer", "reliable")
func _rpc_request_enter_cellar() -> void:
	if not multiplayer.is_server():
		return
	_ensure_cellar_spawned()
	var sender_id: int = multiplayer.get_remote_sender_id()
	var sender_player: Node3D = _find_player_by_peer(sender_id)
	_server_begin_cellar(sender_player)

func _server_begin_cellar(from_player: Node = null) -> void:
	# pick leader
	_leader_peer_id = _pick_leader_peer_id(from_player)
	_follower_peer_ids = _pick_followers(_leader_peer_id)

	_cellar_active = true

	# Tell everyone: spawn cellar (if needed), disable fog, teleport and set roles
	rpc("_rpc_enter_cellar_all", _leader_peer_id, leader_speed_multiplier, follower_height, follower_forward_offset)

@rpc("any_peer", "call_local", "reliable")
func _rpc_enter_cellar_all(leader_peer_id: int, leader_mult: float, hover_h: float, fwd_off: float) -> void:
	_ensure_cellar_spawned()
	_local_disable_fog()
	_local_teleport_all_players_to_cellar()

	# Configure local players on THIS peer
	var local_players := get_tree().get_nodes_in_group("player")
	for p in local_players:
		var player := p as Node3D
		if player == null:
			continue

		var pid: int = int(player.get_multiplayer_authority())
		var is_leader: bool = (pid == leader_peer_id)

		# Requires Player.gd RPC hook (below)
		if player.has_method("server_set_cellar_role"):
			player.rpc_id(pid, "server_set_cellar_role", is_leader, leader_mult, hover_h, fwd_off, leader_peer_id)

func _physics_process(delta: float) -> void:
	# Server keeps followers glued above leader
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if not _cellar_active:
		return

	_follow_accum += delta
	var step := 1.0 / maxf(server_follow_update_hz, 1.0)
	if _follow_accum < step:
		return
	_follow_accum = 0.0

	var leader := _find_player_by_peer(_leader_peer_id)
	if leader == null:
		return

	var leader_pos: Vector3 = leader.global_position
	var leader_basis: Basis = (leader as Node3D).global_transform.basis

	# forward offset based on leader facing (uses -Z as forward in Godot)
	var forward: Vector3 = -leader_basis.z.normalized()
	var target_pos: Vector3 = leader_pos + Vector3(0, follower_height, 0) + forward * follower_forward_offset

	# Push forced position to each follower's owning client
	for fid in _follower_peer_ids:
		var fnode := _find_player_by_peer(fid)
		if fnode == null:
			continue
		if fnode.has_method("server_set_forced_pose"):
			# send to OWNER (so only that player snaps itself)
			fnode.rpc_id(fid, "server_set_forced_pose", true, target_pos)

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
	_cellar_instance.global_position = root.global_position + cellar_world_offset

func _local_disable_fog() -> void:
	var fog := get_node_or_null(fog_root_path) as Node
	if fog == null:
		return
	fog.visible = false

func _local_teleport_all_players_to_cellar() -> void:
	if _cellar_instance == null or not is_instance_valid(_cellar_instance):
		return

	var spawn := _cellar_instance.get_node_or_null(cellar_spawn_marker_path) as Node3D
	if spawn == null:
		push_error("[TeleportManager] Spawn marker not found in cellar. Expected SpawnPoints/Spawn.")
		return

	var spawn_pos := spawn.global_position

	for p in get_tree().get_nodes_in_group("player"):
		var player := p as Node3D
		if player == null:
			continue

		player.global_position = spawn_pos + Vector3(0, 3.5, 0)

func _pick_leader_peer_id(from_player: Node) -> int:
	# prefer requester
	var fp := from_player as Node
	if fp != null:
		var a := int(fp.get_multiplayer_authority())
		if a > 0:
			return a

	# else pick lowest peer id among players
	var best := INF
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node
		if n == null:
			continue
		var id := int(n.get_multiplayer_authority())
		if id > 0 and id < best:
			best = id

	return -1 if best == INF else int(best)

func _pick_followers(leader_id: int) -> Array[int]:
	var out: Array[int] = []
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node
		if n == null:
			continue
		var id := int(n.get_multiplayer_authority())
		if id > 0 and id != leader_id:
			out.append(id)
	return out

func _find_player_by_peer(peer_id: int) -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node3D
		if n != null and int(n.get_multiplayer_authority()) == peer_id:
			return n
	return null

func _local_apply_roles_solo() -> void:
	# singleplayer: nothing fancy; just disable fog and keep player normal
	_cellar_active = false
