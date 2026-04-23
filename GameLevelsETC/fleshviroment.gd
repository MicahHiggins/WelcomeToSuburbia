extends WorldEnvironment
class_name FleshDungeonWorldEnvironment

@export var enable_fx: bool = true
@export var reattach_check_interval_sec: float = 0.5

# ------------------------------------------------------------
# ENVIRONMENT LOOK
# ------------------------------------------------------------
@export var apply_environment_tweaks: bool = true
@export var fog_enabled: bool = true

# red fog but less overall haze
@export var fog_density: float = 0.016
@export var fog_color: Color = Color(0.55, 0.10, 0.12)
@export var fog_depth_begin: float = 0.9
@export var fog_depth_end: float = 22.0

# grade
@export var exposure: float = 0.98
@export var contrast: float = 1.34
@export var saturation: float = 0.92
@export var brightness: float = 0.98

@export var glow_enabled: bool = true
@export var glow_strength: float = 0.26

# enclosed ambient so sealed rooms don't go dead
@export var ambient_enabled: bool = true
@export var ambient_color: Color = Color(0.32, 0.06, 0.07)
@export var ambient_energy: float = 0.45

# heartbeat pulse
@export var heartbeat_enabled: bool = true
@export var heartbeat_period_sec: float = 2.2
@export var heartbeat_strength: float = 0.14

# ------------------------------------------------------------
# CAMERA LIGHTING (enclosed)
# ------------------------------------------------------------
@export var lights_enabled: bool = true
@export var main_light_color: Color = Color(0.90, 0.22, 0.20)
@export var main_light_energy: float = 0.85
@export var main_light_range: float = 11.0

@export var spec_light_color: Color = Color(1.0, 0.55, 0.50)
@export var spec_light_energy: float = 0.38
@export var spec_light_range: float = 6.0

@export var light_flicker_enabled: bool = true
@export var light_flicker_amount: float = 0.10
@export var light_flicker_speed: float = 2.0

# ------------------------------------------------------------
# PARTICLES + SCREEN OVERLAY
# ------------------------------------------------------------
@export var spores_enabled: bool = true
@export var droplets_enabled: bool = true
@export var post_enabled: bool = true

# spores
@export var spores_amount: int = 110
@export var spores_lifetime: float = 7.0
@export var spores_spawn_box: Vector3 = Vector3(1.6, 1.1, 2.8)
@export var spores_velocity: float = 0.06
@export var spores_scale_min: float = 0.010
@export var spores_scale_max: float = 0.032
@export var spores_alpha: float = 0.13
@export var spores_color: Color = Color(0.85, 0.22, 0.24)

# droplets (make these read like goo)
@export var droplets_amount: int = 190
@export var droplets_lifetime: float = 3.8
@export var droplets_spawn_box: Vector3 = Vector3(1.35, 0.95, 2.7)
@export var droplets_fall_speed: float = 0.42
@export var droplets_scale_min: float = 0.030
@export var droplets_scale_max: float = 0.095
@export var droplets_alpha: float = 0.36
@export var droplets_color: Color = Color(0.55, 0.06, 0.07)

# post
@export var post_intensity: float = 0.62
@export var wobble_strength: float = 0.009
@export var wobble_speed: float = 0.55
@export var vignette_strength: float = 0.58
@export var grain_strength: float = 0.05
@export var chroma_edge: float = 0.0010
@export var tint_color: Color = Color(0.85, 0.22, 0.24)
@export var tint_strength: float = 0.09

# goo/wet film
@export var wet_film_strength: float = 0.42
@export var wet_film_speed: float = 0.55
@export var wet_film_scale: float = 1.8

# drip streaks
@export var drip_strength: float = 0.28
@export var drip_speed: float = 0.25
@export var drip_scale: float = 1.2

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

var _base_fog_density: float = 0.0
var _base_exposure: float = 1.0
var _base_glow_strength: float = 0.0

var _base_main_light_energy: float = 0.0
var _base_spec_light_energy: float = 0.0

var _tex_spore: Texture2D = null
var _tex_droplet: Texture2D = null

