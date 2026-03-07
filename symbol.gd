extends Node3D
class_name UvRevealTarget

# Drag the MeshInstance3D in here (or leave default if it’s a child named "Mesh")
@export var mesh_path: NodePath = NodePath("Mesh")

# Material slot to edit (0 is usually correct)
@export var material_surface: int = 0

# Shader param name used in the reveal material
@export var reveal_param_name: StringName = &"uv_reveal"

@onready var _mesh: MeshInstance3D = get_node_or_null(mesh_path) as MeshInstance3D
var _mat: ShaderMaterial = null

func _ready() -> void:
	if _mesh == null:
		push_error("[UvRevealTarget] mesh_path invalid. Set mesh_path to your MeshInstance3D.")
		return

	# Make sure we have a unique material instance for THIS object
	var base_mat := _mesh.get_surface_override_material(material_surface)
	if base_mat == null:
		push_error("[UvRevealTarget] No surface override material on MeshInstance3D. Assign the reveal ShaderMaterial.")
		return

	_mat = base_mat.duplicate(true) as ShaderMaterial
	if _mat == null:
		push_error("[UvRevealTarget] Material is not a ShaderMaterial. Assign the reveal ShaderMaterial.")
		return

	_mesh.set_surface_override_material(material_surface, _mat)

func set_reveal(amount: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter(reveal_param_name, clampf(amount, 0.0, 1.0))
