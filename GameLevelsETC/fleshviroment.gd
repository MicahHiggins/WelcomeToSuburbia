
extends WorldEnvironment
class_name FleshDungeonWorldEnvironment

# ============================================================
#  Flesh Dungeon WorldEnvironment 
#  - Sets Environment fog/grade/glow 
#  - Spawns player-POV particles + screen overlay under Camera3D
# ============================================================

@export var enable_fx: bool = true
@export var reattach_check_interval_sec: float = 0.5

# ------------------------------------------------------------
# ENVIRONMENT LOOK
# ------------------------------------------------------------
@export var apply_environment_tweaks: bool = true
@export var fog_enabled: bool = true
@export var fog_density: float = 0.055
@export var fog_color: Color = Color(0.70, 0.18, 0.20)
@export var fog_depth_begin: float = 1.0
@export var fog_depth_end: float = 42.0

@export var exposure: float = 0.92
@export var contrast: float = 1.22
@export var saturation: float = 0.72
@export var brightness: float = 1.02

@export var glow_enabled: bool = true
@export var glow_strength: float = 0.30

# "heartbeat" pulse (subtle global pulse)
@export var heartbeat_enabled: bool = true
@export var heartbeat_period_sec: float = 2.2
@export var heartbeat_strength: float = 0.12  # affects exposure/glow/fog slightly

# ------------------------------------------------------------
# PARTICLES + SCREEN OVERLAY
# ------------------------------------------------------------
@export var spores_enabled: bool = true
@export var droplets_enabled: bool = true
@export var post_enabled: bool = true

# spores
@export var spores_amount: int = 260
@export var spores_lifetime: float = 7.0
@export var spores_spawn_box: Vector3 = Vector3(1.6, 1.1, 2.8) # box in front of camera
@export var spores_velocity: float = 0.10
@export var spores_scale_min: float = 0.015
@export var spores_scale_max: float = 0.050
@export var spores_alpha: float = 0.24
@export var spores_color: Color = Color(0.92, 0.40, 0.44)

# droplets
@export var droplets_amount: int = 110
@export var droplets_lifetime: float = 3.2
@export var droplets_spawn_box: Vector3 = Vector3(1.3, 0.8, 2.4)
@export var droplets_fall_speed: float = 0.65
@export var droplets_scale_min: float = 0.02
@export var droplets_scale_max: float = 0.07
@export var droplets_alpha: float = 0.20
@export var droplets_color: Color = Color(0.75, 0.08, 0.10)

# post overlay
@export var post_intensity: float = 0.62
@export var wobble_strength: float = 0.014
@export var wobble_speed: float = 0.60
@export var vignette_strength: float = 0.46
@export var grain_strength: float = 0.10
@export var chroma_edge: float = 0.0024
@export var tint_color: Color = Color(0.85, 0.30, 0.34)
@export var tint_strength: float = 0.12

# ------------------------------------------------------------
# INTERNAL
# ------------------------------------------------------------
const RIG_NAME: StringName = &"FleshFXRig"

var _env: Environment = null
var _prop_cache: Dictionary = {}
var _timer_attach: Timer = null
var _timer_beat: Timer = null

var _attached_cam: Camera3D = null
var _rig: Node = null

# cached baseline for heartbeat pulse
var _base_fog_density: float = 0.0
var _base_exposure: float = 1.0
var _base_glow_strength: float = 0.0

func _ready() -> void:
	_env = environment
	if _env == null:
		push_error("[FleshDungeonWorldEnvironment] Assign an Environment resource to this WorldEnvironment node.")
		return

	_cache_env_properties()

	if apply_environment_tweaks:
		_apply_env_baseline()

	# attach tick (handles level reloads / camera re-creation inside this scene)
	_timer_attach = Timer.new()
	_timer_attach.one_shot = false
	_timer_attach.wait_time = maxf(0.1, reattach_check_interval_sec)
	add_child(_timer_attach)
	_timer_attach.timeout.connect(_tick_attach)
	_timer_attach.start()

	_tick_attach()

	# heartbeat pulse 
	if heartbeat_enabled:
		_timer_beat = Timer.new()
		_timer_beat.one_shot = false
		_timer_beat.wait_time = maxf(0.3, heartbeat_period_sec)
		add_child(_timer_beat)
		_timer_beat.timeout.connect(_beat_pulse)
		_timer_beat.start()

func _exit_tree() -> void:
	if _timer_attach != null and is_instance_valid(_timer_attach):
		_timer_attach.stop()
	if _timer_beat != null and is_instance_valid(_timer_beat):
		_timer_beat.stop()
	_detach_rig()

# ============================================================
# ENV SAFETY
# ============================================================
func _cache_env_properties() -> void:
	_prop_cache.clear()
	for d_any in _env.get_property_list():
		var d: Dictionary = d_any as Dictionary
		if d != null and d.has("name"):
			_prop_cache[String(d["name"])] = true

func _has_prop(p: String) -> bool:
	return _prop_cache.has(p)

