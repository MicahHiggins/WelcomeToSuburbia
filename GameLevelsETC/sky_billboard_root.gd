extends Node3D

@export var players_group := "player"

@export var min_distance := 55.0
@export var teleport_distance := 120.0
@export var check_interval := 0.35

@export var raycast_up := 200.0
@export var raycast_down := 3000.0
@export var side_offset := 12.0

# peer_id -> is_looking (reported by each client)
var looking_by_peer: Dictionary = {}
var _t := 0.0


func _ready():
	_reposition()


func _physics_process(dt):
	# Server decides when to teleport
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	_t += dt
	if _t < check_interval:
		return
	_t = 0.0

	var ps := _get_players()
	if ps.is_empty():
		return

	var center := _players_center(ps)

	# Only teleport if too close AND nobody is looking (per client reports)
	if global_position.distance_to(center) < min_distance and _nobody_is_looking(ps):
		_reposition()


# Called by clients
@rpc("any_peer", "unreliable")
func report_looking(is_looking: bool):
	var peer_id := multiplayer.get_remote_sender_id()
	looking_by_peer[peer_id] = is_looking


func _nobody_is_looking(ps: Array) -> bool:
	# If any player peer says they're looking -> do NOT teleport
	for p in ps:
		var pl := p as Node
		# Convention: player node name is the peer id string (common in multiplayer setups)
		var pid := int(pl.name) if pl.name.is_valid_int() else null
		if pid != null and looking_by_peer.get(pid, false) == true:
			return false
	return true


func _reposition():
	var ps := _get_players()
	if ps.is_empty():
		return

	var center := _players_center(ps)
	var dir := _average_forward_xz(ps)
	var right := dir.cross(Vector3.UP).normalized()

	var target_pos := center + dir * teleport_distance + right * side_offset
	target_pos = _snap_to_ground(target_pos)

	global_position = target_pos
	_face_center_yaw_only(center)


func _get_players() -> Array:
	return get_tree().get_nodes_in_group(players_group)


func _players_center(ps: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ps:
		c += (p as Node3D).global_position
	return c / float(ps.size())


func _average_forward_xz(ps: Array) -> Vector3:
	var dir := Vector3.ZERO
	for p in ps:
		var f := -(p as Node3D).global_transform.basis.z
		f.y = 0.0
		dir += f
	dir.y = 0.0
	if dir.length() < 0.001:
		return Vector3.FORWARD
	return dir.normalized()


func _snap_to_ground(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := pos + Vector3.UP * raycast_up
	var to := pos + Vector3.DOWN * raycast_down
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit:
		pos.y = hit.position.y
	return pos


func _face_center_yaw_only(center: Vector3):
	var flat_target := Vector3(center.x, global_position.y, center.z)
	var to := flat_target - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	rotation.x = 0.0
	rotation.z = 0.0
	rotation.y = atan2(to.x, to.z)
