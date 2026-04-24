extends Node3D
class_name Level1Controller

@export var fog_anim_path: NodePath = NodePath("WorldEnvironment/AnimationPlayer")
@export var fog_anim_name: StringName = &"fog_cycle"

@export var tentacle_scene: PackedScene = preload("res://Assets/RandomObjects/tentacle/tentacle_v_2.tscn")

@export var start_iteration: int = 3
@export var spawn_radius: float = 35.0
@export var radius_randomness: float = 8.0
@export var max_alive_tentacles: int = 20

@export var slow_spawn_interval: float = 7.0
@export var fast_spawn_interval: float = 0.5
@export var max_iteration_for_full_speed: int = 6.0

@export var spawn_height_offset: float = 0.0

@export var play_intro_cutscene: bool = true
@export var intro_video_path: NodePath = NodePath("IntroLayer/IntroVideo")
@export var intro_black_rect_path: NodePath = NodePath("IntroLayer/Black")
@export var intro_fallback_duration_sec: float = 0.0
@export var fade_out_black_after_intro: bool = true
@export var fade_out_duration_sec: float = 0.6
@export var use_global_input_lock: bool = true

var spawn_timer: float = 0.0
var _intro_done: bool = false

func _ready() -> void:
	_play_fog_anim()
	randomize()

	if play_intro_cutscene:
		await _play_intro_blocking()

	_intro_done = true

func _process(delta: float) -> void:
	if not _intro_done:
		return

	if GlobalVariables.iterations < start_iteration:
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_try_spawn_tentacle()
		spawn_timer = _get_spawn_interval()

func _play_intro_blocking() -> void:
	var v := get_node_or_null(intro_video_path) as VideoStreamPlayer
	var black := get_node_or_null(intro_black_rect_path) as ColorRect
	if v == null or black == null:
		return

	_lock_input(true)

	# black should NOT cover during the video
	black.visible = false
	var c0 := black.color
	c0.a = 0.0
	black.color = c0

	v.visible = true
	v.paused = false
	v.play()

	if intro_fallback_duration_sec > 0.0:
		await get_tree().create_timer(intro_fallback_duration_sec).timeout
	else:
		if v.has_signal("finished"):
			await v.finished
		else:
			await get_tree().create_timer(18.0).timeout

	v.stop()
	v.paused = true
	v.visible = false

	if fade_out_black_after_intro:
		black.visible = true
		var c1 := black.color
		c1.a = 1.0
		black.color = c1
		await _fade_black_out(black, fade_out_duration_sec)
	else:
		black.visible = false
		var c2 := black.color
		c2.a = 0.0
		black.color = c2

	_lock_input(false)

func _fade_black_out(black: ColorRect, dur: float) -> void:
	if dur <= 0.0:
		black.visible = false
		var c0 := black.color
		c0.a = 0.0
		black.color = c0
		return

	var steps := 30
	for i in range(steps):
		var t := float(i + 1) / float(steps)
		var c := black.color
		c.a = 1.0 - t
		black.color = c
		await get_tree().create_timer(dur / float(steps)).timeout

	black.visible = false
	var c2 := black.color
	c2.a = 0.0
	black.color = c2

func _lock_input(lock_it: bool) -> void:
	if not use_global_input_lock:
		return
	if GlobalVariables.has_signal("gameplay_lock_changed"):
		GlobalVariables.emit_signal("gameplay_lock_changed", lock_it)

func _play_fog_anim() -> void:
	var anim := get_node_or_null(fog_anim_path) as AnimationPlayer
	if anim != null and anim.has_animation(String(fog_anim_name)):
		anim.play(String(fog_anim_name))

func _get_spawn_interval() -> float:
	var t := inverse_lerp(
		float(start_iteration),
		float(max_iteration_for_full_speed),
		float(GlobalVariables.iterations)
	)
	t = clamp(t, 0.0, 1.0)
	return lerp(slow_spawn_interval, fast_spawn_interval, t)

func _try_spawn_tentacle() -> void:
	if tentacle_scene == null:
		return

	var alive_count := get_tree().get_nodes_in_group("tentacles_alive").size()
	if alive_count >= max_alive_tentacles:
		return

	var player := _get_player()
	if player == null:
		return

	var tentacle := tentacle_scene.instantiate() as Node3D
	if tentacle == null:
		return

	var scale_mult := randf_range(0.7, 2.7)
	tentacle.scale = Vector3.ONE * scale_mult

	var angle := randf() * TAU
	var dist := spawn_radius + randf_range(-radius_randomness, radius_randomness)

	var offset := Vector3(cos(angle), 0.0, sin(angle)) * dist
	var spawn_pos := player.global_position + offset
	spawn_pos.y += spawn_height_offset

	add_child(tentacle)
	tentacle.global_position = spawn_pos

func _get_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
