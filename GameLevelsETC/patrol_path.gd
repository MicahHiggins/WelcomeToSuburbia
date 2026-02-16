extends Node3D
class_name PatrolPath

@export var loop: bool = true
@export var waypoint_name_prefix: String = "WP_"
@export var search_recursively: bool = true

func get_waypoint_nodes_sorted() -> Array[Node3D]:
	var waypoints: Array[Node3D] = []

	if search_recursively:
		_collect_waypoints_recursive(self, waypoints)
	else:
		for c in get_children():
			var n := c as Node3D
			if n != null and _is_waypoint(n):
				waypoints.append(n)

	waypoints.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _wp_index(a) < _wp_index(b)
	)

	return waypoints


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
	return String(n.name).begins_with(waypoint_name_prefix)


func _wp_index(n: Node3D) -> int:
	if n.has_meta("wp_index"):
		return int(n.get_meta("wp_index"))

	var s := String(n.name)
	var parts := s.split("_")
	if parts.size() >= 2 and parts[parts.size() - 1].is_valid_int():
		return int(parts[parts.size() - 1])

	return 999999
