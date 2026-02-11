extends Area3D
class_name RuleArea

@export var enabled: bool = true
@export var rule_tag: StringName = &"default"

@onready var _shape_node: CollisionShape3D = $CollisionShape3D

func contains_world_point(p: Vector3) -> bool:
	if not enabled:
		return false
	if _shape_node == null:
		return false

	var shape: Shape3D = _shape_node.shape
	if shape == null:
		return false

	if not (shape is BoxShape3D):
		return false

	var box: BoxShape3D = shape as BoxShape3D
	var he: Vector3 = box.size * 0.5

	var local_p: Vector3 = _shape_node.global_transform.affine_inverse() * p

	return (
		local_p.x >= -he.x and local_p.x <= he.x
		and local_p.y >= -he.y and local_p.y <= he.y
		and local_p.z >= -he.z and local_p.z <= he.z
	)
