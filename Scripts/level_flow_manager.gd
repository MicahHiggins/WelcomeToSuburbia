# res://LevelFlowManager.gd
extends Node
class_name LevelFlowManager

const SERVER_ID: int = 1

@export var level_container_path: NodePath = NodePath("../LevelContainer")
@export var players_root_path: NodePath = NodePath("../PlayersRoot")

@export var default_level: PackedScene
@export var lobby_level_scene: PackedScene = preload("res://GameLevelsETC/lobby.tscn")
@export var spawn_marker_path_in_level: NodePath = NodePath("Spawn")
@export var spawn_y_lift: float = 1.5
@export var snap_late_joiners_to_spawn: bool = true

@export var level_1_scene: PackedScene = preload("res://Assets/RandomObjects/symbol/SymbolPuzzle.tscn")
@export var level_2_scene: PackedScene = preload("res://GameLevelsETC/kidnap.tscn")
@export var level_3_scene: PackedScene = preload("res://GameLevelsETC/CellarLevel.tscn")

# ----------------------------
# Cellar/role application hooks
# ----------------------------
@export var apply_cellar_roles_only_on_level_3: bool = true
@export var cellar_level_scene_path_hint: String = "CellarLevel" # substring match

@export var cellar_follow_speed: float = 1.0
@export var cellar_follow_dist: float = 2.2
@export var cellar_follow_lerp: float = 0.25

# ----------------------------
# Flashlight: give to joiner/top player
# ----------------------------
@export var give_flashlight_to_joining_player: bool = true
@export var flashlight_group_name: String = "pickup"
@export var flashlight_name_contains: String = "flashlight"

# Delay so flashlight + ItemManager have registered scene pickups before we auto-pickup
@export var flashlight_pickup_delay_sec: float = 0.25

# Optional: call this group after level load & spawn
@export var post_level_ready_group: String = "level_post_ready"

# ----------------------------
# PATCH: make LevelFlowManager easy to find
# - LobbyReady was likely failing to find it due to hardcoded /root/Main path or node name mismatch
# - This guarantees:
#   * Node name is "LevelFlowManager"
#   * It’s in a predictable group: "level_flow_manager"
#   * You can find it via get_tree().get_first_node_in_group("level_flow_manager")
# ----------------------------
@export var force_node_name_level_flow_manager: bool = true
@export var register_in_group: bool = true
const LEVEL_FLOW_GROUP: StringName = &"level_flow_manager"

# Cached nodes
var _level_container: Node = null
var _players_root: Node3D = null

var _current_level: Node = null
var _current_level_scene_path: String = ""

var _has_spawn_xform: bool = false
var _cached_spawn_xform: Transform3D = Transform3D.IDENTITY

var _has_split_spawns: bool = false
var _spawn_host_xform: Transform3D = Transform3D.IDENTITY
var _spawn_join_xform: Transform3D = Transform3D.IDENTITY

# Level-load readiness handshake (server)
var _ready_peers: Dictionary = {} # int(peer_id) -> bool
var _waiting_for_ready: bool = false

# witness tracking
var _peer_look_target: Dictionary = {} # int(peer_id) -> String

# camera look sync
var _peer_cam_xforms: Dictionary = {}  # int(peer_id) -> Transform3D


func _enter_tree() -> void:
	# PATCH: guarantee a stable name so find_child("LevelFlowManager") works
	if force_node_name_level_flow_manager and name != "LevelFlowManager":
		name = "LevelFlowManager"

	if register_in_group and not is_in_group(String(LEVEL_FLOW_GROUP)):
		add_to_group(String(LEVEL_FLOW_GROUP))


func _ready() -> void:
	_level_container = get_node_or_null(level_container_path)
	if _level_container == null:
		push_error("[LevelFlowManager] LevelContainer not found. Fix level_container_path.")
		return

	_players_root = get_node_or_null(players_root_path) as Node3D
	if _players_root == null:
		push_error("[LevelFlowManager] PlayersRoot not found. Fix players_root_path.")
		return

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# NOTE: default_level load only happens on server when multiplayer is active
	if default_level != null:
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				load_level_server(default_level)
		else:
			_load_level_local(default_level)

