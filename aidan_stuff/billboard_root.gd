extends Node3D

@onready var rotator: Node3D = $Rotator
@onready var sprite_3d: Sprite3D = $Rotator/Sprite3D
@onready var sprite_3d2: Sprite3D = $Rotator/Sprite3D2

@export var default_texture: Texture2D = preload("res://Assets/Images/suburbia_title_card.png")
@export var default_sprite_scale: Vector3 = Vector3(0.27, 0.27, 0.27)

var unique_iteration_images := {
	2: {
		"texture": preload("res://Assets/Images/BB_are_you_lost.webp"),
		"scale": Vector3(0.4, 0.4, 0.4)
	},
	4: {
		"texture": preload("res://Assets/Images/BB_where_are_you_going.webp"),
		"scale": Vector3(0.27, 0.27, 0.27)
	},
	6: {
		"texture": preload("res://Assets/Images/BB_youll_never_get_home.webp"),
		"scale": Vector3(0.27, 0.27, 0.27)
	}
}

var player: Node3D = null
var last_iteration: int = -1

func _ready() -> void:
	find_player()
	update_image()

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		find_player()

	var iteration: int = GlobalVariables.iterations

	if iteration != last_iteration:
		update_image()
		last_iteration = iteration

	if iteration in unique_iteration_images and player != null:
		face_player_y_only()

func find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D

func update_image() -> void:
	if sprite_3d == null or sprite_3d2 == null:
		return

	var iteration: int = GlobalVariables.iterations
	var texture_to_use: Texture2D = default_texture
	var scale_to_use: Vector3 = default_sprite_scale

	if iteration in unique_iteration_images:
		texture_to_use = unique_iteration_images[iteration]["texture"]
		scale_to_use = unique_iteration_images[iteration]["scale"]

	sprite_3d.texture = texture_to_use
	sprite_3d2.texture = texture_to_use

	sprite_3d.scale = scale_to_use
	sprite_3d2.scale = scale_to_use

func face_player_y_only() -> void:
	var to_player: Vector3 = player.global_position - rotator.global_position
	to_player.y = 0.0

	if to_player.length_squared() < 0.0001:
		return

	rotator.rotation.y = atan2(to_player.x, to_player.z) + PI - deg_to_rad(45)
