# res://WatchedCrawler.gd (or WatcherSpider8.gd)
extends CharacterBody3D
class_name WatcherSpider

@export var move_speed: float = 3.5
@export var accel: float = 10.0
@export var stick_force: float = 28.0
@export var align_speed: float = 10.0

@export var step_distance: float = 0.70
@export var step_duration: float = 0.16
@export var step_height: float = 0.20

@export var probe_down_path: NodePath = NodePath("Probes/ProbeDown")
@export var probe_forward_path: NodePath = NodePath("Probes/ProbeForward")
@export var visual_root_path: NodePath = NodePath("VisualRoot")
@export var rays_root_path: NodePath = NodePath("Legs/Rays")
@export var targets_root_path: NodePath = NodePath("Legs/Targets")

# Manual leg ray tuning (THIS is the big fix)
@export var leg_ray_length: float = 3.0
@export var leg_ray_start_offset: float = 0.35
@export var leg_ray_fallback_offset: float = 0.10
@export var leg_ray_collision_mask: int = 0xFFFFFFFF

@export var debug_print: bool = true
@export var debug_interval_sec: float = 0.75

const LEG_NAMES: Array[StringName] = [
	&"L1", &"L2", &"L3",
	&"R1", &"R2", &"R3",
	&"FM", &"BM"
]

const GROUP_A: Array[StringName] = [&"L1", &"R2", &"L3", &"BM"]
const GROUP_B: Array[StringName] = [&"R1", &"L2", &"R3", &"FM"]

var _probe_down: RayCast3D = null
var _probe_forward: RayCast3D = null
var _visual_root: Node3D = null

var _rays: Dictionary = {}     # leg -> RayCast3D (kept for organization/debug)
var _targets: Dictionary = {}  # leg -> Node3D

var _surface_normal: Vector3 = Vector3.UP

var _home_local: Dictionary = {}   # leg -> Vector3
var _foot_pos: Dictionary = {}     # leg -> Vector3
var _stepping: Dictionary = {}     # leg -> bool
var _step_t: Dictionary = {}       # leg -> float
var _step_from: Dictionary = {}    # leg -> Vector3
var _step_to: Dictionary = {}      # leg -> Vector3

# debug per-leg
var _leg_last_hit: Dictionary = {}     # leg -> bool
var _leg_last_hit_p: Dictionary = {}   # leg -> Vector3

var _use_group_a: bool = true
var _dbg_t: float = 0.0

func _ready() -> void:
	_probe_down = get_node_or_null(probe_down_path) as RayCast3D
	_probe_forward = get_node_or_null(probe_forward_path) as RayCast3D
	_visual_root = get_node_or_null(visual_root_path) as Node3D

	var rays_root := get_node_or_null(rays_root_path) as Node
	var targets_root := get_node_or_null(targets_root_path) as Node

	var miss_targets := 0
	var miss_rays := 0

	for ln in LEG_NAMES:
		var ray: RayCast3D = null
		var tgt: Node3D = null

		if rays_root != null:
			ray = rays_root.get_node_or_null("%s_Ray" % String(ln)) as RayCast3D
		if targets_root != null:
			tgt = targets_root.get_node_or_null("%s_Target" % String(ln)) as Node3D

		if ray == null:
			miss_rays += 1
		if tgt == null:
			miss_targets += 1

		_rays[ln] = ray
		_targets[ln] = tgt

		_stepping[ln] = false
		_step_t[ln] = 0.0
		_leg_last_hit[ln] = false
		_leg_last_hit_p[ln] = Vector3.ZERO

		if tgt != null:
			_home_local[ln] = to_local(tgt.global_position)
			_foot_pos[ln] = tgt.global_position
		else:
			_home_local[ln] = Vector3.ZERO
			_foot_pos[ln] = global_position

	_start_all_ik()

	#if debug_print:
		##print("CRAWLER DBG | ready miss_targets:%s miss_rays:%s visual:%s probeDown:%s probeFwd:%s"
			#% [miss_targets, miss_rays, _visual_root != null, _probe_down != null, _probe_forward != null])

