extends Node3D

@onready var label_3d: Label3D = $Label3D

@export var default_text: String = "Welcome to Suburbia!"

var unique_iterations := {
	4: "Something feels different.",
	8: "You have been here before.",
	12: "Why are you still here?"
}

var player: Node3D = null
var last_iteration: int = -999
var fixed_position: Vector3


func _ready() -> void:
	fixed_position = global_position
	find_player()
	update_text()


func _process(_delta: float) -> void:
	# Force billboard to stay in its original spot
	global_position = fixed_position

	if player == null or not is_instance_valid(player):
		find_player()

	var iteration: int = GlobalVariables.iterations

	if iteration != last_iteration:
		update_text()
		last_iteration = iteration

	if iteration in unique_iterations and player != null:
		face_player_y_only()


func find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D


func update_text() -> void:
	if label_3d == null:
		return

	var iteration: int = GlobalVariables.iterations

	if iteration in unique_iterations:
		label_3d.text = unique_iterations[iteration]
	else:
		label_3d.text = default_text


func face_player_y_only() -> void:
	var to_player = player.global_position - global_position
	to_player.y = 0.0

	if to_player.length_squared() <= 0.0001:
		return

	rotation.y = atan2(to_player.x, to_player.z)
