extends NPCState
class_name PatrolState

@export var arrive_dist: float = 0.6
@export var wait_at_waypoint: float = 0.0

@export var retry_autofind: bool = true
@export var retry_interval: float = 0.5
@export var retry_max_seconds: float = 6.0

@export var talk_range: Area3D

var _wps: Array[Node3D] = []
var _idx: int = 0
var _wait_t: float = 0.0
var _loop: bool = true

var _retry_t: float = 0.0
var _retry_left: float = 0.0


func enter(msg := {}) -> void:
	_wps.clear()
	_idx = 0
	_wait_t = 0.0
	_loop = true

	_retry_t = 0.0
	_retry_left = retry_max_seconds

	if npc == null:
		return

	_try_build_path()


func physics_update(delta: float) -> void:
	var npc3d := npc as NPC
	if npc3d == null:
		return

	# talk interrupt (optional)
	if _is_player_in_talk_range():
		npc3d.save_patrol_resume(_idx, _wait_t)
		npc3d.velocity.x = 0.0
		npc3d.velocity.z = 0.0
		change_state.emit(&"TalkState", {})
		return

	# If no waypoints, retry (PCG timing)
	if _wps.size() == 0:
		if retry_autofind and _retry_left > 0.0:
			_retry_left -= delta
			_retry_t -= delta
			if _retry_t <= 0.0:
				_retry_t = retry_interval
				_try_build_path()
		return

	# wait at waypoint
	if _wait_t > 0.0:
		_wait_t -= delta
		return

	_idx = clampi(_idx, 0, _wps.size() - 1)

	#  read current waypoint global position each frame
	var wp := _wps[_idx]
	if wp == null or not is_instance_valid(wp):
		_wps.clear()
		return

	var target := wp.global_position
	var look_target := target
	look_target.y -= 0.55
	npc3d.move_toward_world(target, delta)
	npc3d.look_at(look_target)

	var flat_dist := Vector3(npc3d.global_position.x, 0.0, npc3d.global_position.z) \
		.distance_to(Vector3(target.x, 0.0, target.z))

	if flat_dist <= arrive_dist:
		if wait_at_waypoint > 0.0:
			_wait_t = wait_at_waypoint
		_advance()
		return


func _try_build_path() -> void:
	var npc3d := npc as NPC
	if npc3d == null:
		return

	# LOCAL ONLY: NPC already bound to its own PatrolPath via patrol_path_node
	var path := npc3d.patrol_path
	if path == null or not is_instance_valid(path):
		return

	_wps = path.get_waypoint_nodes_sorted()
	_loop = path.loop

	if _wps.size() == 0:
		return

	# resume (optional)
	var resume := npc3d.consume_patrol_resume()
	if bool(resume.get("has_data", false)):
		_idx = clampi(int(resume.get("idx", 0)), 0, _wps.size() - 1)
		_wait_t = float(resume.get("wait_t", 0.0))
	else:
		_idx = _closest_index(npc3d.global_position, _wps)


func _advance() -> void:
	_idx += 1
	if _idx >= _wps.size():
		_idx = 0 if _loop else (_wps.size() - 1)


func _closest_index(pos: Vector3, wps: Array[Node3D]) -> int:
	var best_i := 0
	var best_d := INF
	for i in range(wps.size()):
		var w := wps[i]
		if w == null or not is_instance_valid(w):
			continue
		var d := pos.distance_to(w.global_position)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _is_player_in_talk_range() -> bool:
	if talk_range == null or not is_instance_valid(talk_range):
		return false
	for b in talk_range.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			return true
	return false