func _ready() -> void:
	_env = environment
	if _env == null:
		push_error("[FleshDungeonWorldEnvironment] Assign an Environment resource to this WorldEnvironment node.")
		return

	_cache_env_properties()

	if apply_environment_tweaks:
		_apply_env_baseline()

	_timer_attach = Timer.new()
	_timer_attach.one_shot = false
	_timer_attach.wait_time = maxf(0.1, reattach_check_interval_sec)
	add_child(_timer_attach)
	_timer_attach.timeout.connect(_tick_attach)
	_timer_attach.start()

	_tick_attach()

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
	_set_if_has("fog_enabled", fog_enabled)
	_set_if_has("fog_density", fog_density)
	_set_if_has("fog_light_color", fog_color)
	_set_if_has("fog_depth_begin", fog_depth_begin)
	_set_if_has("fog_depth_end", fog_depth_end)

	_set_if_has("adjustment_enabled", true)
	_set_if_has("tonemap_exposure", exposure)
	_set_if_has("adjustment_brightness", brightness)
	_set_if_has("adjustment_contrast", contrast)
	_set_if_has("adjustment_saturation", saturation)

	_set_if_has("glow_enabled", glow_enabled)
	_set_if_has("glow_strength", glow_strength)

	if ambient_enabled:
		_set_if_has("ambient_light_source", Environment.AMBIENT_SOURCE_COLOR)
		_set_if_has("ambient_light_color", ambient_color)
		_set_if_has("ambient_light_energy", ambient_energy)

	if _has_prop("fog_density"):
		_base_fog_density = float(_env.get("fog_density"))
	if _has_prop("tonemap_exposure"):
		_base_exposure = float(_env.get("tonemap_exposure"))
	if _has_prop("glow_strength"):
		_base_glow_strength = float(_env.get("glow_strength"))

func _beat_pulse() -> void:
	if not heartbeat_enabled:
		return
	if _env == null:
		return

	var t := create_tween()
	t.set_parallel(true)

	if _has_prop("tonemap_exposure"):
		t.tween_property(_env, "tonemap_exposure", _base_exposure + heartbeat_strength * 0.35, 0.10)
		t.tween_property(_env, "tonemap_exposure", _base_exposure, 0.35).set_delay(0.10)

	if _has_prop("glow_strength"):
		t.tween_property(_env, "glow_strength", _base_glow_strength + heartbeat_strength * 0.55, 0.10)
		t.tween_property(_env, "glow_strength", _base_glow_strength, 0.35).set_delay(0.10)

	if _has_prop("fog_density"):
		t.tween_property(_env, "fog_density", _base_fog_density + heartbeat_strength * 0.03, 0.10)
		t.tween_property(_env, "fog_density", _base_fog_density, 0.35).set_delay(0.10)

	# light pulse
	if _rig != null and is_instance_valid(_rig):
		var ml := _rig.get_node_or_null("MainLight") as OmniLight3D
		var sl := _rig.get_node_or_null("SpecLight") as OmniLight3D
		if ml != null:
			t.tween_property(ml, "light_energy", _base_main_light_energy + heartbeat_strength * 0.28, 0.10)
			t.tween_property(ml, "light_energy", _base_main_light_energy, 0.35).set_delay(0.10)
		if sl != null:
			t.tween_property(sl, "light_energy", _base_spec_light_energy + heartbeat_strength * 0.18, 0.10)
			t.tween_property(sl, "light_energy", _base_spec_light_energy, 0.35).set_delay(0.10)

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

	var cams: Array = get_tree().get_nodes_in_group("player_camera")
	for any in cams:
		var c2 := any as Camera3D
		if c2 != null:
			return c2

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

