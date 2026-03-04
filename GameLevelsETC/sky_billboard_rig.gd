extends Node3D

@export var players_group := "player"

# Readable distance target (keep this close enough to read)
@export var read_distance := 75.0

# If players get within this distance, billboard "escapes"
@export var min_distance := 55.0

# Where it jumps to when escaping (still readable-ish, but unreachable)
@export var escape_distance := 120.0

# Fixed compass direction from the player midpoint (example: NE)
@export var direction := Vector3(1, 0, -1)

# Make it feel stationary (don't update constantly)
@export var update_step := 10.0          # only update after players move this far
@export var check_interval := 0.25       # seconds between checks

# Ground snap ray
@export var raycast_up := 200.0
@export var raycast_down := 3000.0

# Optional: face players but upright (yaw only)
@export var face_players := true

var _last_center := Vector3.INF
var _t := 0.0


func _physics_process(dt):
	# IMPORTANT: server decides position so both clients see the same spot
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	_t += dt
	if _t < check_interval:
		return
	_t = 0.0

	var ps := get_tree().get_nodes_in_group(players_group)
	if ps.is_empty():
		return

	var center := _players_center(ps)

	# Only update in "chunks" so it doesn't look like it follows them
	if _last_center != Vector3.INF and center.distance_to(_last_center) < update_step:
		return
	_last_center = center

	var dir := direction.normalized()

	# If players are getting close, push it farther out (same direction)
	var target_dist := read_distance
	if global_position.distance_to(center) < min_distance:
		target_dist = escape_distance

	var target_pos := center + dir * target_dist
	target_pos = _snap_to_ground(target_pos)

	global_position = target_pos

	if face_players:
		_face_center_yaw_only(center)


func _players_center(ps: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ps:
		c += (p as Node3D).global_position
	return c / float(ps.size())


func _snap_to_ground(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := pos + Vector3.UP * raycast_up
	var to := pos + Vector3.DOWN * raycast_down
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit:
		pos.y = hit.position.y
	return pos


func _face_center_yaw_only(center: Vector3) -> void:
	var flat_target := Vector3(center.x, global_position.y, center.z)
	var to := flat_target - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	rotation.x = 0.0
	rotation.z = 0.0
	rotation.y = atan2(to.x, to.z)
