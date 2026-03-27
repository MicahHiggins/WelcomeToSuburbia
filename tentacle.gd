extends Node3D

@onready var skeleton: Skeleton3D = $Armature/Skeleton3D

@export var speed: float = 1.6
@export var main_amplitude: float = 22.0
@export var secondary_amplitude: float = 10.0
@export var twist_amplitude: float = 14.0
@export var bone_delay: float = 0.45
@export var tip_extra_curl: float = 1.4
@export var twitch_strength: float = 18.0
@export var twitch_speed: float = 14.0

var t: float = 0.0
var twitch_timer: float = 0.0
var twitch_active: bool = false
var twitch_phase: float = 0.0

func _ready() -> void:
	randomize()
	twitch_timer = randf_range(1.5, 4.0)

func _process(delta: float) -> void:
	t += delta * speed

	if !twitch_active:
		twitch_timer -= delta
		if twitch_timer <= 0.0:
			twitch_active = true
			twitch_phase = 0.0
			twitch_timer = randf_range(1.5, 4.0)
	else:
		twitch_phase += delta * twitch_speed
		if twitch_phase >= PI:
			twitch_active = false

	var bone_count: int = skeleton.get_bone_count()

	for i in range(bone_count):
		var bone_factor: float = float(i) / max(float(bone_count - 1), 1.0)
		var tip_factor: float = lerp(1.0, tip_extra_curl, bone_factor)

		var bend_a: float = sin(t + i * bone_delay) * main_amplitude * tip_factor
		var bend_b: float = sin(t * 0.63 + i * bone_delay * 1.7 + 1.3) * secondary_amplitude * tip_factor
		var twist: float = sin(t * 1.15 + i * 0.35 + 2.2) * twist_amplitude * (0.35 + bone_factor * 0.65)

		var twitch: float = 0.0
		if twitch_active:
			twitch = sin(twitch_phase) * twitch_strength * bone_factor

		var x_rot: float = deg_to_rad((bend_a + bend_b + twitch) * 0.85)
		var z_rot: float = deg_to_rad((bend_a * 0.45 - bend_b * 0.7 + twitch * 0.35))
		var y_rot: float = deg_to_rad(twist)

		var qx: Quaternion = Quaternion(Vector3.RIGHT, x_rot)
		var qy: Quaternion = Quaternion(Vector3.UP, y_rot)
		var qz: Quaternion = Quaternion(Vector3.FORWARD, z_rot)

		skeleton.set_bone_pose_rotation(i, qy * qx * qz)
