extends Node
# ------------------------------------------------------------
# ItemManager (SERVER authoritative)
# - Owns authoritative "who is holding what" state
# - Broadcasts pickup/drop reparenting to ALL peers
# - Uses a STABLE per-item key ("item_key") so drop works after reparenting
# - Forces physics/collision state so dropped items don't stay frozen / un-pickupable
# - NEW: Late-join sync so joining players get correct dropped/held state
# - NEW: Server-authoritative Use/Attack that plays item animation ("swing") for ALL peers
# ------------------------------------------------------------

const SERVER_ID: int = 1
@export var max_inventory_slots: int = 2

# Drop tuning
@export var drop_forward_distance: float = 1.2
@export var drop_up_offset: float = 0.7
@export var drop_impulse_strength: float = 1.0
@export var drop_downward_impulse: float = 0.0
@export var drop_clear_velocity: bool = true

# "Slow fall" tuning (RigidBody3D only)
@export var drop_linear_damp: float = 6.0
@export var drop_angular_damp: float = 8.0
@export var cap_fall_speed: bool = true
@export var max_downward_speed: float = 3.0

# Held physics (RigidBody3D only)
@export var held_linear_damp: float = 0.0
@export var held_angular_damp: float = 0.0
@export var held_gravity_scale: float = 0.0
@export var drop_gravity_scale: float = 1.0

# Attack / Use tuning
@export var attack_animation_name: StringName = &"swing"   # name of animation on the item
@export var attack_restart_if_playing: bool = true         # restart the swing if spammed

# Keyed by STABLE scene-relative key (ex: "Items/BatClean")
var _held_by: Dictionary = {}           # NodePath -> int (peer_id), -1 = free
var _original_parent: Dictionary = {}   # NodePath -> NodePath (scene-relative parent path)

# NEW: last known world transform for late-join reconstruction
var _last_world_xform: Dictionary = {}  # NodePath -> Transform3D

# =========================
#      READY / LATE JOIN
# =========================
func _ready() -> void:
	# Ensure every peer stamps item_key + caches original parent so stable lookup works everywhere.
	_register_scene_items()

	# Server: push full state snapshot to new peers
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
	# Defer 1 frame so the joining peer finishes spawning their player/items.
	call_deferred("_send_full_state_to_peer", peer_id)

func _register_scene_items() -> void:
	# Runs on ALL peers. Makes sure items have item_key meta and original parent recorded.
	var pickups: Array = get_tree().get_nodes_in_group("pickup")
	for obj in pickups:
		var item: Node = obj as Node
		if item == null:
			continue

		var key: NodePath = _stable_key_for_item(item)
		if String(key) == "":
			continue

		# Stamp stable key everywhere
		item.set_meta("item_key", String(key))

		# Record original parent once
		if not _original_parent.has(key):
			var parent_path: NodePath = _to_scene_path(item.get_parent())
			_original_parent[key] = parent_path

		# Remember last transform baseline
		if item is Node3D and not _last_world_xform.has(key):
			_last_world_xform[key] = (item as Node3D).global_transform

func _send_full_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Ensure we include ALL pickup items, even never-picked-up ones
	var payload: Array = []
	var pickups: Array = get_tree().get_nodes_in_group("pickup")

	for obj in pickups:
		var item: Node = obj as Node
		if item == null:
			continue

		var key: NodePath = _stable_key_for_item(item)
		if String(key) == "":
			continue

		if not _held_by.has(key):
			_held_by[key] = -1

		var xform: Transform3D = Transform3D.IDENTITY
		if item is Node3D:
			xform = (item as Node3D).global_transform
		elif _last_world_xform.has(key):
			xform = _last_world_xform[key]

		_last_world_xform[key] = xform

		var entry: Dictionary = {
			"key": String(key),
			"held_by": int(_held_by[key]),
			"xform": xform
		}
		payload.append(entry)

	rpc_id(peer_id, "sync_full_state", payload)

@rpc("any_peer", "call_local", "reliable")
func sync_full_state(payload: Array) -> void:
	# Runs on the JOINING peer. Reconstructs held/dropped state locally (fixes hovering & pickup).
	for v in payload:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = v

		if not d.has("key") or not d.has("held_by") or not d.has("xform"):
			continue

		var item_key: NodePath = NodePath(String(d["key"]))
		var holder_id: int = int(d["held_by"])
		var world_xform: Transform3D = d["xform"]

		_last_world_xform[item_key] = world_xform
		_held_by[item_key] = holder_id

		if holder_id != -1:
			var p: Node3D = _player_for_peer(holder_id)
			if p != null:
				var p_path: NodePath = _to_scene_path(p)
				apply_pickup(item_key, p_path, holder_id)
		else:
			apply_drop(item_key, world_xform, Vector3.ZERO)