func _set_if_has(prop: String, value: Variant) -> void:
	if _has_prop(prop):
		_env.set(prop, value)

func _apply_env_baseline() -> void:
	# Fog
	_set_if_has("fog_enabled", fog_enabled)
	_set_if_has("fog_density", fog_density)
	_set_if_has("fog_light_color", fog_color)
	_set_if_has("fog_depth_begin", fog_depth_begin)
	_set_if_has("fog_depth_end", fog_depth_end)

	# Grade
	_set_if_has("adjustment_enabled", true)
	_set_if_has("tonemap_exposure", exposure)
	_set_if_has("adjustment_brightness", brightness)
	_set_if_has("adjustment_contrast", contrast)
	_set_if_has("adjustment_saturation", saturation)

	# Glow
	_set_if_has("glow_enabled", glow_enabled)
	_set_if_has("glow_strength", glow_strength)

	# Cache baseline values for heartbeat
	if _has_prop("fog_density"):
		_base_fog_density = float(_env.get("fog_density"))
	if _has_prop("tonemap_exposure"):
		_base_exposure = float(_env.get("tonemap_exposure"))
	if _has_prop("glow_strength"):
		_base_glow_strength = float(_env.get("glow_strength"))

# ============================================================
# HEARTBEAT PULSE
# ============================================================
func _beat_pulse() -> void:
	if not heartbeat_enabled:
		return
	if _env == null:
		return

	var t := create_tween()
	t.set_parallel(true)

	# pulse up then back down
	if _has_prop("tonemap_exposure"):
		t.tween_property(_env, "tonemap_exposure", _base_exposure + heartbeat_strength * 0.35, 0.10)
		t.tween_property(_env, "tonemap_exposure", _base_exposure, 0.35).set_delay(0.10)

	if _has_prop("glow_strength"):
		t.tween_property(_env, "glow_strength", _base_glow_strength + heartbeat_strength * 0.55, 0.10)
		t.tween_property(_env, "glow_strength", _base_glow_strength, 0.35).set_delay(0.10)

	if _has_prop("fog_density"):
		t.tween_property(_env, "fog_density", _base_fog_density + heartbeat_strength * 0.05, 0.10)
		t.tween_property(_env, "fog_density", _base_fog_density, 0.35).set_delay(0.10)

# ============================================================
# CAMERA ATTACH
# ============================================================
func _tick_attach() -> void:
	if not enable_fx:
		_detach_rig()
		return

	var cam: Camera3D = _find_active_camera()
	if cam == null:
		return

	if cam != _attached_cam or _rig == null or not is_instance_valid(_rig):
		_attach_to_camera(cam)
	else:
		_push_params_to_rig()

func _find_active_camera() -> Camera3D:
	var vp := get_viewport()
	if vp != null:
		var c := vp.get_camera_3d()
		if c != null:
			return c

	# fallback: find any Camera3D in scene
	var cams: Array = get_tree().get_nodes_in_group("player_camera")
	for any in cams:
		var c2 := any as Camera3D
		if c2 != null:
			return c2

	# brute fallback: scan children
	var scene := get_tree().current_scene
	if scene != null:
		var found := scene.find_child("Camera3D", true, false)
		return found as Camera3D

	return null

func _attach_to_camera(cam: Camera3D) -> void:
	_detach_rig()

	_attached_cam = cam
	_rig = Node3D.new()
	_rig.name = String(RIG_NAME)
	cam.add_child(_rig)

	_build_rig_nodes(_rig)
	_push_params_to_rig()

func _detach_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.queue_free()
	_rig = null
	_attached_cam = null

# ============================================================
# BUILD RIG
# ============================================================
func _build_rig_nodes(rig: Node) -> void:
	if spores_enabled:
		var spores := _make_spores_particles()
		spores.name = "Spores"
		rig.add_child(spores)

	if droplets_enabled:
		var drops := _make_droplet_particles()
		drops.name = "Droplets"
		rig.add_child(drops)

	if post_enabled:
		var canvas := CanvasLayer.new()
		canvas.name = "FleshPostFX"
		canvas.layer = 200
		rig.add_child(canvas)

		var rect := ColorRect.new()
		rect.name = "Screen"
		rect.anchor_left = 0
		rect.anchor_top = 0
		rect.anchor_right = 1
		rect.anchor_bottom = 1
		rect.offset_left = 0
		rect.offset_top = 0
		rect.offset_right = 0
		rect.offset_bottom = 0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(rect)

		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = _post_shader_code()
		rect.material = mat

