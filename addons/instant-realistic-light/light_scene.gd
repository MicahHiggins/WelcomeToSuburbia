extends WorldEnvironment

@export var sun_ref: DirectionalLight3D # can be "math only" (energy 0 is fine)

@export var look_start: float = 0.85   # when effect begins (0..1)
@export var look_end: float = 0.98     # when it reaches full strength
@export var response_speed: float = 6.0

@export var base_fog_light_energy: float = 1.0

# How much fog should remain when staring at the sun (0.0 = totally clear)
@export var min_fog_multiplier: float = 0.35

func _ready() -> void:
	# Capture your current fog values automatically if you want:
	if environment:
		base_fog_light_energy = environment.fog_light_energy

func _process(dt: float) -> void:
	if environment == null or sun_ref == null:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var cam_forward: Vector3 = (-cam.global_transform.basis.z).normalized()

	# DirectionalLight forward is -Z; direction TO the sun is opposite of that.
	var sun_forward: Vector3 = (-sun_ref.global_transform.basis.z).normalized()
	var to_sun: Vector3 = -sun_forward

	var raw_focus: float = clampf(cam_forward.dot(to_sun), 0.0, 1.0)
	var focus: float = smoothstep(look_start, look_end, raw_focus) # 0..1

	# When focus=1 (looking at sun), fog multiplier goes toward min_fog_multiplier
	var target_mult: float = lerpf(1.0, min_fog_multiplier, focus)

	# Smooth it so it feels natural
	environment.fog_light_energy = lerpf(environment.fog_light_energy, base_fog_light_energy * target_mult, dt * response_speed)
