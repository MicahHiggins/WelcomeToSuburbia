extends Node3D
class_name UvRevealTarget

@export var target_mesh_path: NodePath
@export var auto_add_to_group: bool = true

# Slower = smaller numbers (units/sec)
@export var fade_in_speed: float = 2.0
@export var fade_out_speed: float = 0.8

@export var glow_color: Color = Color(0.3, 0.9, 1.0, 1.0)
@export var glow_strength: float = 3.0

# hold full brightness after UV stops
@export var hold_full_seconds: float = 3.0

var _mesh: MeshInstance3D = null
var _mat: ShaderMaterial = null

var _reveal: float = 0.0
var _want_on: bool = false
var _hold_t: float = 0.0


func _ready() -> void:
	if auto_add_to_group:
		add_to_group("uv_reveal")

	_mesh = _resolve_mesh()
	if _mesh == null:
		push_warning("[UvRevealTarget] No MeshInstance3D found. Set target_mesh_path or put a MeshInstance3D under this node.")
		return

	# Prefer surface material 0, fallback to material_override
	_mat = _mesh.get_active_material(0) as ShaderMaterial
	if _mat == null:
		_mat = _mesh.material_override as ShaderMaterial

	if _mat == null:
		push_warning("[UvRevealTarget] Target mesh has no ShaderMaterial (surface 0 or material_override).")
		return

	_apply_params()
	set_process(true)


func _resolve_mesh() -> MeshInstance3D:
	# If you set an explicit path, use it
	if target_mesh_path != NodePath(""):
		var m: MeshInstance3D = get_node_or_null(target_mesh_path) as MeshInstance3D
		if m != null:
			return m

	# Fallback: find first MeshInstance3D under this node (no Variant inference)
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var children: Array[Node] = n.get_children()
		for ch: Node in children:
			if ch is MeshInstance3D:
				return ch as MeshInstance3D
			stack.append(ch)

	return null


func set_reveal(v: bool) -> void:
	# called by flashlight
	if v:
		_want_on = true
		_hold_t = hold_full_seconds
	else:
		# don’t turn off instantly; let hold timer expire
		_want_on = false


func _process(delta: float) -> void:
	if _mat == null:
		return

	# If being hit this frame, keep refreshing the hold timer
	if _want_on:
		_hold_t = hold_full_seconds
	else:
		_hold_t = maxf(0.0, _hold_t - delta)

	# Full bright while hold timer is active, then fade out
	var target: float = 1.0 if _hold_t > 0.0 else 0.0

	if target > _reveal:
		_reveal = move_toward(_reveal, target, fade_in_speed * delta)
	else:
		_reveal = move_toward(_reveal, target, fade_out_speed * delta)

	_apply_params()


func _apply_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("reveal", _reveal)
	_mat.set_shader_parameter("glow_color", glow_color)
	_mat.set_shader_parameter("glow_strength", glow_strength)
