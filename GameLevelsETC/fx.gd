extends CanvasLayer

@export var sun_light: DirectionalLight3D

@export var shader_rect: ColorRect

func _process(_dt):
	var camera := get_viewport().get_camera_3d()
	if sun_light == null or camera == null or shader_rect == null:
		return

	# Camera forward is -basis.z
	var cam_forward: Vector3 = -camera.global_transform.basis.z.normalized()

	# DirectionalLight points along -Z as well (its "forward")
	var sun_forward: Vector3 = -sun_light.global_transform.basis.z.normalized()

	# If you want "direction to the sun in the sky", use the opposite:
	var to_sun: Vector3 = -sun_forward

	# 1.0 when looking directly at the sun, 0.0 at 90 degrees, negative behind you
	var focus := clampf(cam_forward.dot(to_sun), 0.0, 1.0)

	var mat := shader_rect.material as ShaderMaterial
	mat.set_shader_parameter("sun_focus", focus)
