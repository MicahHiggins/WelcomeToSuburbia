extends Node3D
class_name PatrolPath

@export var loop: bool = true

# Accept waypoints that are:
# - Marker3D
# - OR Node3D named like "WP_1", "WP_2", etc
# - OR Node3D with meta "wp_index"
@export var waypoint_name_prefix: String = "WP_"
@export var search_recursively: bool = true

func _ready() -> void:
	add_to_group("patrol_path")

func get_points_world() -> Array[Vector3]:
	var waypoints: Array[Node3D] = []

	if search_recursively:
		_collect_waypoints_recursive(self, waypoints)
	else:
		for c in get_children():
			var n := c as Node3D
			if n != null and _is_waypoint(n):
				waypoints.append(n)

	# Sort by wp_index meta OR by the number in the name suffix (WP_2, WP_10, etc)
	waypoints.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _wp_index(a) < _wp_index(b)
	)

	var pts: Array[Vector3] = []
	for w in waypoints:
		pts.append(w.global_position)

	# Debug (optional)
	# print("[PatrolPath] found waypoints:", waypoints.size(), " pts:", pts.size())

	return pts

func _collect_waypoints_recursive(root: Node, out: Array[Node3D]) -> void:
	for c in root.get_children():
		var n := c as Node3D
		if n != null and _is_waypoint(n):
			out.append(n)

		_collect_waypoints_recursive(c, out)

func _is_waypoint(n: Node3D) -> bool:
	if n is Marker3D:
		return true
	if n.has_meta("wp_index"):
		return true
	# Name-based 
	return String(n.name).begins_with(waypoint_name_prefix)

func _wp_index(n: Node3D) -> int:
	if n.has_meta("wp_index"):
		return int(n.get_meta("wp_index"))

	var s := String(n.name)
	var parts := s.split("_")
	if parts.size() >= 2 and parts[parts.size() - 1].is_valid_int():
		return int(parts[parts.size() - 1])

	return 999999