# =========================
#      PATH HELPERS
# =========================
func _scene_root() -> Node:
	return get_tree().current_scene

func _resolve_scene_path(path: NodePath) -> Node:
	var scene: Node = _scene_root()
	if scene != null:
		var n: Node = scene.get_node_or_null(path)
		if n != null:
			return n
	return get_tree().root.get_node_or_null(path)

func _to_scene_path(n: Node) -> NodePath:
	var scene: Node = _scene_root()
	if scene == null or n == null:
		return NodePath("")
	return scene.get_path_to(n)

# =========================
#   STABLE ITEM LOOKUP
# =========================
func _resolve_item_anywhere(item_key: NodePath) -> Node:
	# 1) Try resolve by key path (works when under Items/)
	var direct: Node = _resolve_scene_path(item_key)
	if direct != null:
		return direct

	# 2) Fallback: scan pickup group for item_key meta match (works while held)
	var key_str: String = String(item_key)
	var pickups: Array = get_tree().get_nodes_in_group("pickup")
	for obj in pickups:
		var node: Node = obj as Node
		if node == null:
			continue
		if node.has_meta("item_key") and String(node.get_meta("item_key")) == key_str:
			return node

	return null

func _stable_key_for_item(item: Node) -> NodePath:
	if item != null and item.has_meta("item_key"):
		var s: String = String(item.get_meta("item_key"))
		if s != "":
			return NodePath(s)
	return _to_scene_path(item)

# =========================
#      PLAYER LOOKUP
# =========================
func _player_for_peer(peer_id: int) -> Node3D:
	var players: Array = get_tree().get_nodes_in_group("player")
	for n in players:
		var p3d: Node3D = n as Node3D
		if p3d == null:
			continue
		if p3d.get_multiplayer_authority() == peer_id:
			return p3d
	return null

# =========================
#   COLLISION HELPERS
# =========================
func _set_collision_shapes_enabled(root: Node, enabled: bool) -> void:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n == null:
			continue

		if n is CollisionShape3D:
			(n as CollisionShape3D).disabled = not enabled

		var children: Array = n.get_children()
		for c in children:
			var child: Node = c as Node
			if child != null:
				stack.append(child)

# =========================
#   PHYSICS HELPERS
# =========================
func _freeze_for_hold(item: Node) -> void:
	_set_collision_shapes_enabled(item, false)

	if item is RigidBody3D:
		var rb: RigidBody3D = item as RigidBody3D
		rb.linear_damp = held_linear_damp
		rb.angular_damp = held_angular_damp
		rb.gravity_scale = held_gravity_scale
		rb.freeze = true
		rb.sleeping = true

func _apply_slow_fall(rb: RigidBody3D) -> void:
	rb.linear_damp = drop_linear_damp
	rb.angular_damp = drop_angular_damp

	if cap_fall_speed:
		var v: Vector3 = rb.linear_velocity
		if v.y < -max_downward_speed:
			v.y = -max_downward_speed
			rb.linear_velocity = v

func _unfreeze_for_drop(item: Node, impulse_dir: Vector3) -> void:
	_set_collision_shapes_enabled(item, true)

	if item is RigidBody3D:
		var rb: RigidBody3D = item as RigidBody3D
		rb.freeze = false
		rb.sleeping = false
		rb.gravity_scale = drop_gravity_scale

		if drop_clear_velocity:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO

		_apply_slow_fall(rb)

		# Always nudge it so it wakes up on all peers (prevents hover)
		var impulse: Vector3 = impulse_dir * drop_impulse_strength + Vector3.DOWN * drop_downward_impulse
		if impulse.length() < 0.0001:
			impulse = Vector3.DOWN * 0.01
		rb.apply_central_impulse(impulse)

func _deferred_finalize_drop(item_key: NodePath) -> void:
	var item: Node = _resolve_item_anywhere(item_key)
	if item == null:
		return

	_set_collision_shapes_enabled(item, true)

	if item is RigidBody3D:
		var rb: RigidBody3D = item as RigidBody3D
		rb.freeze = false
		rb.sleeping = false
		rb.gravity_scale = drop_gravity_scale
		_apply_slow_fall(rb)

