extends RayCast3D
#
# Network-aware interaction ray:
# - Scene path: Player -> Head -> Camera3D -> RayCast3D
# - Handles:
#     * Hover detection (for outlines)
#     * Interact input (e.g. E)
# - Delegates pickup/drop requests to the Player script
# - Works with any MultiplayerPeer backend (ENet, SteamMultiplayerPeer, etc.)
#

# Input action name used for interaction (e.g. "interact" mapped to E)
@export var interact_action := "interact"

# How far the ray reaches forward from the camera
@export var max_distance := 4.0

# The currently hovered pickup (in group "pickup"), or null if nothing is targeted
var hovered_item: Node = null

# Assumes this RayCast3D is at: Player -> Head -> Camera3D -> RayCast3D
# parent             = Camera3D
# parent.parent      = Head
# parent.parent.parent = Player
@onready var player := get_parent().get_parent().get_parent() as Node


func _ready() -> void:
	# Enable the ray and make it point straight forward from the camera.
	# In Godot, -Z is the local "forward" direction.
	enabled = true
	target_position = Vector3(0, 0, -max_distance)

	if player == null:
		push_error("RayCast3D: Could not find player node by climbing parents.")
	else:
		print("RayCast3D: Player found -> ", player.name)


func _process(_delta: float) -> void:
	# If there is no valid player reference, do nothing.
	if player == null:
		return

	# In multiplayer, only the local authority should drive hover/interaction.
	if "is_multiplayer_authority" in player and not player.is_multiplayer_authority():
		return

	# If the ray hits nothing, clear hovered state.
	if not is_colliding():
		_set_hovered(null)
		return

	# The collider can be a mesh, area, rigid body, etc.
	var hit := get_collider()
	if hit == null:
		_set_hovered(null)
		return

	# Walk up the node tree until a node in group "pickup" is found.
	# This lets us hit child meshes/areas while the root node is the pickup.
	var pickup := _find_pickup_root(hit)

	# Update hovered item and outline state.
	_set_hovered(pickup)


func _input(event: InputEvent) -> void:
	# If there is no player, do nothing.
	if player == null:
		return

	# Only the local authority should fire interaction input.
	if "is_multiplayer_authority" in player and not player.is_multiplayer_authority():
		return

	# When the interact key (e.g. E) is pressed, attempt pickup or drop.
	if event.is_action_pressed(interact_action):
		_try_pickup()


# ================== HELPERS ==================

# Set which item is currently hovered, and toggle outline state via set_hovered().
func _set_hovered(new_item: Node) -> void:
	# No change → nothing to do.
	if new_item == hovered_item:
		return

	# Clear previous hovered item's outline (if it supports set_hovered()).
	if hovered_item != null and "set_hovered" in hovered_item:
		hovered_item.call_deferred("set_hovered", false)

	# Update the reference.
	hovered_item = new_item

	# Enable new hovered item's outline (if it supports set_hovered()).
	if hovered_item != null and "set_hovered" in hovered_item:
		hovered_item.call_deferred("set_hovered", true)


# Walk up from the hit collider's node until a node in group "pickup" is found.
# This allows the ray to hit a child mesh/area while the parent node is the
# one that actually represents the pickup item.
func _find_pickup_root(hit_obj: Object) -> Node:
	var n := hit_obj as Node
	while n != null:
		if n.is_in_group("pickup"):
			return n
		n = n.get_parent()
	return null


# Handles both pickup and drop behavior when interact is pressed.
func _try_pickup() -> void:
	# Require a valid hovered item.
	if hovered_item == null or not is_instance_valid(hovered_item):
		return

	# Require a valid player reference.
	if player == null or not is_instance_valid(player):
		push_error("RayCast3D: no valid player in _try_pickup()")
		return

	# If the player already holds something, treat interact as a DROP request.
	if "picked_object" in player and player.picked_object != null:
		if player.has_method("request_drop_rpc"):
			player.request_drop_rpc()
		return

	# Normal pickup path: ask the Player script to send a request to the server.
	if not player.has_method("request_pickup_rpc"):
		push_error("RayCast3D: player has no request_pickup_rpc()")
		return

	# Pass the NodePath so the server can find the same item in its scene tree.
	var item_path: NodePath = hovered_item.get_path()
	player.request_pickup_rpc(item_path)
