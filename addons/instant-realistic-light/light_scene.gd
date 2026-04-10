extends WorldEnvironment

@export var sun_ref: DirectionalLight3D # can be "math only" (energy 0 is fine)

@export var look_start: float = 0.85   # when effect begins (0..1)
@export var look_end: float = 0.98     # when it reaches full strength
@export var response_speed: float = 6.0

@export var base_fog_light_energy: float = 1.0

# How much fog should remain when staring at the sun (0.0 = totally clear)
@export var min_fog_multiplier: float = 0.35

@export var base_fog_depth: float = 1.0

# How close fog should be when staring at the sun (0.0 = no distance)
@export var min_fog_depth: float = 0.90

@export var base_sky_color: Color = Color(1.0,0.92,0.26,1.0)
# sky color after looking at sun
@export var changed_sky_color:  Color = Color(0.709, 0.0, 0.332, 1.0)

#@export var base_sun_size: float = 100.0
## sun size after looking at sun
#@export var changed_sun_size: float = 1000.0

@export var base_sun_curve: float = 0.0588
# sun size after looking at sun
@export var changed_sun_curve: float = 1.35

#Stops changing at 6th iteration
@export var max_iterations: float = 10.0
@export var max_iterations2: float = 6.0

# How quickly the environment catches up to the target look
@export var transition_speed: float = 2.0

# Starting look
@export var start_exposure: float = 1.0
@export var start_ambient_energy: float = 1.0
@export var start_saturation: float = 1.4
@export var start_color: Color = Color(1.0, 1.0, 1.0)

# Ending look (darker / scarier)
@export var end_exposure: float = 0.14
@export var end_ambient_energy: float = 0.2
@export var end_saturation: float = 0.25
@export var end_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var current_exposure: float
var current_ambient_energy: float
var current_saturation: float
var current_color: Color

# Fog distance change
@export var start_depth_begin: float = 80.0
@export var end_depth_begin: float = 40.0
@export var start_depth_end: float = 300.0
@export var end_depth_end: float = 120.0

# Color cycle speed
@export var cycle_speed: float = 0.22

# Red creep strength
@export var red_shift_strength: float = 0.55

# Creepy pulse
@export var pulse_speed: float = 2.8
@export var pulse_strength: float = 0.05

func _ready() -> void:
	# Capture your current fog values automatically if you want:
	if environment:
		base_fog_light_energy = environment.fog_light_energy
		base_fog_depth = environment.fog_sky_affect
		var sky := environment.sky
		if sky and sky.sky_material:
			base_sky_color = sky.sky_material.sky_top_color
			#base_sun_size = sky.sky_material.sun_angle_max
			base_sun_curve = sky.sky_material.sun_curve
		
	# Make sure we have adjustment enabled so saturation/color can work
	environment.adjustment_enabled = true

	current_exposure = start_exposure
	current_ambient_energy = start_ambient_energy
	current_saturation = start_saturation
	current_color = start_color

	apply_environment_values()
	update_fog_color()

