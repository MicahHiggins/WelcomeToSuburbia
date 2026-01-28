extends Node
# ------------------------------------------------------------
# ItemManager (SERVER authoritative)
# - Owns authoritative "who is holding what" state
# - Broadcasts pickup/drop reparenting to ALL peers
# - Uses a STABLE per-item key ("item_key") so drop works after reparenting
# - Drop physics tuning: slower fall via damping + optional fall speed cap
# ------------------------------------------------------------

const SERVER_ID: int = 1
@export var max_inventory_slots: int = 2

# Drop tuning (RigidBody3D only)
@export var drop_forward_distance: float = 1.2
@export var drop_up_offset: float = 0.7
@export var drop_impulse_strength: float = 1.0          # keep small for gentle drops
@export var drop_downward_impulse: float = 0.0          # set >0 if you want it to "start falling" instantly
@export var drop_clear_velocity: bool = true

# "Slow fall" tuning (RigidBody3D only)
@export var drop_linear_damp: float = 6.0               # higher = slower fall (try 3..12)
@export var drop_angular_damp: float = 8.0              # reduces spin on drop
@export var cap_fall_speed: bool = true
@export var max_downward_speed: float = 3.0             # units/sec downward (try 2..6)

# When held, we restore these (so we don't permanently change the bat)
@export var held_linear_damp: float = 0.0
@export var held_angular_damp: float = 0.0

# Keyed by STABLE scene-relative key (ex: "Items/BatClean")
var _held_by: Dictionary = {}           # NodePath -> int (peer_id), -1 = free
var _original_parent: Dictionary = {}   # NodePath -> NodePath (scene-relative parent path)

# =========================
#      PATH HELPERS
# =========================
func _scene_root() -> Node:
	return get_tree().current_scene

func _resolve_scene_path(path: NodePath) -> Node:
	var scene := _scene_root()
	if scene != null:
		var n := scene.get_node_or_null(path)
		if n != null:
			return n
	return get_tree().root.get_node_or_null(path)

func _to_scene_path(n: Node) -> NodePath:
	var scene := _scene_root()
	if scene == null or n == null:
		return NodePath("")
	return scene.get_path_to(n)

# =========================
#   STABLE ITEM LOOKUP
# =========================
func _resolve_item_anywhere(item_key: NodePath) -> Node:
	var n := _resolve_scene_path(item_key)
	if n != null:
		return n

	var key_str := String(item_key)
	for obj in get_tree().get_nodes_in_group("pickup"):
		if obj is Node:
			var node := obj as Node
			if node.has_meta("item_key") and String(node.get_meta("item_key")) == key_str:
				return node
	return null

func _stable_key_for_item(item: Node) -> NodePath:
	if item != null and item.has_meta("item_key"):
		var s := String(item.get_meta("item_key"))
		if s != "":
			return NodePath(s)
	return _to_scene_path(item)

# =========================
#      PLAYER LOOKUP
# =========================
func _player_for_peer(peer_id: int) -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	for n in players:
		if n is Node3D:
			var p := n as Node3D
			if p.get_multiplayer_authority() == peer_id:
				return p
	return null

# =========================
#   PHYSICS HELPERS
# =========================
func _freeze_for_hold(item: Node) -> void:
	if item is RigidBody3D:
		var rb := item as RigidBody3D
		# restore "normal" damping while held (so it's consistent)
		rb.linear_damp = held_linear_damp
		rb.angular_damp = held_angular_damp
		rb.freeze = true
		rb.sleeping = true

func _apply_slow_fall(rb: RigidBody3D) -> void:
	# Slow the fall mainly via damping
	rb.linear_damp = drop_linear_damp
	rb.angular_damp = drop_angular_damp

	# Optional: hard cap downward speed (very effective)
	if cap_fall_speed:
		var v := rb.linear_velocity
		if v.y < -max_downward_speed:
			v.y = -max_downward_speed
			rb.linear_velocity = v

func _unfreeze_for_drop(item: Node, impulse_dir: Vector3) -> void:
	if item is RigidBody3D:
		var rb := item as RigidBody3D
		rb.freeze = false
		rb.sleeping = false

		if drop_clear_velocity:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO

		# Apply slow-fall settings immediately
		_apply_slow_fall(rb)

		# Gentle impulse (optional)
		var impulse := impulse_dir * drop_impulse_strength + Vector3.DOWN * drop_downward_impulse
		if impulse.length() > 0.0001:
			rb.apply_central_impulse(impulse)

