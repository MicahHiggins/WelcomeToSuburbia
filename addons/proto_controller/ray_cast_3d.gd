extends RayCast3D
#
# Interaction ray:
# - If hit object is in group "pickup" -> request_pickup_rpc(nodepath)
# - If hit object is in group "interactable" -> call interact(from_player)
# - Hover outline uses set_hovered(true/false) if present
#

@export var interact_action := "interact"
@export var max_distance := 4.0
@export var interact_collision_layer: int = 4  # your Area3D layer

var hovered_target: Node = null

@onready var player := get_parent().get_parent().get_parent() as Node

func _ready() -> void:
	enabled = true
	target_position = Vector3(0, 0, -max_distance)

	# Make sure our RayCast collision mask includes the interact layer (4)
	if interact_collision_layer >= 1 and interact_collision_layer <= 32:
		set_collision_mask_value(interact_collision_layer, true)

	if player == null:
		push_error("RayCast3D: Could not find player node by climbing parents.")
	else:
		print("RayCast3D: Player found -> ", player.name)

func _process(_delta: float) -> void:
	if player == null:
		return

	# Only local authority should drive interactions
	if "is_multiplayer_authority" in player and not player.is_multiplayer_authority():
		return

	if not is_colliding():
		_set_hovered(null)
		return

	var hit_obj: Object = get_collider()
	if hit_obj == null:
		_set_hovered(null)
		return

	var target: Node = _find_interaction_root(hit_obj)
	_set_hovered(target)

func _input(event: InputEvent) -> void:
	if player == null:
		return

	if "is_multiplayer_authority" in player and not player.is_multiplayer_authority():
		return

	if event.is_action_pressed(interact_action):
		_try_interact()

# -------------------------
# Hover + target resolving
# -------------------------
func _set_hovered(new_target: Node) -> void:
	if new_target == hovered_target:
		return

	if hovered_target != null and hovered_target.has_method("set_hovered"):
		hovered_target.call_deferred("set_hovered", false)

	hovered_target = new_target

	if hovered_target != null and hovered_target.has_method("set_hovered"):
		hovered_target.call_deferred("set_hovered", true)

func _find_interaction_root(hit_obj: Object) -> Node:
	var n := hit_obj as Node
	while n != null:
		if n.is_in_group("pickup") or n.is_in_group("interactable"):
			return n
		n = n.get_parent()
	return null

# -------------------------
# Interact on F
# -------------------------
func _try_interact() -> void:
	if hovered_target == null or not is_instance_valid(hovered_target):
		return

	# PICKUP behavior (unchanged from your original)
	if hovered_target.is_in_group("pickup"):
		if not player.has_method("request_pickup_rpc"):
			push_error("RayCast3D: player has no request_pickup_rpc()")
			return

		var scene_root := get_tree().current_scene
		var item_path: NodePath

		if scene_root != null and scene_root.is_ancestor_of(hovered_target):
			item_path = scene_root.get_path_to(hovered_target)
		else:
			item_path = hovered_target.get_path()

		player.request_pickup_rpc(item_path)
		return

	# INTERACTABLE behavior (door, lever, etc.)
	if hovered_target.is_in_group("interactable"):
		if hovered_target.has_method("interact"):
			hovered_target.call_deferred("interact", player)
		else:
			push_error("RayCast3D: interactable has no interact(from_player) method.")
