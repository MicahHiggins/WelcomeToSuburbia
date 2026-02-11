extends Node3D

@export var target_scene_path: String = "res://GameLevelsETC/CellarLevel.tscn"

@onready var interact_area: Area3D = $Area3D

func _ready() -> void:
	add_to_group("interactable")

	# Make sure the raycast can hit this Area (layer 4)
	if interact_area != null:
		interact_area.set_collision_layer_value(4, true)
		interact_area.collision_mask = 0

func interact(from_player: Node = null) -> void:
	# SOLO TEST: if no multiplayer peer, just change immediately
	if not multiplayer.has_multiplayer_peer():
		get_tree().change_scene_to_file(target_scene_path)
		return

	# Multiplayer: use autoload vote system
	NetSceneManager.request_group_scene_change(target_scene_path)
