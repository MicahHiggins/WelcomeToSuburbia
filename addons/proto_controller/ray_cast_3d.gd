extends RayCast3D
#
# Network-aware interaction ray:
# - Only handles PICKUP on "interact" (F)
# - Drop is handled by Player input action "drop" (G)
# - Sends scene-relative NodePaths for multiplayer safety
#

@export var interact_action := "interact"
@export var max_distance := 4.0

var hovered_item: Node = null

@onready var player := get_parent().get_parent().get_parent() as Node

func _ready() -> void:
	enabled = true
	target_position = Vector3(0, 0, -max_distance)

	if player == null:
		push_error("RayCast3D: Could not find player node by climbing parents.")
	else:
		print("RayCast3D: Player found -> ", player.name)

func _process(_delta: float) -> void:
	if player == null:
		return

	# Only the local authority should drive hover/interaction.
	if "is_multiplayer_authority" in player and not player.is_multiplayer_authority():
		return

	if not is_colliding():
		_set_hovered(null)
		return

	var hit := get_collider()
	if hit == null:
		_set_hovered(null)
		return

	var pickup := _find_pickup_root(hit)
	_set_hovered(pickup)

func _input(event: InputEvent) -> void:
	if player == null:
		return

	if "is_multiplayer_authority" in player and not player.is_multiplayer_authority():
		return

	if event.is_action_pressed(interact_action):
		_try_pickup()

# ================== HELPERS ==================

func _set_hovered(new_item: Node) -> void:
	if new_item == hovered_item:
		return

	if hovered_item != null and "set_hovered" in hovered_item:
		hovered_item.call_deferred("set_hovered", false)

	hovered_item = new_item

	if hovered_item != null and "set_hovered" in hovered_item:
		hovered_item.call_deferred("set_hovered", true)

func _find_pickup_root(hit_obj: Object) -> Node:
	var n := hit_obj as Node
	while n != null:
		if n.is_in_group("pickup"):
			return n
		n = n.get_parent()
	return null

func _try_pickup() -> void:
	if hovered_item == null or not is_instance_valid(hovered_item):
		return

	if not player.has_method("request_pickup_rpc"):
		push_error("RayCast3D: player has no request_pickup_rpc()")
		return

	# Send NodePath relative to current scene root (ex: "Items/BatClean")
	var scene_root := get_tree().current_scene
	var item_path: NodePath

	if scene_root != null and scene_root.is_ancestor_of(hovered_item):
		item_path = scene_root.get_path_to(hovered_item)
	else:
		item_path = hovered_item.get_path() # fallback

	player.request_pickup_rpc(item_path)