# ----------------------------
# basic helpers
# ----------------------------
func _scene_root() -> Node:
	return get_tree().current_scene

func _resolve_scene_path(path: NodePath) -> Node:
	var scene: Node = _scene_root()
	if scene != null:
		var n: Node = scene.get_node_or_null(path)
		if n != null:
			return n
	return get_tree().root.get_node_or_null(path)

func _to_scene_path(n: Node) -> NodePath:
	var scene: Node = _scene_root()
	if scene == null or n == null:
		return NodePath("")
	return scene.get_path_to(n)

func _find_item_manager() -> Node:
	var scene: Node = _scene_root()
	if scene == null:
		return null

	var direct: Node = scene.get_node_or_null("ItemManager")
	if direct != null:
		return direct

	return scene.find_child("ItemManager", true, false)

# ----------------------------
# multiplayer events
# ----------------------------
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _current_level_scene_path == "":
		return

	_peer_look_target[peer_id] = ""
	_peer_cam_xforms[peer_id] = Transform3D.IDENTITY

	# send current level to late joiner
	rpc_id(peer_id, "_rpc_load_level_all", _current_level_scene_path)

func _on_peer_disconnected(peer_id: int) -> void:
	_peer_look_target.erase(peer_id)
	_peer_cam_xforms.erase(peer_id)

