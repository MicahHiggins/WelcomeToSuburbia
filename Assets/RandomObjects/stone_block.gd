extends Node3D

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
