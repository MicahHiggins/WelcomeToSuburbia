extends Node3D
class_name LeverFx

# This matches your tree: Lever(Node3D) -> Area3D + MeshInstance3D
@export var mesh_path: NodePath = NodePath("MeshInstance3D")
@export var swing_degrees: float = -55.0
@export var swing_time: float = 0.18
@export var return_time: float = 0.10

# Optional: if you add a light as a child later, set it here
@export var light_path: NodePath = NodePath("DirectionalLight3D")
@export var flash_time: float = 0.20

var _mesh: Node3D
var _light: Node3D
var _busy := false

func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as Node3D
	_light = get_node_or_null(light_path) as Node3D
	if _light != null:
		_light.visible = false

func play_pull_fx() -> void:
	if _busy:
		return
	_busy = true

	# simple lever swing (feels snappy)
	if _mesh != null:
		var base_rot := _mesh.rotation
		var target_rot := base_rot + Vector3(deg_to_rad(swing_degrees), 0.0, 0.0)

		var t := create_tween()
		t.tween_property(_mesh, "rotation", target_rot, swing_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(_mesh, "rotation", base_rot, return_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# optional flash
	if _light != null:
		_light.visible = true
		await get_tree().create_timer(flash_time).timeout
		if is_instance_valid(_light):
			_light.visible = false

	_busy = false
