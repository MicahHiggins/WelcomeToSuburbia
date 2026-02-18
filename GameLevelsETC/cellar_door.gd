extends Node3D

@export var teleport_manager_path: NodePath = NodePath("../TeleportManager")
@onready var interact_area: Area3D = $Area3D

func _ready() -> void:
	add_to_group("interactable")

	if interact_area != null:
		interact_area.set_collision_layer_value(4, true)
		interact_area.collision_mask = 0

func interact(from_player: Node = null) -> void:
	var tm := get_node_or_null(teleport_manager_path)
	if tm == null:
		push_error("[CellarDoor] TeleportManager not found at teleport_manager_path.")
		return

	# Option A: pass player (or null)
	if tm.has_method("request_enter_cellar"):
		tm.call("request_enter_cellar", from_player)