# =========================
#   SERVER: PICKUP REQUEST
# =========================
@rpc("any_peer", "reliable")
func request_pickup(item_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()

	var item := _resolve_scene_path(item_path)
	if item == null:
		return
	if not item.is_in_group("pickup"):
		return

	var item_key: NodePath = _stable_key_for_item(item)
	if String(item_key) == "":
		return

	if not _original_parent.has(item_key):
		var parent_path: NodePath = _to_scene_path(item.get_parent())
		_original_parent[item_key] = parent_path

	if _held_by.has(item_key) and int(_held_by[item_key]) != -1:
		return

	if item.has_meta("locked") and bool(item.get_meta("locked")):
		return
	item.set_meta("locked", true)

	var p := _player_for_peer(sender)
	if p == null:
		item.set_meta("locked", false)
		return

	if "inventory" in p:
		var inv_any: Array = p.inventory
		if inv_any.size() >= max_inventory_slots:
			if p.has_method("server_show_hint"):
				p.rpc_id(sender, "server_show_hint", "Inventory Full", 1.25)
			item.set_meta("locked", false)
			return

	_held_by[item_key] = sender

	var player_rel: NodePath = _to_scene_path(p)
	if String(player_rel) == "":
		_held_by[item_key] = -1
		item.set_meta("locked", false)
		return

	rpc("apply_pickup", item_key, player_rel, sender)

	if "inventory" in p and p.has_method("server_set_inventory"):
		var new_inv: Array[StringName] = (p.inventory as Array[StringName]).duplicate()
		new_inv.append(StringName(item.name))
		p.rpc_id(sender, "server_set_inventory", new_inv)

# =========================
#  ALL PEERS: APPLY PICKUP
# =========================
@rpc("any_peer", "call_local", "reliable")
func apply_pickup(item_key: NodePath, player_path: NodePath, new_owner_id: int) -> void:
	var item := _resolve_item_anywhere(item_key)
	var player := _resolve_scene_path(player_path)
	if item == null or player == null:
		return

	item.set_meta("item_key", String(item_key))

	_freeze_for_hold(item)

	item.set_multiplayer_authority(new_owner_id)

	var marker := player.get_node_or_null("Head/CarryObjectMarker")
	if marker != null and marker is Node3D:
		var m := marker as Node3D
		item.reparent(m)
		item.transform = Transform3D.IDENTITY
	else:
		item.reparent(player)

	if "set_held" in item:
		item.call_deferred("set_held", true)

# =========================
#    SERVER: DROP REQUEST
# =========================
@rpc("any_peer", "reliable")
func request_drop(item_key: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()

	var item := _resolve_item_anywhere(item_key) as Node3D
	if item == null:
		return

	if not _held_by.has(item_key):
		return
	if int(_held_by[item_key]) != sender:
		return

	var p := _player_for_peer(sender) as Node3D
	if p == null:
		return

	_held_by[item_key] = -1
	if item.has_meta("locked"):
		item.set_meta("locked", false)

	var forward: Vector3 = (-p.global_transform.basis.z).normalized()
	var drop_pos: Vector3 = p.global_position + forward * drop_forward_distance + Vector3.UP * drop_up_offset
	var drop_xform: Transform3D = Transform3D(item.global_transform.basis, drop_pos)

	# Broadcast: include forward so clients match the same impulse direction
	rpc("apply_drop", item_key, drop_xform, forward)

	if "inventory" in p and p.has_method("server_set_inventory"):
		var id_to_remove: StringName = StringName(item.name)
		var new_inv: Array[StringName] = (p.inventory as Array[StringName]).duplicate()
		var idx := new_inv.find(id_to_remove)
		if idx != -1:
			new_inv.remove_at(idx)
		p.rpc_id(sender, "server_set_inventory", new_inv)

# =========================
#  ALL PEERS: APPLY DROP
# =========================
@rpc("any_peer", "call_local", "reliable")
func apply_drop(item_key: NodePath, world_xform: Transform3D, impulse_forward: Vector3) -> void:
	var item := _resolve_item_anywhere(item_key) as Node3D
	if item == null:
		return

	item.set_meta("item_key", String(item_key))

	var scene := _scene_root()
	var parent_node: Node = null

	if _original_parent.has(item_key):
		var parent_path: NodePath = _original_parent[item_key]
		parent_node = _resolve_scene_path(parent_path)

	if parent_node == null:
		parent_node = scene if scene != null else get_tree().root

	item.reparent(parent_node)
	item.global_transform = world_xform

	_unfreeze_for_drop(item, impulse_forward)

	# Extra safety: cap fall speed one more time right after unfreeze
	if item is RigidBody3D:
		_apply_slow_fall(item as RigidBody3D)

	if "set_held" in item:
		item.call_deferred("set_held", false)

# =========================
#   OPTIONAL: DEBUG HELP
# =========================
func debug_print_state() -> void:
	print("Held map:")
	for k in _held_by.keys():
		print(" - ", String(k), " => ", int(_held_by[k]))