func _build_rig_nodes(rig: Node) -> void:
	_tex_spore = _make_radial_tex(64, 0.55, 0.95, false)
	_tex_droplet = _make_radial_tex(96, 0.28, 0.98, true)

	if lights_enabled:
		var main := OmniLight3D.new()
		main.name = "MainLight"
		main.light_color = main_light_color
		main.light_energy = main_light_energy
		main.omni_range = main_light_range
		main.shadow_enabled = false
		rig.add_child(main)

		var spec := OmniLight3D.new()
		spec.name = "SpecLight"
		spec.light_color = spec_light_color
		spec.light_energy = spec_light_energy
		spec.omni_range = spec_light_range
		spec.shadow_enabled = false
		spec.position = Vector3(0.12, -0.08, 0.10)
		rig.add_child(spec)

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

	var ml := _rig.get_node_or_null("MainLight") as OmniLight3D
	if ml != null:
		ml.light_color = main_light_color
		ml.omni_range = main_light_range
		ml.light_energy = main_light_energy
		_base_main_light_energy = main_light_energy

	var sl := _rig.get_node_or_null("SpecLight") as OmniLight3D
	if sl != null:
		sl.light_color = spec_light_color
		sl.omni_range = spec_light_range
		sl.light_energy = spec_light_energy
		_base_spec_light_energy = spec_light_energy

	# tiny flicker that makes things feel “alive”
	if light_flicker_enabled and (ml != null or sl != null):
		var t := float(Time.get_ticks_msec()) * 0.001
		var f := 1.0 + sin(t * light_flicker_speed) * light_flicker_amount * 0.6 + sin(t * light_flicker_speed * 2.3) * light_flicker_amount * 0.4
		if ml != null:
			ml.light_energy = _base_main_light_energy * f
		if sl != null:
			sl.light_energy = _base_spec_light_energy * (0.92 + 0.08 * f)

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

			sm.set_shader_parameter("wet_film_strength", wet_film_strength)
			sm.set_shader_parameter("wet_film_speed", wet_film_speed)
			sm.set_shader_parameter("wet_film_scale", wet_film_scale)

			sm.set_shader_parameter("drip_strength", drip_strength)
			sm.set_shader_parameter("drip_speed", drip_speed)
			sm.set_shader_parameter("drip_scale", drip_scale)

# ------------------------------------------------------------
# PARTICLES (procedural blob textures)
# ------------------------------------------------------------
func _make_billboard_quad_mesh(tex: Texture2D) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, 1)

	q.material = mat
	return q

func _make_spores_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = max(1, spores_amount)
	p.lifetime = maxf(0.1, spores_lifetime)
	p.one_shot = false
	p.emitting = true
	p.draw_pass_1 = _make_billboard_quad_mesh(_tex_spore)

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = spores_spawn_box * 0.5
	m.direction = Vector3(0, 0, -1)
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = spores_velocity
	m.orbit_velocity_min = -0.10
	m.orbit_velocity_max = 0.10
	m.angular_velocity_min = -0.40
	m.angular_velocity_max = 0.40
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
	p.draw_pass_1 = _make_billboard_quad_mesh(_tex_droplet)

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = droplets_spawn_box * 0.5
	m.direction = Vector3(0, -1, -0.06).normalized()
	m.initial_velocity_min = droplets_fall_speed * 0.70
	m.initial_velocity_max = droplets_fall_speed
	m.tangential_accel_min = -0.08
	m.tangential_accel_max = 0.08
	m.radial_accel_min = -0.05
	m.radial_accel_max = 0.05
	m.gravity = Vector3.ZERO
	m.scale_min = droplets_scale_min
	m.scale_max = droplets_scale_max
	m.color = Color(droplets_color.r, droplets_color.g, droplets_color.b, droplets_alpha)
	p.process_material = m
	return p

func _make_radial_tex(size: int, core: float, edge: float, add_highlight: bool) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)

	var s := float(size)
	var center := Vector2((s - 1.0) * 0.5, (s - 1.0) * 0.5)

	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x), float(y))
			var d := p.distance_to(center) / (s * 0.5)
			var a := 1.0 - smoothstep(core, edge, d)

			# soften corners hard
			a = pow(maxf(0.0, a), 1.6)

			var r := 1.0
			var g := 1.0
			var b := 1.0

			if add_highlight:
				# small spec highlight in upper-left
				var hpos := center + Vector2(-s * 0.18, -s * 0.18)
				var hd := p.distance_to(hpos) / (s * 0.22)
				var h := maxf(0.0, 1.0 - smoothstep(0.0, 1.0, hd))
				h = pow(h, 2.2)
				r = 1.0 + h * 0.25
				g = 1.0 + h * 0.20
				b = 1.0 + h * 0.20

			img.set_pixel(x, y, Color(r, g, b, a))

	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------
