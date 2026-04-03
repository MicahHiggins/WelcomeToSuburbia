# res://LobbyWorldConveyor.gd
extends Node3D
class_name LobbyWorldConveyor

@export var block_scene: PackedScene

@export var block_length_z: float = 40.0
@export var move_speed: float = 8.0
@export var blocks_visible: int = 6
@export var move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
@export var conveyor_origin: Vector3 = Vector3.ZERO
@export var despawn_blocks_behind: float = 2.0

# ------------------------------------------------------------
# Trees (BLOCK-OWNED)
# - Conveyor does NOT spawn trees itself.
# - It simply tells the block to rebuild trees when spawned/recycled.
# - Configure tree_scene + spacing + road buffer ONLY on LobbyWorldBlock.
# ------------------------------------------------------------
@export var enable_block_tree_rebuild: bool = true
@export var block_tree_rebuild_method: StringName = &"rebuild_trees" # or "rebuild_block" if you prefer

var _blocks: Array[Node3D] = []
var _dir: Vector3 = Vector3(0.0, 0.0, -1.0)

func _ready() -> void:
	_dir = move_direction
	if _dir.length() < 0.0001:
		push_warning("[LobbyWorldConveyor] move_direction was zero; defaulting to (0,0,-1).")
		_dir = Vector3(0.0, 0.0, -1.0)
	_dir = _dir.normalized()

	_blocks.clear()

	if block_scene == null:
		push_error("[LobbyWorldConveyor] block_scene is NULL. Assign LobbyWorldBlock.tscn in inspector.")
		return

	if blocks_visible <= 0:
		push_error("[LobbyWorldConveyor] blocks_visible <= 0.")
		return

	_spawn_initial_blocks()

func _process(delta: float) -> void:
	_scroll_blocks(delta)
	_recycle_blocks_if_needed()

func _spawn_initial_blocks() -> void:
	for i: int in range(blocks_visible):
		var b: Node3D = _spawn_block_at_index(i)
		if b != null:
			_blocks.append(b)

func _spawn_block_at_index(i: int) -> Node3D:
	var inst_any: Node = block_scene.instantiate()
	if inst_any == null:
		push_error("[LobbyWorldConveyor] instantiate() returned null.")
		return null

	var b: Node3D = inst_any as Node3D
	if b == null:
		push_error("[LobbyWorldConveyor] LobbyWorldBlock root is NOT Node3D. Root is: %s" % inst_any.get_class())
		inst_any.queue_free()
		return null

	add_child(b)

	var z_off: float = float(i) * block_length_z
	b.global_position = conveyor_origin + (-_dir) * z_off
	b.name = "LobbyWorldBlock_%d" % i

	# IMPORTANT: let the block build its own trees exactly like the "first block"
	_request_block_tree_rebuild(b)

	return b

func _scroll_blocks(delta: float) -> void:
	if _blocks.is_empty():
		return

	var step: Vector3 = _dir * move_speed * delta
	for b: Node3D in _blocks:
		if b == null or not is_instance_valid(b):
			continue
		b.global_position += step

func _recycle_blocks_if_needed() -> void:
	if _blocks.is_empty():
		return

	var behind_limit: float = despawn_blocks_behind * block_length_z

	var best_ahead: float = -INF
	for b: Node3D in _blocks:
		if b == null or not is_instance_valid(b):
			continue
		var rel: Vector3 = b.global_position - conveyor_origin
		var ahead_proj: float = rel.dot(-_dir)
		if ahead_proj > best_ahead:
			best_ahead = ahead_proj

	for idx: int in range(_blocks.size()):
		var b2: Node3D = _blocks[idx]
		if b2 == null or not is_instance_valid(b2):
			continue

		var rel2: Vector3 = b2.global_position - conveyor_origin
		var behind_proj: float = rel2.dot(_dir)

		if behind_proj > behind_limit:
			var new_ahead: float = best_ahead + block_length_z
			b2.global_position = conveyor_origin + (-_dir) * new_ahead
			best_ahead = new_ahead

			# Rebuild trees on recycle so every "new" block looks fresh
			_request_block_tree_rebuild(b2)

func _request_block_tree_rebuild(block: Node3D) -> void:
	if not enable_block_tree_rebuild:
		return

	# We defer 1 frame to ensure block _ready() has run and its nodes exist
	call_deferred("_deferred_block_tree_rebuild", block)

func _deferred_block_tree_rebuild(block: Node3D) -> void:
	if block == null or not is_instance_valid(block):
		return

	# Preferred: block implements rebuild_trees()
	if block.has_method(String(block_tree_rebuild_method)):
		block.call(String(block_tree_rebuild_method))
		return

	# Fallbacks (in case your block script uses different method names)
	if block.has_method("rebuild_block"):
		block.call("rebuild_block")
		return
	if block.has_method("rebuild_trees"):
		block.call("rebuild_trees")
		return

	# Last resort: if the block auto-spawns in _ready(), do nothing
	push_warning("[LobbyWorldConveyor] Block has no rebuild method (rebuild_trees/rebuild_block). Trees may not refresh on recycle.")
