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

# --- Fog control ---
@export var fog_root_path: NodePath = NodePath("../WorldEnvironment")

# --- Cellar roles ---
@export var leader_speed_multiplier: float = 0.35  # leader moves slower
@export var follower_height: float = 2.2           # follower hovers above leader
@export var follower_forward_offset: float = 0.25  # tiny offset so they don't clip
@export var server_follow_update_hz: float = 20.0  # how often server pushes follower position

# Teleport lift (keeps you from clipping into blocks)
@export var spawn_y_lift: float = 3.5

# ============================================================
# NEW: TOP/BOTTOM PLAYER RULES
# - "Top" = follower (hovering)   | "Bottom" = leader (ground)
# ============================================================
@export var top_auto_give_flashlight: bool = true
@export var top_flashlight_item_key: NodePath = NodePath("flashlight") # ItemManager item_key meta value
@export var bottom_speed_multiplier: float = 1.15                      # leader a little faster

# Top body invis + no collision
@export var top_make_body_invisible: bool = true
@export var top_disable_collision: bool = true
@export var top_body_mesh_path: NodePath = NodePath("")        # optional override; if empty we auto-find MeshInstance3D children
@export var top_collision_shape_path: NodePath = NodePath("Collider")  # your player uses $Collider

# Top view lock relative to bottom view (yaw clamp)
@export var top_lock_view_to_bottom: bool = true
@export var top_yaw_limit_deg: float = 20.0

var _cellar_instance: Node3D = null

# role state
var _cellar_active: bool = false
var _leader_peer_id: int = -1
var _follower_peer_ids: Array[int] = []

var _follow_accum: float = 0.0

# Fog backups
var _fog_env_original: Environment = null
var _fog_env_disabled: Environment = null

func _ready() -> void:
	set_process(false)
	set_physics_process(true)

func request_enter_cellar(from_player: Node = null) -> void:
	# SOLO: do it locally
	if not multiplayer.has_multiplayer_peer():
		_ensure_cellar_spawned()
		_local_disable_fog()
		_local_teleport_all_players_to_cellar()
		_local_apply_roles_solo()
		return

	# MULTI: server decides and tells everyone
	if multiplayer.is_server():
		_ensure_cellar_spawned()
		_server_begin_cellar(from_player)
	else:
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
	_leader_peer_id = _pick_leader_peer_id(from_player)
	_follower_peer_ids = _pick_followers(_leader_peer_id)

	_cellar_active = true

	# Tell everyone: spawn cellar (if needed), disable fog, teleport and set roles
	rpc(
		"_rpc_enter_cellar_all",
		_leader_peer_id,
		leader_speed_multiplier,
		follower_height,
		follower_forward_offset,
		bottom_speed_multiplier,
		top_auto_give_flashlight,
		top_flashlight_item_key,
		top_make_body_invisible,
		top_disable_collision,
		top_body_mesh_path,
		top_collision_shape_path,
		top_lock_view_to_bottom,
		top_yaw_limit_deg
	)

@rpc("any_peer", "call_local", "reliable")
func _rpc_enter_cellar_all(
	leader_peer_id: int,
	leader_mult: float,
	hover_h: float,
	fwd_off: float,
	leader_speed_boost: float,
	do_top_flashlight: bool,
	flashlight_key: NodePath,
	do_top_invis: bool,
	do_top_no_coll: bool,
	mesh_path: NodePath,
	coll_path: NodePath,
	do_view_lock: bool,
	yaw_limit_deg: float
) -> void:
	_ensure_cellar_spawned()
	_local_disable_fog()
	_local_teleport_all_players_to_cellar()

	# Configure local players on THIS peer
	var local_players: Array[Node] = get_tree().get_nodes_in_group("player")
	for p in local_players:
		var player := p as Node3D
		if player == null:
			continue

		var pid: int = int(player.get_multiplayer_authority())
		var is_leader: bool = (pid == leader_peer_id)
		var is_top: bool = (not is_leader) # follower = top

		# 1) Apply cellar role (speed + follower/leader flag)
		if player.has_method("server_set_cellar_role"):
			var mult := leader_mult
			if is_leader:
				# make bottom a bit faster: multiply AFTER leader slow
				mult = leader_mult * leader_speed_boost
			player.rpc_id(pid, "server_set_cellar_role", is_leader, mult, hover_h, fwd_off, leader_peer_id)

		# 2) Force-pose lock followers immediately (server keeps updating)
		if is_top and player.has_method("server_set_forced_pose"):
			player.rpc_id(pid, "server_set_forced_pose", true, player.global_position)

		# 3) Give top player a flashlight automatically (owner-only)
		if is_top and do_top_flashlight and player.has_method("request_pickup_rpc"):
			player.rpc_id(pid, "request_pickup_rpc", flashlight_key)

		# 4) Make top body invisible + disable collision (owner-only)
		if is_top and (do_top_invis or do_top_no_coll):
			player.rpc_id(
				pid,
				"_cellar_apply_top_avatar_rules",
				do_top_invis,
				do_top_no_coll,
				mesh_path,
				coll_path
			)

		# 5) Lock top view relative to bottom view (owner-only)
		if is_top and do_view_lock and player.has_method("server_set_view_lock_to_leader"):
			player.rpc_id(pid, "server_set_view_lock_to_leader", true, leader_peer_id, yaw_limit_deg)
		elif is_top and do_view_lock and player.has_method("_cellar_set_view_lock_to_leader_fallback"):
			# if you implement a different name in Player, this gives you a safe fallback hook
			player.rpc_id(pid, "_cellar_set_view_lock_to_leader_fallback", true, leader_peer_id, yaw_limit_deg)