func _process(delta: float) -> void:
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
	var target_mult2: float = lerpf(1.0, min_fog_depth, focus)
	#var target_mult3: float = lerpf(1.0, changed_sun_size, focus)
	var target_mult4: float = lerpf(1.0, changed_sun_curve, focus)
	var targ_color: Color = base_sky_color.lerp(changed_sky_color, focus)

	# Smooth it so it feels natural
	environment.fog_light_energy = lerpf(environment.fog_light_energy, base_fog_light_energy * target_mult, delta * response_speed)
	environment.fog_sky_affect = lerpf(environment.fog_sky_affect, base_fog_depth * target_mult2, delta * response_speed)
	var sky := environment.sky
	if sky and sky.sky_material:
		sky.sky_material.sky_top_color = sky.sky_material.sky_top_color.lerp(targ_color, delta * response_speed)
		#sky.sky_material.sun_angle_max = lerpf(sky.sky_material.sun_angle_max, base_sun_size * target_mult3, delta * response_speed)
		sky.sky_material.sun_curve = lerpf(sky.sky_material.sun_curve, base_sun_curve * target_mult4, delta * response_speed)

	
	if environment == null:
		return

	var iterations_value: float = GlobalVariables.iterations

	# Convert iterations into a 0.0 -> 1.0 progress value
	var t := clamp(iterations_value / max_iterations, 0.0, 1.0)

	# Target values as iterations increase
	var target_exposure := lerp(start_exposure, end_exposure, t)
	var target_ambient_energy := lerp(start_ambient_energy, end_ambient_energy, t)
	var target_saturation := lerp(start_saturation, end_saturation, t)
	var target_color := start_color.lerp(end_color, t)

	# Smooth transition
	current_exposure = lerp(current_exposure, target_exposure, transition_speed * delta)
	current_ambient_energy = lerp(current_ambient_energy, target_ambient_energy, transition_speed * delta)
	current_saturation = lerp(current_saturation, target_saturation, transition_speed * delta)
	current_color = current_color.lerp(target_color, transition_speed * delta)

	apply_environment_values()
	update_fog_color()

func apply_environment_values() -> void:
	# Darker overall image
	environment.tonemap_exposure = current_exposure

	# Less ambient fill light = scarier shadows
	environment.ambient_light_energy = current_ambient_energy

	# Slightly drained / unsettling colors
	environment.adjustment_saturation = current_saturation
	environment.adjustment_color_correction = null
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.0

	# Apply a subtle tint through ambient light color
	environment.ambient_light_color = current_color
	
func update_fog_color() -> void:
	var iters: float = float(GlobalVariables.iterations)
	var iter_t: float = clamp(iters / max_iterations, 0.0, 1.0)
	var time_sec: float = Time.get_ticks_msec() / 1000.0

	# 1) Pull fog closer as ITERS rises
	environment.fog_depth_begin = lerp(start_depth_begin, end_depth_begin, iter_t)
	environment.fog_depth_end = lerp(start_depth_end, end_depth_end, iter_t)

	# 2) 2) Base color loop
	# blue -> greener -> blue -> purpler -> blue
	# -----------------------------
	var blue := Color8(0, 154, 253)
	var greener := Color8(0, 172, 238)
	var purpler := Color8(35, 138, 255)
	
	var cycle_pos := fposmod(time_sec * cycle_speed, 4.0)
	var loop_color: Color
	
	if cycle_pos < 1.0:
		loop_color = blue.lerp(greener, cycle_pos)
	elif cycle_pos < 2.0:
		loop_color = greener.lerp(blue, cycle_pos - 1.0)
	elif cycle_pos < 3.0:
		loop_color = blue.lerp(purpler, cycle_pos - 2.0)
	else:
		loop_color = purpler.lerp(blue, cycle_pos - 3.0)
	
	# -----------------------------
	# 3) Red-shift the CURRENT loop color
	# This keeps the greener/purpler variants intact
	# -----------------------------
	var red_target := Color(
		min(loop_color.r + 0.35, 1.0),
		max(loop_color.g - 0.08, 0.0),
		max(loop_color.b - 0.12, 0.0),
		1.0
	)
	
	var shifted_color := loop_color.lerp(red_target, red_shift_strength * iter_t)
	
	# -----------------------------
	# 4) Subtle creepy pulse
	# Small enough that it won't flash red
	# -----------------------------
	var pulse := sin(time_sec * pulse_speed) * pulse_strength * iter_t
	
	var final_r := clamp(shifted_color.r + pulse, 0.0, 1.0)
	var final_g := clamp(shifted_color.g - pulse * 0.25, 0.0, 1.0)
	var final_b := clamp(shifted_color.b - pulse * 0.45, 0.0, 1.0)
	
	environment.fog_light_color = Color(final_r, final_g, final_b, 1.0)
