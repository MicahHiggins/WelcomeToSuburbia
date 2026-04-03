extends Node3D

@export var uv_offset_strength: float = 0.35
@export var uv_scale_variation: float = 0.08

func _ready() -> void:
	var cs := find_child("CollisionShape3D", true, false) as CollisionShape3D
	if cs == null or cs.shape == null:
		print("[BlockSize] No CollisionShape3D/shape found.")
		return

	var box := cs.shape as BoxShape3D
	if box == null:
		print("[BlockSize] Shape is not BoxShape3D. It's:", cs.shape)
		return

	# IMPORTANT: include node scaling
	var s := cs.global_transform.basis.get_scale()
	var size_world := Vector3(
		abs(box.size.x * s.x),
		abs(box.size.y * s.y),
		abs(box.size.z * s.z)
	)

	print("[BlockSize] BoxShape size (world): ", size_world)
	
	var cube: MeshInstance3D = $Cube
	if cube == null:
		return

	var mat := cube.get_active_material(0)
	if mat == null:
		return

	# Make this block use its own copy of the material
	mat = mat.duplicate()
	cube.set_surface_override_material(0, mat)

	if mat is StandardMaterial3D:
		var S := _get_deterministic_seed()
		var rng := RandomNumberGenerator.new()
		rng.seed = S

		# Slightly shift the UVs so each cube looks different
		mat.uv1_offset = Vector3(
			rng.randf_range(-uv_offset_strength, uv_offset_strength),
			rng.randf_range(-uv_offset_strength, uv_offset_strength),
			0.0
		)

		# Slightly vary scale too
		var scale_x := rng.randf_range(1.0 - uv_scale_variation, 1.0 + uv_scale_variation)
		var scale_y := rng.randf_range(1.0 - uv_scale_variation, 1.0 + uv_scale_variation)
		mat.uv1_scale = Vector3(scale_x, scale_y, 1.0)

func _get_deterministic_seed() -> int:
	var p := global_position
	return int(p.x * 92821.0 + p.y * 68917.0 + p.z * 51787.0)