func _physics_process(delta: float) -> void:
	# Server keeps followers glued above leader
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if not _cellar_active:
		return

	_follow_accum += delta
	var step: float = 1.0 / maxf(server_follow_update_hz, 1.0)
	if _follow_accum < step:
		return
	_follow_accum = 0.0

	var leader := _find_player_by_peer(_leader_peer_id)
	if leader == null:
		return

	var leader_pos: Vector3 = leader.global_position
	var leader_basis: Basis = leader.global_transform.basis

	# forward offset (Godot forward is -Z)
	var forward: Vector3 = -leader_basis.z.normalized()
	var target_pos: Vector3 = leader_pos + Vector3(0, follower_height, 0) + forward * follower_forward_offset

	# Push forced position to each follower's owning client
	for fid: int in _follower_peer_ids:
		var fnode := _find_player_by_peer(fid)
		if fnode == null:
			continue
		if fnode.has_method("server_set_forced_pose"):
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

# ============================================================
# FOG DISABLE (WorldEnvironment-safe)
# ============================================================
func _local_disable_fog() -> void:
	var n := get_node_or_null(fog_root_path)
	if n == null:
		push_warning("[TeleportManager] fog_root_path not found. Set it to your WorldEnvironment node.")
		return

	var we := n as WorldEnvironment
	if we != null:
		if we.environment == null:
			return

		if _fog_env_original == null:
			_fog_env_original = we.environment

		if _fog_env_disabled == null:
			_fog_env_disabled = _fog_env_original.duplicate(true) as Environment
			if _fog_env_disabled == null:
				push_warning("[TeleportManager] Could not duplicate Environment.")
				return

			_env_set_if_has(_fog_env_disabled, "fog_enabled", false)
			_env_set_if_has(_fog_env_disabled, "volumetric_fog_enabled", false)

		we.environment = _fog_env_disabled
		return

	var n3 := n as Node3D
	if n3 != null:
		n3.visible = false

func _env_set_if_has(env: Environment, prop: String, value: Variant) -> void:
	if env == null:
		return
	for d: Dictionary in env.get_property_list():
		var name: String = String(d.get("name", ""))
		if name == prop:
			env.set(prop, value)
			return

func _local_teleport_all_players_to_cellar() -> void:
	if _cellar_instance == null or not is_instance_valid(_cellar_instance):
		return

	var spawn := _cellar_instance.get_node_or_null(cellar_spawn_marker_path) as Node3D
	if spawn == null:
		push_error("[TeleportManager] Spawn marker not found in cellar. Expected SpawnPoints/Spawn.")
		return

	var spawn_pos: Vector3 = spawn.global_position

	for p in get_tree().get_nodes_in_group("player"):
		var player := p as Node3D
		if player == null:
			continue
		player.global_position = spawn_pos + Vector3(0.0, spawn_y_lift, 0.0)

func _pick_leader_peer_id(from_player: Node) -> int:
	var fp := from_player as Node
	if fp != null:
		var a: int = int(fp.get_multiplayer_authority())
		if a > 0:
			return a

	var best: float = INF
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node
		if n == null:
			continue
		var id: int = int(n.get_multiplayer_authority())
		if id > 0 and float(id) < best:
			best = float(id)

	return -1 if best == INF else int(best)

func _pick_followers(leader_id: int) -> Array[int]:
	var out: Array[int] = []
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node
		if n == null:
			continue
		var id: int = int(n.get_multiplayer_authority())
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
	_cellar_active = false