# POST SHADER (wet film + drip streaks)
# ------------------------------------------------------------
func _post_shader_code() -> String:
	return """
shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.62;
uniform float wobble_strength : hint_range(0.0, 0.05) = 0.009;
uniform float wobble_speed : hint_range(0.0, 3.0) = 0.55;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.58;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.05;
uniform float chroma_edge : hint_range(0.0, 0.02) = 0.0010;

uniform vec4 tint_color : source_color = vec4(0.85, 0.22, 0.24, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.09;

uniform float wet_film_strength : hint_range(0.0, 1.0) = 0.42;
uniform float wet_film_speed : hint_range(0.0, 3.0) = 0.55;
uniform float wet_film_scale : hint_range(0.2, 6.0) = 1.8;

uniform float drip_strength : hint_range(0.0, 1.0) = 0.28;
uniform float drip_speed : hint_range(0.0, 2.0) = 0.25;
uniform float drip_scale : hint_range(0.2, 6.0) = 1.2;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;

	// subtle wobble
	float tw = t * wobble_speed;
	float w1 = sin((uv.y * 8.0 + tw * 1.3)) * cos((uv.x * 6.0 - tw * 1.0));
	float w2 = sin((uv.x * 10.0 - tw * 1.5)) * 0.35;
	vec2 offs = vec2(w1 + w2, -w1) * (wobble_strength * intensity);

	// slight chroma at edges
	vec2 p = uv - 0.5;
	float r2 = dot(p, p);
	float edge = smoothstep(0.12, 0.46, r2) * chroma_edge * intensity;

	vec4 cR = texture(screen_tex, uv + offs + vec2(edge, 0.0));
	vec4 cG = texture(screen_tex, uv + offs);
	vec4 cB = texture(screen_tex, uv + offs - vec2(edge, 0.0));
	vec4 col = vec4(cR.r, cG.g, cB.b, 1.0);

	// tint
	col.rgb = mix(col.rgb, col.rgb * tint_color.rgb, tint_strength * intensity);

	// wet film: moving spec + micro ripples, stronger at edges
	float n1 = noise(uv * vec2(14.0, 9.0) * wet_film_scale + vec2(t * wet_film_speed, -t * wet_film_speed * 0.7));
	float n2 = noise(uv * vec2(26.0, 18.0) * wet_film_scale + vec2(-t * wet_film_speed * 1.2, t * wet_film_speed));
	float film = pow(clamp(n1 * 0.65 + n2 * 0.35, 0.0, 1.0), 2.2);

	float edge_mask = smoothstep(0.08, 0.60, r2);
	float film_amt = wet_film_strength * intensity * (0.25 + 0.75 * edge_mask);

	// colored “wet shine”
	col.rgb += film * film_amt * vec3(0.22, 0.07, 0.06);

	// drips: thin vertical streaks that crawl downward
	vec2 duv = uv * vec2(9.0 * drip_scale, 1.0);
	duv.y += t * drip_speed * 0.25;

	float streak_noise = noise(duv);
	float streaks = smoothstep(0.72, 0.92, streak_noise); // thin lines
	float drip_fade = smoothstep(0.0, 0.30, uv.y) * (1.0 - smoothstep(0.70, 1.0, uv.y));
	col.rgb += streaks * drip_strength * intensity * drip_fade * vec3(0.14, 0.04, 0.04);

	// vignette (enclosed)
	float vig = smoothstep(0.10, 0.78, r2);
	col.rgb *= 1.0 - (vig * vignette_strength * intensity);

	// grain (low)
	float g = hash(uv * vec2(1500.0, 900.0) + vec2(t * 31.0, t * 17.0)) - 0.5;
	col.rgb += g * (grain_strength * intensity);

	COLOR = col;
}
"""
