extends Node3D
class_name Level1Controller

@export var fog_anim_path: NodePath = NodePath("WorldEnvironment/AnimationPlayer")
@export var fog_anim_name: StringName = &"fog_cycle"

func _ready() -> void:
	var anim := get_node_or_null(fog_anim_path) as AnimationPlayer
	if anim != null and anim.has_animation(String(fog_anim_name)):
		anim.play(String(fog_anim_name))