# =========================
#   ANIMATION HELPERS
# =========================
func _find_item_anim_player(item: Node) -> AnimationPlayer:
	if item == null:
		return null

	var ap: AnimationPlayer = item.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		return ap

	var found: Node = item.find_child("AnimationPlayer", true, false)
	return found as AnimationPlayer

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

	var item: Node = _resolve_scene_path(item_path)
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

	if not _held_by.has(item_key):
		_held_by[item_key] = -1

	if _held_by.has(item_key) and int(_held_by[item_key]) != -1:
		return

	if item.has_meta("locked") and bool(item.get_meta("locked")):
		return
	item.set_meta("locked", true)

	var p: Node3D = _player_for_peer(sender)
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
	var item: Node = _resolve_item_anywhere(item_key)
	var player: Node = _resolve_scene_path(player_path)
	if item == null or player == null:
		return

	item.set_meta("item_key", String(item_key))

	_freeze_for_hold(item)

	# While held, holder owns authority
	item.set_multiplayer_authority(new_owner_id)

	var marker: Node = player.get_node_or_null("Head/CarryObjectMarker")
	if marker != null and marker is Node3D:
		item.reparent(marker as Node3D)
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

	var item: Node3D = _resolve_item_anywhere(item_key) as Node3D
	if item == null:
		return

	if not _held_by.has(item_key):
		return
	if int(_held_by[item_key]) != sender:
		return

	var p: Node3D = _player_for_peer(sender)
	if p == null:
		return

	_held_by[item_key] = -1
	if item.has_meta("locked"):
		item.set_meta("locked", false)

	var forward: Vector3 = (-p.global_transform.basis.z).normalized()
	var drop_pos: Vector3 = p.global_position + forward * drop_forward_distance + Vector3.UP * drop_up_offset
	var drop_xform: Transform3D = Transform3D(item.global_transform.basis, drop_pos)

	# IMPORTANT: dropped items should be server-authoritative
	item.set_multiplayer_authority(SERVER_ID)

	_last_world_xform[item_key] = drop_xform

	rpc("apply_drop", item_key, drop_xform, forward)

	if "inventory" in p and p.has_method("server_set_inventory"):
		var id_to_remove: StringName = StringName(item.name)
		var new_inv: Array[StringName] = (p.inventory as Array[StringName]).duplicate()
		var idx: int = new_inv.find(id_to_remove)
		if idx != -1:
			new_inv.remove_at(idx)
		p.rpc_id(sender, "server_set_inventory", new_inv)

# =========================
#  ALL PEERS: APPLY DROP
# =========================
@rpc("any_peer", "call_local", "reliable")
func apply_drop(item_key: NodePath, world_xform: Transform3D, impulse_forward: Vector3) -> void:
	var item: Node3D = _resolve_item_anywhere(item_key) as Node3D
	if item == null:
		return

	item.set_meta("item_key", String(item_key))
	_last_world_xform[item_key] = world_xform

	var scene: Node = _scene_root()
	var parent_node: Node = null

	if _original_parent.has(item_key):
		var parent_path: NodePath = _original_parent[item_key]
		parent_node = _resolve_scene_path(parent_path)

	if parent_node == null:
		parent_node = scene if scene != null else get_tree().root

	item.reparent(parent_node)
	item.global_transform = world_xform

	# IMPORTANT: dropped items should be server-authoritative on all peers too
	item.set_multiplayer_authority(SERVER_ID)

	_unfreeze_for_drop(item, impulse_forward)

	if "set_held" in item:
		item.call_deferred("set_held", false)

	call_deferred("_deferred_finalize_drop", item_key)

# =========================
#   SERVER: USE/ATTACK
# =========================
@rpc("any_peer", "reliable")
func request_use_attack(item_key: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()

	# Must be holding this item
	if not _held_by.has(item_key):
		return
	if int(_held_by[item_key]) != sender:
		return

	# Broadcast to ALL peers so everyone sees the swing
	rpc("apply_use_attack", item_key)

# =========================
#  ALL PEERS: PLAY SWING
# =========================
@rpc("any_peer", "call_local", "reliable")
func apply_use_attack(item_key: NodePath) -> void:
	var item: Node = _resolve_item_anywhere(item_key)
	if item == null:
		return

	var ap: AnimationPlayer = _find_item_anim_player(item)
	if ap == null:
		return

	if not ap.has_animation(attack_animation_name):
		return

	if attack_restart_if_playing and ap.is_playing():
		ap.stop()

	ap.play(attack_animation_name)

# =========================
#   OPTIONAL: DEBUG HELP
# =========================
func debug_print_state() -> void:
	print("Held map:")
	for k in _held_by.keys():
		print(" - ", String(k), " => ", int(_held_by[k]))
