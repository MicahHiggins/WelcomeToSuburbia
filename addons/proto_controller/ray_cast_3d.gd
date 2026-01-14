extends RayCast3D

@export var interact_action := "interact"
@export var max_distance := 4.0

var hovered_item: Node = null

# We assume this RayCast3D is at: Player -> Head -> Camera3D -> RayCast3D
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

	# Only local authority controls hover
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

# -------------- helpers ----------------

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
	if player == null or not is_instance_valid(player):
		push_error("RayCast3D: no valid player in _try_pickup()")
		return

	# If the player script is already tracking a held object, we can ask to DROP instead
	if "picked_object" in player and player.picked_object != null:
		if player.has_method("request_drop_rpc"):
			player.request_drop_rpc()
		return

	# Normal pickup path: ask the player to talk to the server
	if not player.has_method("request_pickup_rpc"):
		push_error("RayCast3D: player has no request_pickup_rpc()")
		return

	var item_path: NodePath = hovered_item.get_path()
	player.request_pickup_rpc(item_path)