func _physics_process(delta: float) -> void:
	_update_surface(delta)
	_move_along_surface(delta)
	_update_legs(delta)
	_apply_targets()

	_dbg_t += delta
	if debug_print and _dbg_t >= debug_interval_sec:
		_dbg_t = 0.0
		_debug_tick()

# =========================
# SURFACE
# =========================
func _update_surface(delta: float) -> void:
	if _probe_down == null:
		return

	_probe_down.force_raycast_update()
	if _probe_forward != null:
		_probe_forward.force_raycast_update()

	var have := false
	var best_n := Vector3.UP
	var best_d := INF

	if _probe_down.is_colliding():
		var p := _probe_down.get_collision_point()
		var n := _probe_down.get_collision_normal().normalized()
		var d := global_position.distance_to(p)
		have = true
		best_n = n
		best_d = d

	if _probe_forward != null and _probe_forward.is_colliding():
		var p2 := _probe_forward.get_collision_point()
		var n2 := _probe_forward.get_collision_normal().normalized()
		var d2 := global_position.distance_to(p2)
		if (not have) or (d2 < best_d):
			have = true
			best_n = n2
			best_d = d2

	if have:
		_surface_normal = best_n

	# VisualRoot align (keep basis orthonormal!)
	if _visual_root != null:
		var up := _surface_normal
		var fwd := (-global_transform.basis.z).normalized()
		var fwd_proj := (fwd - up * fwd.dot(up))
		if fwd_proj.length() < 0.001:
			fwd_proj = (global_transform.basis.x - up * global_transform.basis.x.dot(up))
		fwd_proj = fwd_proj.normalized()

		var right := fwd_proj.cross(up).normalized()
		var target_basis := Basis(right, up, -fwd_proj).orthonormalized()

		var t := clampf(align_speed * delta, 0.0, 1.0)
		_visual_root.global_transform.basis = _visual_root.global_transform.basis.orthonormalized().slerp(target_basis, t)

# =========================
# MOVEMENT (TEMP INPUT)
# =========================
func _move_along_surface(delta: float) -> void:
	var v2 := Vector2.ZERO
	if Input.is_action_pressed("ui_up"): v2.y -= 1.0
	if Input.is_action_pressed("ui_down"): v2.y += 1.0
	if Input.is_action_pressed("ui_left"): v2.x -= 1.0
	if Input.is_action_pressed("ui_right"): v2.x += 1.0
	v2 = v2.normalized()

	var fwd := (-global_transform.basis.z).normalized()
	var right := (global_transform.basis.x).normalized()

	var wish := (right * v2.x + fwd * v2.y)
	wish = (wish - _surface_normal * wish.dot(_surface_normal))
	if wish.length() > 0.001:
		wish = wish.normalized()

	var desired := wish * move_speed
	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)

	velocity += -_surface_normal * stick_force * delta
	move_and_slide()

# =========================
# LEGS (manual raycast, not RayCast3D nodes)
# =========================
func _update_legs(delta: float) -> void:
	var group := GROUP_A if _use_group_a else GROUP_B

	for ln in group:
		if bool(_stepping[ln]):
			continue
		if _leg_needs_step(ln):
			_begin_step(ln)

	for ln in LEG_NAMES:
		if not bool(_stepping[ln]):
			continue

		_step_t[ln] = float(_step_t[ln]) + delta / maxf(step_duration, 0.01)
		var t := clampf(float(_step_t[ln]), 0.0, 1.0)

		var a: Vector3 = _step_from[ln] as Vector3
		var b: Vector3 = _step_to[ln] as Vector3

		var pos := a.lerp(b, t)
		pos += _surface_normal * (sin(t * PI) * step_height)
		_foot_pos[ln] = pos

		if t >= 1.0:
			_stepping[ln] = false
			_step_t[ln] = 0.0
			_foot_pos[ln] = b

	if _group_done(group):
		var other := GROUP_B if _use_group_a else GROUP_A
		if _group_needs_step(other):
			_use_group_a = not _use_group_a

