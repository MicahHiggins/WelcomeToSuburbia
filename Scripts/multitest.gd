extends Node3D

@export var target_distance := 60.0
@export var smooth := 10.0
@export var raycast_up := 200.0
@export var raycast_down := 3000.0
@export var players_group := "player"

func _physics_process(dt):
	# Server-only movement so all clients match
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	var ps := get_tree().get_nodes_in_group(players_group)
	if ps.is_empty():
		return

	# Midpoint of all players
	var center := Vector3.ZERO
	for p in ps:
		center += (p as Node3D).global_position
	center /= float(ps.size())

	# Stable "forward" direction: average player forward on XZ
	var dir := Vector3.ZERO
	for p in ps:
		var pl := p as Node3D
		var f := -pl.global_transform.basis.z
		f.y = 0.0
		dir += f

	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()

	# Position at fixed distance
	var target_pos := center + dir * target_distance

	# Snap to ground
	var space := get_world_3d().direct_space_state
	var from := target_pos + Vector3.UP * raycast_up
	var to := target_pos + Vector3.DOWN * raycast_down
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := space.intersect_ray(query)
	if hit:
		target_pos.y = hit.position.y
	else:
		target_pos.y = global_position.y

	# Smooth move
	global_position = global_position.lerp(target_pos, 1.0 - exp(-smooth * dt))

	# Face back toward the players (optional)
	var look_point := Vector3(center.x, global_position.y, center.z)
	look_at(look_point, Vector3.UP)
