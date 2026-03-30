extends Node3D

@onready var skeleton: Skeleton3D = $Armature/Skeleton3D

@export var move_speed: float = 2.0
@export var bend_strength: float = 28.0
@export var side_bend_strength: float = 18.0
@export var twist_strength: float = 16.0
@export var bone_delay: float = 0.22
@export var tip_multiplier: float = 1.8

@export var twitch_interval_min: float = 1.2
@export var twitch_interval_max: float = 3.0
@export var twitch_strength: float = 20.0
@export var twitch_speed: float = 16.0

@export var min_lifetime: float = 3.0
@export var max_lifetime: float = 10.0
@export var fade_duration: float = 2.0

var t: float = 0.0
var twitch_timer: float = 0.0
var twitch_active: bool = false
var twitch_phase: float = 0.0

var life_timer: float = 0.0
var life_limit: float = 5.0

var mesh_instance: MeshInstance3D = null

func _ready() -> void:
	randomize()
	twitch_timer = randf_range(twitch_interval_min, twitch_interval_max)
	life_limit = randf_range(min_lifetime, max_lifetime)

	if skeleton == null:
		push_error("Skeleton3D not found at $Armature/Skeleton3D")
		return

	mesh_instance = _find_mesh(self)
	if mesh_instance != null:
		_prepare_fade_materials(mesh_instance)

	add_to_group("tentacles_alive")

func _process(delta: float) -> void:
	if skeleton == null:
		return

	life_timer += delta
	_update_lifetime_fade()

	if life_timer >= life_limit:
		queue_free()
		return

	t += delta * move_speed

	if !twitch_active:
		twitch_timer -= delta
		if twitch_timer <= 0.0:
			twitch_active = true
			twitch_phase = 0.0
			twitch_timer = randf_range(twitch_interval_min, twitch_interval_max)
	else:
		twitch_phase += delta * twitch_speed
		if twitch_phase >= PI:
			twitch_active = false

	var bone_count: int = skeleton.get_bone_count()
	if bone_count <= 0:
		return

	for i in range(bone_count):
		var f: float = float(i) / max(float(bone_count - 1), 1.0)
		var tip_f: float = lerp(1.0, tip_multiplier, f)

		var forward_bend: float = sin(t + float(i) * bone_delay) * bend_strength * tip_f
		var side_bend: float = cos(t * 1.3 + float(i) * bone_delay * 1.15) * side_bend_strength * tip_f
		var twist: float = sin(t * 0.85 + float(i) * 0.35) * twist_strength * (0.35 + f * 0.65)

		var twitch: float = 0.0
		if twitch_active:
			twitch = sin(twitch_phase) * twitch_strength * f

		var x_rot: float = deg_to_rad(forward_bend + twitch)
		var z_rot: float = deg_to_rad(side_bend + twitch * 0.35)
		var y_rot: float = deg_to_rad(twist)

		var qx: Quaternion = Quaternion(Vector3.RIGHT, x_rot)
		var qy: Quaternion = Quaternion(Vector3.UP, y_rot)
		var qz: Quaternion = Quaternion(Vector3.FORWARD, z_rot)

		skeleton.set_bone_pose_rotation(i, qy * qx * qz)

func _update_lifetime_fade() -> void:
	if mesh_instance == null:
		return

	var fade_start: float = max(life_limit - fade_duration, 0.0)
	var alpha: float = 1.0

	if life_timer >= fade_start:
		var fade_t: float = (life_timer - fade_start) / max(fade_duration, 0.001)
		alpha = 1.0 - clamp(fade_t, 0.0, 1.0)

	_apply_alpha(mesh_instance, alpha)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D

	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found

	return null

func _prepare_fade_materials(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return

	for i in range(mesh.mesh.get_surface_count()):
		var base_mat: Material = mesh.get_active_material(i)
		if base_mat == null:
			continue

		var new_mat: Material = base_mat.duplicate(true)

		if new_mat is StandardMaterial3D:
			var sm: StandardMaterial3D = new_mat as StandardMaterial3D
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		elif new_mat is ORMMaterial3D:
			var om: ORMMaterial3D = new_mat as ORMMaterial3D
			om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			om.cull_mode = BaseMaterial3D.CULL_DISABLED

		mesh.set_surface_override_material(i, new_mat)

func _apply_alpha(mesh: MeshInstance3D, alpha: float) -> void:
	if mesh.mesh == null:
		return

	for i in range(mesh.mesh.get_surface_count()):
		var mat: Material = mesh.get_active_material(i)
		if mat == null:
			continue

		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat as StandardMaterial3D
			var c: Color = sm.albedo_color
			c.a = alpha
			sm.albedo_color = c
		elif mat is ORMMaterial3D:
			var om: ORMMaterial3D = mat as ORMMaterial3D
			var c: Color = om.albedo_color
			c.a = alpha
			om.albedo_color = c