func _apply_targets() -> void:
	for ln in LEG_NAMES:
		var tgt := _targets.get(ln, null) as Node3D
		if tgt == null:
			continue
		tgt.global_position = _foot_pos[ln]

func _leg_needs_step(ln: StringName) -> bool:
	var home := to_global(_home_local[ln] as Vector3)
	var cur := _foot_pos[ln] as Vector3
	return cur.distance_to(home) > step_distance

func _begin_step(ln: StringName) -> void:
	var home := to_global(_home_local[ln] as Vector3)

	# cast from slightly ABOVE the surface toward the surface normal direction
	var from := home + _surface_normal * leg_ray_start_offset
	var to := home - _surface_normal * leg_ray_length

	var hit := _raycast_world(from, to)
	var target := home - _surface_normal * leg_ray_fallback_offset

	if hit.has("position"):
		target = hit["position"] as Vector3
		_leg_last_hit[ln] = true
		_leg_last_hit_p[ln] = target
	else:
		_leg_last_hit[ln] = false
		_leg_last_hit_p[ln] = Vector3.ZERO

	_step_from[ln] = _foot_pos[ln]
	_step_to[ln] = target
	_stepping[ln] = true
	_step_t[ln] = 0.0

func _raycast_world(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [self]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.collision_mask = leg_ray_collision_mask
	return space.intersect_ray(q)

func _group_done(group: Array[StringName]) -> bool:
	for ln in group:
		if bool(_stepping[ln]):
			return false
	return true

func _group_needs_step(group: Array[StringName]) -> bool:
	for ln in group:
		if _leg_needs_step(ln):
			return true
	return false

# =========================
# IK
# =========================
func _start_all_ik() -> void:
	var sk := _find_skeleton()
	if sk == null:
		return
	for ik_any in sk.find_children("*", "SkeletonIK3D", true, false):
		var ik := ik_any as SkeletonIK3D
		if ik != null:
			ik.start()

func _find_skeleton() -> Skeleton3D:
	if _visual_root == null:
		return find_child("Skeleton3D", true, false) as Skeleton3D
	return _visual_root.find_child("Skeleton3D", true, false) as Skeleton3D

# =========================
# DEBUG
# =========================
func _debug_tick() -> void:
	var miss_targets := 0
	var miss_rays := 0
	for ln in LEG_NAMES:
		if (_targets.get(ln, null) as Node3D) == null:
			miss_targets += 1
		if (_rays.get(ln, null) as RayCast3D) == null:
			miss_rays += 1

	var down_ok := (_probe_down != null and _probe_down.is_colliding())
	var fwd_ok := (_probe_forward != null and _probe_forward.is_colliding())

	var moving := 0
	for ln in LEG_NAMES:
		var tgt := _targets.get(ln, null) as Node3D
		if tgt != null:
			# crude “moving” check: stepping or dHome > tiny
			var d := (_foot_pos[ln] as Vector3).distance_to(to_global(_home_local[ln] as Vector3))
			if bool(_stepping[ln]) or d > 0.02:
				moving += 1

	#print("CRAWLER DBG | down:%s fwd:%s vel:%s miss_targets:%s miss_rays:%s skel:%s"
	#	% [down_ok, fwd_ok, str(velocity), miss_targets, miss_rays, _find_skeleton() != null])
	#print("CRAWLER DBG | targets_moving:%s/8 step_dist:%s step_dur:%s"
	#	% [moving, step_distance, step_duration])

	for ln in LEG_NAMES:
		var cur := _foot_pos[ln] as Vector3
		var home := to_global(_home_local[ln] as Vector3)
		var d_home := cur.distance_to(home)

		var hit := bool(_leg_last_hit[ln])
		var hp := _leg_last_hit_p[ln] as Vector3

		#print("  leg:%s stepping:%s dHome:%.3f rayHit:%s tgt:%s rayP:%s"
		#	% [String(ln), bool(_stepping[ln]), d_home, hit, str(cur), str(hp)])