func _push_params_to_rig() -> void:
	if _rig == null or not is_instance_valid(_rig):
		return

	var spores := _rig.get_node_or_null("Spores") as GPUParticles3D
	if spores != null:
		spores.amount = max(1, spores_amount)
		spores.lifetime = maxf(0.1, spores_lifetime)
		var pm := spores.process_material as ParticleProcessMaterial
		if pm != null:
			pm.emission_box_extents = spores_spawn_box * 0.5
			pm.initial_velocity_max = spores_velocity
			pm.scale_min = spores_scale_min
			pm.scale_max = spores_scale_max
			pm.color = Color(spores_color.r, spores_color.g, spores_color.b, spores_alpha)

	var drops := _rig.get_node_or_null("Droplets") as GPUParticles3D
	if drops != null:
		drops.amount = max(1, droplets_amount)
		drops.lifetime = maxf(0.1, droplets_lifetime)
		var pm2 := drops.process_material as ParticleProcessMaterial
		if pm2 != null:
			pm2.emission_box_extents = droplets_spawn_box * 0.5
			pm2.initial_velocity_min = droplets_fall_speed * 0.75
			pm2.initial_velocity_max = droplets_fall_speed
			pm2.scale_min = droplets_scale_min
			pm2.scale_max = droplets_scale_max
			pm2.color = Color(droplets_color.r, droplets_color.g, droplets_color.b, droplets_alpha)

	var rect := _rig.get_node_or_null("FleshPostFX/Screen") as ColorRect
	if rect != null:
		var sm := rect.material as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter("intensity", post_intensity)
			sm.set_shader_parameter("wobble_strength", wobble_strength)
			sm.set_shader_parameter("wobble_speed", wobble_speed)
			sm.set_shader_parameter("vignette_strength", vignette_strength)
			sm.set_shader_parameter("grain_strength", grain_strength)
			sm.set_shader_parameter("chroma_edge", chroma_edge)
			sm.set_shader_parameter("tint_color", tint_color)
			sm.set_shader_parameter("tint_strength", tint_strength)

# ============================================================
# PARTICLES
# ============================================================
func _make_billboard_quad_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.disable_receive_shadows = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true

	q.material = mat
	return q

func _make_spores_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = max(1, spores_amount)
	p.lifetime = maxf(0.1, spores_lifetime)
	p.one_shot = false
	p.emitting = true
	p.draw_pass_1 = _make_billboard_quad_mesh()

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = spores_spawn_box * 0.5
	m.direction = Vector3(0, 0, -1)
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = spores_velocity
	m.orbit_velocity_min = -0.18
	m.orbit_velocity_max = 0.18
	m.angular_velocity_min = -0.6
	m.angular_velocity_max = 0.6
	m.gravity = Vector3.ZERO
	m.scale_min = spores_scale_min
	m.scale_max = spores_scale_max
	m.color = Color(spores_color.r, spores_color.g, spores_color.b, spores_alpha)
	p.process_material = m
	return p

func _make_droplet_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = max(1, droplets_amount)
	p.lifetime = maxf(0.1, droplets_lifetime)
	p.one_shot = false
	p.emitting = true
	p.draw_pass_1 = _make_billboard_quad_mesh()

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = droplets_spawn_box * 0.5
	m.direction = Vector3(0, -1, -0.10).normalized()
	m.initial_velocity_min = droplets_fall_speed * 0.75
	m.initial_velocity_max = droplets_fall_speed
	m.tangential_accel_min = -0.16
	m.tangential_accel_max = 0.16
	m.radial_accel_min = -0.08
	m.radial_accel_max = 0.08
	m.gravity = Vector3.ZERO
	m.scale_min = droplets_scale_min
	m.scale_max = droplets_scale_max
	m.color = Color(droplets_color.r, droplets_color.g, droplets_color.b, droplets_alpha)
	p.process_material = m
	return p

# ============================================================
# POST SHADER
# ============================================================
func _post_shader_code() -> String:
	return """
shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.62;
uniform float wobble_strength : hint_range(0.0, 0.05) = 0.014;
uniform float wobble_speed : hint_range(0.0, 3.0) = 0.60;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.46;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.10;
uniform float chroma_edge : hint_range(0.0, 0.02) = 0.0024;

uniform vec4 tint_color : source_color = vec4(0.85, 0.30, 0.34, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.12;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * wobble_speed;

	float w1 = sin((uv.y * 10.0 + t * 1.4)) * cos((uv.x * 8.0 - t * 1.1));
	float w2 = sin((uv.x * 12.0 - t * 1.7)) * 0.5;
	vec2 offs = vec2(w1 + w2, -w1) * (wobble_strength * intensity);

	vec2 p = uv - 0.5;
	float r2 = dot(p, p);
	float edge = smoothstep(0.08, 0.38, r2) * chroma_edge * intensity;

	vec4 cR = texture(screen_tex, uv + offs + vec2(edge, 0.0));
	vec4 cG = texture(screen_tex, uv + offs);
	vec4 cB = texture(screen_tex, uv + offs - vec2(edge, 0.0));

	vec4 col = vec4(cR.r, cG.g, cB.b, 1.0);

	col.rgb = mix(col.rgb, col.rgb * tint_color.rgb, tint_strength * intensity);

	float vig = smoothstep(0.12, 0.70, r2);
	col.rgb *= 1.0 - (vig * vignette_strength * intensity);

	float g = hash(uv * vec2(1800.0, 900.0) + vec2(t * 31.0, t * 17.0)) - 0.5;
	col.rgb += g * (grain_strength * intensity);

	COLOR = col;
}
"""