# ----------------------------
# level change entrypoint
# ----------------------------
func request_level_change(level_index: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		var ps_local: PackedScene = _scene_for_index(level_index)
		if ps_local == null:
			push_warning("[LevelFlowManager] invalid level index: %d" % level_index)
			return
		_load_level_local(ps_local)
		_place_all_players_local_to_spawn()
		_apply_post_spawn_rules_local()
		return

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
		push_warning("[LevelFlowManager] invalid level index: %d" % level_index)
		return
	load_level_server(ps)

func _scene_for_index(level_index: int) -> PackedScene:
	match level_index:
		1: return level_1_scene
		2: return level_2_scene
		3: return level_3_scene
		_: return null

# ----------------------------
# server load -> broadcast
# ----------------------------
func load_level_server(scene: PackedScene) -> void:
	if scene == null:
		push_error("[LevelFlowManager] load_level_server got null scene.")
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		push_warning("[LevelFlowManager] load_level_server called on a client. Ignoring.")
		return

	var p: String = scene.resource_path
	if p == "":
		push_error("[LevelFlowManager] Level scene has no resource_path (must be saved .tscn).")
		return

	_current_level_scene_path = p

	_ready_peers.clear()
	_waiting_for_ready = true
	_ready_peers[multiplayer.get_unique_id()] = false

	rpc("_rpc_load_level_all", _current_level_scene_path)

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

	for pid_any in multiplayer.get_peers():
		var pid: int = int(pid_any)
		if not _ready_peers.has(pid) or _ready_peers[pid] != true:
			return

	_waiting_for_ready = false
	call_deferred("_deferred_server_place_all")

# ----------------------------
# local instantiate
# ----------------------------
func _clear_level_container_safely() -> void:
	if _level_container == null:
		return
	var kids: Array = _level_container.get_children()
	for c_any in kids:
		var c: Node = c_any as Node
		if c == null or not is_instance_valid(c):
			continue
		_level_container.remove_child(c)
		c.queue_free()

func _load_level_local(scene: PackedScene) -> void:
	_clear_level_container_safely()
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
	_cache_split_spawns()

	print("[LevelFlowManager] Loaded level:", scene.resource_path)

# ----------------------------
# server place players
# ----------------------------
func _deferred_server_place_all() -> void:
	teleport_all_players_to_current_spawn_server()
	call_deferred("_deferred_server_post_spawn_apply")

func _deferred_server_post_spawn_apply() -> void:
	_server_apply_post_spawn_rules()

	if post_level_ready_group != "":
		rpc("_rpc_call_group_post_ready", post_level_ready_group)

@rpc("any_peer", "call_local", "reliable")
func _rpc_call_group_post_ready(group_name: String) -> void:
	if group_name == "":
		return
	get_tree().call_group(group_name, "on_level_post_ready")

func teleport_all_players_to_current_spawn_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_cache_spawn_transform()
	_cache_split_spawns()

	var kids: Array = _players_root.get_children()
	for child_any in kids:
		var p: Node3D = child_any as Node3D
		if p == null:
			continue

		var owner_id: int = int(p.get_multiplayer_authority())
		if owner_id <= 0:
			continue

		var target_xf: Transform3D = _cached_spawn_xform
		if _has_split_spawns:
			target_xf = _spawn_host_xform if owner_id == SERVER_ID else _spawn_join_xform

		if p.has_method("server_teleport_to"):
			p.rpc_id(owner_id, "server_teleport_to", target_xf)
		else:
			p.global_transform = target_xf

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

	call_deferred("_deferred_server_post_spawn_apply")

# ----------------------------
# spawn cache
# ----------------------------
func _cache_spawn_transform() -> void:
	_has_spawn_xform = false
	_cached_spawn_xform = Transform3D.IDENTITY

	if _current_level == null:
		return

	var spawn: Node3D = _current_level.get_node_or_null(spawn_marker_path_in_level) as Node3D
	if spawn == null:
		push_error("[LevelFlowManager] Spawn marker not found at: " + String(spawn_marker_path_in_level))
		return

	var xform: Transform3D = spawn.global_transform
	xform.origin.y += spawn_y_lift

	_cached_spawn_xform = xform
	_has_spawn_xform = true

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

# ------------------------------------------------------------
# Post-spawn rules: cellar roles + flashlight auto-pickup (SERVER FORCE)
# ------------------------------------------------------------
func _is_cellar_level() -> bool:
	if _current_level_scene_path == "":
		return false
	if apply_cellar_roles_only_on_level_3:
		return _current_level_scene_path.findn(cellar_level_scene_path_hint) != -1
	return true

func _server_apply_post_spawn_rules() -> void:
	if not multiplayer.is_server():
		return
	if _current_level == null:
		return
	if not _is_cellar_level():
		return

	_apply_cellar_roles_server()

	if give_flashlight_to_joining_player:
		var joiner_id: int = _pick_joiner_peer_id_server()
		call_deferred("_deferred_server_force_pickup_flashlight", joiner_id)

func _apply_post_spawn_rules_local() -> void:
	if _is_cellar_level():
		_apply_cellar_roles_local()

func _deferred_server_force_pickup_flashlight(joiner_id: int) -> void:
	if not multiplayer.is_server():
		return

	var timer: SceneTreeTimer = get_tree().create_timer(maxf(0.0, flashlight_pickup_delay_sec))
	await timer.timeout

	var im: Node = _find_item_manager()
	if im == null:
		push_error("[LevelFlowManager] ItemManager not found on server for auto-pickup.")
		return
	if not im.has_method("server_force_pickup_for_peer"):
		push_error("[LevelFlowManager] ItemManager missing server_force_pickup_for_peer.")
		return

	var flashlight: Node3D = _find_flashlight_in_world()
	if flashlight == null:
		push_warning("[LevelFlowManager] Could not find flashlight to auto-pickup.")
		return

	var item_path: NodePath = _to_scene_path(flashlight)
	if String(item_path) == "":
		push_warning("[LevelFlowManager] Flashlight had no valid scene path to auto-pickup.")
		return

	im.call("server_force_pickup_for_peer", item_path, joiner_id)

# ----------------------------
# cellar roles
# ----------------------------
func _apply_cellar_roles_server() -> void:
	if not multiplayer.is_server():
		return

	var players: Array = get_tree().get_nodes_in_group("player")
	var leader_id: int = 999999

	for p_any in players:
		var p3: Node3D = p_any as Node3D
		if p3 == null:
			continue
		var pid: int = int(p3.get_multiplayer_authority())
		if pid > 0 and pid < leader_id:
			leader_id = pid

	if leader_id == 999999:
		return

	for p_any in players:
		var p3: Node3D = p_any as Node3D
		if p3 == null:
			continue
		var pid: int = int(p3.get_multiplayer_authority())
		if pid <= 0:
			continue

		var is_leader: bool = (pid == leader_id)
		if p3.has_method("server_set_cellar_role"):
			p3.rpc_id(pid, "server_set_cellar_role", is_leader, cellar_follow_speed, cellar_follow_dist, cellar_follow_lerp, leader_id)

func _apply_cellar_roles_local() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	var leader_id: int = 999999

	for p_any in players:
		var p3: Node3D = p_any as Node3D
		if p3 == null:
			continue
		var pid: int = int(p3.get_multiplayer_authority())
		if pid > 0 and pid < leader_id:
			leader_id = pid

	if leader_id == 999999:
		return

	for p_any in players:
		var p3: Node3D = p_any as Node3D
		if p3 == null:
			continue
		var pid: int = int(p3.get_multiplayer_authority())
		if pid <= 0:
			continue
		var is_leader: bool = (pid == leader_id)
		if p3.has_method("server_set_cellar_role"):
			p3.call("server_set_cellar_role", is_leader, cellar_follow_speed, cellar_follow_dist, cellar_follow_lerp, leader_id)

func _pick_joiner_peer_id_server() -> int:
	var joiner_id: int = SERVER_ID
	for pid_any in multiplayer.get_peers():
		var pid: int = int(pid_any)
		if pid != SERVER_ID and (joiner_id == SERVER_ID or pid < joiner_id):
			joiner_id = pid
	return joiner_id

func _find_flashlight_in_world() -> Node3D:
	if flashlight_group_name != "":
		var nodes: Array = get_tree().get_nodes_in_group(flashlight_group_name)
		for n_any in nodes:
			var n: Node3D = n_any as Node3D
			if n == null:
				continue
			if flashlight_name_contains == "" or String(n.name).to_lower().find(flashlight_name_contains.to_lower()) != -1:
				return n

	if _current_level != null:
		var stack: Array[Node] = [_current_level]
		while not stack.is_empty():
			var cur: Node = stack.pop_back() as Node
			if cur == null:
				continue
			for ch_any in cur.get_children():
				var ch: Node = ch_any as Node
				if ch == null:
					continue
				stack.append(ch)

				var c3: Node3D = ch as Node3D
				if c3 == null:
					continue
				if flashlight_name_contains != "" and String(c3.name).to_lower().find(flashlight_name_contains.to_lower()) != -1:
					return c3

	return null

# ------------------------------------------------------------
# witness API
# ------------------------------------------------------------
@rpc("any_peer", "unreliable")
func _rpc_witness_set_look_target(target_path) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if typeof(target_path) != TYPE_STRING:
		return
	_peer_look_target[sender] = String(target_path)

func witness_get_lookers_count(target_path: String) -> int:
	if not multiplayer.is_server():
		return 0
	var count: int = 0
	for pid_any in _peer_look_target.keys():
		var pid: int = int(pid_any)
		if String(_peer_look_target[pid]) == target_path:
			count += 1
	return count

# ------------------------------------------------------------
# camera look sync API
# ------------------------------------------------------------
@rpc("any_peer", "call_local", "unreliable")
func _rpc_broadcast_peer_camera(peer_id: int, cam_xform: Transform3D) -> void:
	_peer_cam_xforms[peer_id] = cam_xform

func _server_set_peer_camera(peer_id: int, cam_xform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	_peer_cam_xforms[peer_id] = cam_xform
	rpc("_rpc_broadcast_peer_camera", peer_id, cam_xform)

@rpc("any_peer", "unreliable")
func _rpc_update_peer_camera(cam_xform: Transform3D) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return

	_peer_cam_xforms[sender] = cam_xform
	rpc("_rpc_broadcast_peer_camera", sender, cam_xform)

func get_peer_camera_xform(peer_id: int) -> Transform3D:
	if _peer_cam_xforms.has(peer_id):
		return _peer_cam_xforms[peer_id] as Transform3D
	return Transform3D.IDENTITY

func get_all_peer_camera_xforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for pid_any in _peer_cam_xforms.keys():
		var pid: int = int(pid_any)
		out.append(_peer_cam_xforms[pid] as Transform3D)
	return out
