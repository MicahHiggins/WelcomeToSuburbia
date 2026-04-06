# res://LobbyWorldBlock.gd
extends Node3D
class_name LobbyWorldBlock

# ============================================================
#  LOBBY WORLD BLOCK 
#  - Spawns trees on the block, excluding a center "no-tree" band
#  - Designed to work with conveyor pooling/reuse:
#      call prepare_for_use() whenever the block is spawned/reused
# ============================================================

# -------------------------
# BLOCK BOUNDS (local space)
# -------------------------
@export var block_size_x: float = 40.0
@export var block_size_z: float = 40.0
@export var ground_y: float = 0.0
@export var tree_ground_lift: float = 0.2

# -------------------------
# ROAD / NO-TREE BAND
# Single knob: half width of the exclusion band around the road center
# Example:
#   road_width = 8, padding = 3  ->  no_tree_half_width = 4 + 3 = 7
# -------------------------
@export var road_center_x: float = 0.0
@export var no_tree_half_width: float = 7.0  # <-- ONLY VALUE YOU TWEAK to keep trees off road

# -------------------------
# TREE SPAWN SETTINGS
# -------------------------
@export var enable_trees: bool = true
@export var tree_scene: PackedScene

@export var trees_per_block_min: int = 10
@export var trees_per_block_max: int = 22

@export var tree_min_spacing: float = 3.0

@export var tree_scale_multiplier: float = 1.0
@export var tree_scale_min_abs: float = 1.0
@export var tree_scale_max_abs: float = 2.0

@export var random_yaw: bool = true

# If true, each time prepare_for_use() is called, we randomize the seed
@export var randomize_each_use: bool = true

# If randomize_each_use is false, this seed is used (0 means random once at startup)
@export var seed: int = 0

# -------------------------
# DEBUG
# -------------------------
@export var debug_print: bool = false

# -------------------------
# INTERNAL
# -------------------------
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _trees_container: Node3D = null
var _has_seeded_once: bool = false


func _ready() -> void:
	_ensure_container()
	_seed_rng_once_if_needed()

	# If you are NOT pooling/reusing blocks, this is enough.
	# If you ARE pooling/reusing, call prepare_for_use() from the conveyor script each time.
	if enable_trees:
		_spawn_trees()


# Call this whenever the conveyor reuses / repositions a block.
func prepare_for_use() -> void:
	_ensure_container()

	if randomize_each_use:
		_rng.randomize()
	else:
		_seed_rng_once_if_needed()

	if enable_trees:
		_spawn_trees()
	else:
		_clear_trees_immediately()


# ============================================================
# SETUP
# ============================================================
func _ensure_container() -> void:
	_trees_container = get_node_or_null("Trees") as Node3D
	if _trees_container == null:
		_trees_container = Node3D.new()
		_trees_container.name = "Trees"
		add_child(_trees_container)

func _seed_rng_once_if_needed() -> void:
	if _has_seeded_once:
		return

	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = int(seed)

	_has_seeded_once = true


# ============================================================
# TREE SPAWNING
# ============================================================
func _clear_trees_immediately() -> void:
	if _trees_container == null:
		return

	var kids: Array = _trees_container.get_children()
	for c_any in kids:
		var c: Node = c_any as Node
		if c != null:
			_trees_container.remove_child(c)
			c.free()

func _spawn_trees() -> void:
	if tree_scene == null:
		push_warning("[LobbyWorldBlock] tree_scene is NULL.")
		return

	_clear_trees_immediately()

	var want: int = _rng.randi_range(trees_per_block_min, trees_per_block_max)

	var half_x: float = block_size_x * 0.5
	var half_z: float = block_size_z * 0.5

	var placed: Array[Vector3] = []
	var spawned: int = 0
	var attempts: int = 0

	# robust attempts so it doesn't "give up" too early
	var max_attempts: int = max(400, want * 200)

	while spawned < want and attempts < max_attempts:
		attempts += 1

		var x: float = _rng.randf_range(-half_x, half_x)
		var z: float = _rng.randf_range(-half_z, half_z)

		# exclude the road band (single knob)
		if absf(x - road_center_x) <= no_tree_half_width:
			continue

		var local_pos: Vector3 = Vector3(x, ground_y + tree_ground_lift, z)
		var world_pos: Vector3 = global_transform * local_pos

		# spacing check
		var ok: bool = true
		for p: Vector3 in placed:
			if p.distance_to(world_pos) < tree_min_spacing:
				ok = false
				break
		if not ok:
			continue

		var inst: Node = tree_scene.instantiate()
		var t3: Node3D = inst as Node3D
		if t3 == null:
			inst.queue_free()
			continue

		_trees_container.add_child(t3)
		t3.global_position = world_pos
		t3.visible = true

		if random_yaw:
			t3.rotation.y = _rng.randf_range(0.0, TAU)

		var s_abs: float = _rng.randf_range(tree_scale_min_abs, tree_scale_max_abs)
		var s: float = s_abs * tree_scale_multiplier
		t3.scale = Vector3(s, s, s)

		placed.append(world_pos)
		spawned += 1

	if debug_print:
		print("[LobbyWorldBlock] spawned=", spawned, "/", want,
			" attempts=", attempts,
			" noTreeHalfWidth=", no_tree_half_width)
