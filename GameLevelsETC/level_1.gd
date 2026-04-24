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

var spawn_timer: float = 0.0

func _ready() -> void:
	var anim := get_node_or_null(fog_anim_path) as AnimationPlayer
	if anim != null and anim.has_animation(String(fog_anim_name)):
		anim.play(String(fog_anim_name))
	randomize()

func _process(delta: float) -> void:
	if GlobalVariables.iterations < start_iteration:
		return
	
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_try_spawn_tentacle()
		spawn_timer = _get_spawn_interval()

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
