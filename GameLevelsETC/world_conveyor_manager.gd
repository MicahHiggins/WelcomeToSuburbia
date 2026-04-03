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

# -------------------------
# Trees
# -------------------------
@export var enable_trees: bool = true
@export var tree_scene: PackedScene

# These are searched *inside each LobbyWorldBlock instance*
@export var tree_area_paths: Array[NodePath] = [NodePath("TreeAreaLeft"), NodePath("TreeAreaRight")]

@export var trees_per_block_min: int = 18
@export var trees_per_block_max: int = 32
@export var tree_y_offset: float = 0.0

# spacing / sampling
@export var tree_min_spacing: float = 1.4
@export var tree_spawn_max_attempts_per_tree: int = 18

# fallback if no TreeArea nodes exist:
# (half-extents in local space, centered on the block root)
@export var fallback_grass_half_extents: Vector3 = Vector3(16.0, 0.0, 14.0)

# variety
@export var random_yaw: bool = true
@export var random_scale: bool = true
@export var scale_min: float = 0.85
@export var scale_max: float = 1.25

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _blocks: Array[Node3D] = []
var _dir: Vector3 = Vector3(0.0, 0.0, -1.0)

func _ready() -> void:
	_rng.randomize()

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

	if enable_trees:
		_spawn_trees_for_block(b)

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

	var best_ahead: float = -float("inf")
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

			if enable_trees:
				_clear_block_trees(b2)
				_spawn_trees_for_block(b2)

# ============================================================
# Trees
# ============================================================
func _spawn_trees_for_block(block: Node3D) -> void:
	if tree_scene == null:
		push_warning("[LobbyWorldConveyor] enable_trees=true but tree_scene is NULL.")
		return

	var areas: Array[Node3D] = _get_tree_area_nodes(block)
	if areas.is_empty():
		# allowed: we will use fallback sampling
		pass

	var want: int = _rng.randi_range(trees_per_block_min, trees_per_block_max)
	var placed: Array[Vector3] = []

	var container: Node3D = block.get_node_or_null("Trees") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "Trees"
		block.add_child(container)

	for i: int in range(want):
		var ok: bool = false
		var chosen_pos: Vector3 = Vector3.ZERO

		var attempts: int = 0
		var max_attempts: int = tree_spawn_max_attempts_per_tree

		while attempts < max_attempts and not ok:
			attempts += 1
			var sample: Vector3

			if areas.is_empty():
				sample = _sample_point_in_fallback_grass(block)
			else:
				var area_idx: int = _rng.randi_range(0, areas.size() - 1)
				sample = _sample_point_in_area(areas[area_idx])

			sample.y += tree_y_offset

			var spaced: bool = true
			for p: Vector3 in placed:
				if p.distance_to(sample) < tree_min_spacing:
					spaced = false
					break

			if spaced:
				chosen_pos = sample
				ok = true

		if not ok:
			continue

		placed.append(chosen_pos)

		var t_any: Node = tree_scene.instantiate()
		var t3: Node3D = t_any as Node3D
		if t3 == null:
			push_warning("[LobbyWorldConveyor] tree_scene root is NOT Node3D.")
			continue

		container.add_child(t3)
		t3.global_position = chosen_pos

		if random_yaw:
			t3.rotation.y = _rng.randf_range(0.0, TAU)

		if random_scale:
			var s: float = _rng.randf_range(scale_min, scale_max)
			t3.scale = Vector3(s, s, s)

func _clear_block_trees(block: Node3D) -> void:
	var container: Node3D = block.get_node_or_null("Trees") as Node3D
	if container == null:
		return
	for ch: Node in container.get_children():
		if ch != null and is_instance_valid(ch):
			ch.queue_free()

func _get_tree_area_nodes(block: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p: NodePath in tree_area_paths:
		var n: Node3D = block.get_node_or_null(p) as Node3D
		if n != null:
			out.append(n)
	return out

func _sample_point_in_area(area_node: Node3D) -> Vector3:
	var cs: CollisionShape3D = area_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is BoxShape3D:
		var box: BoxShape3D = cs.shape as BoxShape3D
		var ext: Vector3 = box.size * 0.5
		var lx: float = _rng.randf_range(-ext.x, ext.x)
		var lz: float = _rng.randf_range(-ext.z, ext.z)
		return area_node.to_global(Vector3(lx, 0.0, lz))

	# fallback if area isn't a BoxShape3D
	var fx: float = _rng.randf_range(-fallback_grass_half_extents.x, fallback_grass_half_extents.x)
	var fz: float = _rng.randf_range(-fallback_grass_half_extents.z, fallback_grass_half_extents.z)
	return area_node.to_global(Vector3(fx, 0.0, fz))

func _sample_point_in_fallback_grass(block: Node3D) -> Vector3:
	# sample in block-local rectangle centered at root
	var lx: float = _rng.randf_range(-fallback_grass_half_extents.x, fallback_grass_half_extents.x)
	var lz: float = _rng.randf_range(-fallback_grass_half_extents.z, fallback_grass_half_extents.z)
	return block.to_global(Vector3(lx, 0.0, lz))
