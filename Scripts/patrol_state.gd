extends NPCState
class_name PatrolState

@export var arrive_dist: float = 0.6
@export var wait_at_waypoint: float = 0.0

# Keep trying to auto-find a path after spawn (useful for PCG timing)
@export var retry_autofind: bool = true
@export var retry_interval: float = 0.5
@export var retry_max_seconds: float = 6.0


@export var talk_range: Area3D

var _points: Array[Vector3] = []
var _idx: int = 0
var _wait_t: float = 0.0
var _loop: bool = true

var _retry_t: float = 0.0
var _retry_left: float = 0.0


func enter(_msg := {}) -> void:
	_points = []
	_wait_t = 0.0

	_retry_t = 0.0
	_retry_left = retry_max_seconds

	if npc == null:
		push_warning("[PatrolState] npc is null")
		return

	_try_build_path()


func physics_update(delta: float) -> void:
	var npc3d := npc as NPC
	if npc3d == null:
		return

	# 1) TALK CHECK FIRST (POLLING, NO SIGNALS)
	# If player is in range, switch to TalkState and remember our current waypoint index.
	if _is_player_in_talk_range():
		npc3d.set_meta("patrol_resume_idx", _idx)

		# Stop immediately this frame
		npc3d.velocity.x = 0.0
		npc3d.velocity.z = 0.0

		change_state.emit(&"TalkState")
		return

	# 2) If have no points yet, keep retrying (PCG spawn timing)
	if _points.size() == 0:
		if retry_autofind and _retry_left > 0.0:
			_retry_left -= delta
			_retry_t -= delta
			if _retry_t <= 0.0:
				_retry_t = retry_interval
				_try_build_path()
		return

	# 3) Optional wait at waypoint
	if _wait_t > 0.0:
		_wait_t -= delta
		return

	# 4) Move toward current waypoint
	var target: Vector3 = _points[_idx]
	npc3d.move_toward_world(target, delta)

	# 5) Arrive?
	var flat_dist := Vector3(npc3d.global_position.x, 0.0, npc3d.global_position.z) \
		.distance_to(Vector3(target.x, 0.0, target.z))

	if flat_dist <= arrive_dist:
		if wait_at_waypoint > 0.0:
			_wait_t = wait_at_waypoint
		_advance()


# -------------------------
# Player-in-range check (robust, no signals)
# -------------------------
func _is_player_in_talk_range() -> bool:
	if talk_range == null or not is_instance_valid(talk_range):
		return false

	var bodies := talk_range.get_overlapping_bodies()
	for b in bodies:
		if b != null and b.is_in_group("player"):
			return true

	return false


# -------------------------
# Path building + resume
# -------------------------
func _try_build_path() -> void:
	var npc3d := npc as NPC
	if npc3d == null:
		push_warning("[PatrolState] npc is not NPC class (script mismatch?)")
		return

	# If missing, try auto-find again (spawn timing / PCG timing fix)
	if npc3d.patrol_path == null and npc3d.auto_find_patrol_path:
		npc3d.patrol_path = npc3d.find_nearest_patrol_path(npc3d.auto_find_max_dist)

	var path: PatrolPath = npc3d.patrol_path
	if path == null:
		push_warning("[PatrolState] patrol_path is NULL (auto-find failed?)")
		return

	_points = path.get_points_world()
	_loop = path.loop

	if _points.size() == 0:
		return

	# Resume from saved idx if we have it (so we don't restart at WP_1)
	if npc3d.has_meta("patrol_resume_idx"):
		_idx = clampi(int(npc3d.get_meta("patrol_resume_idx")), 0, _points.size() - 1)
	else:
		_idx = _closest_index(npc3d.global_position, _points)


func _advance() -> void:
	_idx += 1
	if _idx >= _points.size():
		_idx = 0 if _loop else (_points.size() - 1)


func _closest_index(pos: Vector3, pts: Array[Vector3]) -> int:
	var best_i := 0
	var best_d := INF
	for i in range(pts.size()):
		var d := pos.distance_to(pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i
