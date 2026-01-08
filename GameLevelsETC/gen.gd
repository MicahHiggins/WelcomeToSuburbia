# gen.gd
extends Node3D

# ----- GRID & SCALES -----
@export var grid_size: int = 24                     # number of cells per side
@export var cell_size: float = 8.0                  # world units per cell

# Main road band: a single straight road made of several parallel lanes
@export var vertical_main_road: bool = true
@export var main_road_index: int = 12               # which grid line the main road sits on
@export var road_band_count: int = 3                # number of parallel lanes
@export var road_band_spacing_factor: float = 0.9   # lane spacing in multiples of cell_size

# Visual scales
@export var road_scale_mult: float = 20.0           # chunky road tiles
@export var house_scale_mult: float = 8.0           # house size multiplier
@export var tree_scale: float = 10.0                 # trees a bit bigger

# Placement / layout
@export var house_density: float = 0.65             # probability to place a house on an eligible cell
@export var tree_count: int = 120                   # extra scattered trees
@export var random_jitter: float = 0.25             # small jitter for houses (reduced for “more orderly” look)

# Multiple house types (plug in 0–4 scenes here if you have them)
@export var house_scenes: Array[PackedScene] = []   # drop your different house scenes here (optional)

# Optional scenes for road/trees
@export var road_straight_scene: PackedScene
@export var tree_scene: PackedScene

# Track occupied house cells so we don't touch
var _house_cells: Dictionary = {} # Vector2i -> bool

func _ready() -> void:
	randomize()
	if main_road_index < 0 or main_road_index >= grid_size:
		main_road_index = grid_size / 2
	_generate_city()


func _generate_city() -> void:
	_spawn_main_road_band()
	_place_houses_off_road()
	_scatter_extra_trees()


# ----------------------------
# ROAD GENERATION
# ----------------------------
func _spawn_main_road_band() -> void:
	var lane_offsets: PackedFloat32Array = _lane_offsets_world()
	if vertical_main_road:
		for z: int in range(grid_size):
			for off: float in lane_offsets:
				var base: Vector3 = _grid_to_world(main_road_index, z)
				base.x += off
				_spawn_road_tile(base, true)  # vertical tile (runs along Z)
	else:
		for x: int in range(grid_size):
			for off: float in lane_offsets:
				var base: Vector3 = _grid_to_world(x, main_road_index)
				base.z += off
				_spawn_road_tile(base, false) # horizontal tile (runs along X)


func _lane_offsets_world() -> PackedFloat32Array:
	var offs: PackedFloat32Array = PackedFloat32Array()
	var count: int = max(1, road_band_count)
	var spacing: float = cell_size * road_band_spacing_factor
	for i: int in range(count):
		var idx: float = float(i) - (float(count) - 1.0) * 0.5
		offs.append(idx * spacing)
	return offs


func _spawn_road_tile(world_pos: Vector3, vertical: bool) -> void:
	if road_straight_scene:
		var inst: Node3D = road_straight_scene.instantiate() as Node3D
		inst.position = world_pos
		if vertical:
			inst.rotation.y = deg_to_rad(90.0)
		inst.scale *= road_scale_mult
		add_child(inst)
	else:
		var road := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(cell_size * 0.98, 0.12, cell_size * 0.98)
		road.mesh = mesh
		road.material_override = _road_material()
		road.position = world_pos + Vector3(0.0, 0.06, 0.0)
		road.scale *= road_scale_mult
		if vertical:
			road.rotation.y = deg_to_rad(90.0)
		add_child(road)


# ----------------------------
# HOUSES (multiple types & more orderly alignment)
# ----------------------------
func _place_houses_off_road() -> void:
	_house_cells.clear()
	for gx: int in range(grid_size):
		for gz: int in range(grid_size):
			var center_pos: Vector3 = _grid_to_world(gx, gz)
			if _is_inside_road_band_world(center_pos):
				continue
			if randf() > house_density:
				continue
			if _has_neighbor_house(gx, gz):
				continue

			# Slightly more orderly: small patterned offset perpendicular to road + small jitter
			var ordered_offset: Vector3 = _house_order_offset(gx, gz)
			var wpos: Vector3 = center_pos + ordered_offset + _jitter_vec2d()

			_spawn_house_at(gx, gz, wpos)
			_house_cells[Vector2i(gx, gz)] = true


func _spawn_house_at(gx: int, gz: int, wpos: Vector3) -> void:
	var front_yaw: float = _yaw_towards_main_road(wpos)
	var scene: PackedScene = _pick_house_scene()

	if scene:
		var inst: Node3D = scene.instantiate() as Node3D
		inst.position = wpos
		inst.rotation.y = front_yaw
		inst.scale *= house_scale_mult
		add_child(inst)
	else:
		# Fallback: 4 variants
		var variant: int = randi_range(0, 3)
		match variant:
			0:
				_spawn_house_variant_modern_box(wpos, front_yaw)
			1:
				_spawn_house_variant_townhouse(wpos, front_yaw)
			2:
				_spawn_house_variant_l_shape(wpos, front_yaw)
			_:
				_spawn_house_variant_flat_roof(wpos, front_yaw)


func _pick_house_scene() -> PackedScene:
	if house_scenes.is_empty():
		return null
	# Filter out nulls in case some slots are empty
	var valid: Array[PackedScene] = []
	for s: PackedScene in house_scenes:
		if s != null:
			valid.append(s)
	if valid.is_empty():
		return null
	return valid[randi() % valid.size()]


# Fallback variants (simple geometry mixes)
func _spawn_house_variant_modern_box(wpos: Vector3, yaw: float) -> void:
	# Base
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(cell_size * 0.7, cell_size * 0.6, cell_size * 0.6)
	base.mesh = base_mesh
	base.material_override = _house_material_color(Color(0.82, 0.78, 0.73))
	base.position = wpos + Vector3(0, base_mesh.size.y * 0.5, 0)
	base.rotation.y = yaw
	base.scale *= house_scale_mult
	add_child(base)

	# Upper smaller volume (roof/second story)
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(cell_size * 0.55, cell_size * 0.25, cell_size * 0.5)
	top.mesh = top_mesh
	top.material_override = _house_material_color(Color(0.75, 0.74, 0.78))
	top.position = wpos + Vector3(0, base_mesh.size.y + top_mesh.size.y * 0.5, 0)
	top.rotation.y = yaw
	top.scale *= house_scale_mult
	add_child(top)


func _spawn_house_variant_townhouse(wpos: Vector3, yaw: float) -> void:
	var tower := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cell_size * 0.45, cell_size * 1.2, cell_size * 0.45)
	tower.mesh = mesh
	tower.material_override = _house_material_color(Color(0.88, 0.83, 0.76))
	tower.position = wpos + Vector3(0, mesh.size.y * 0.5, 0)
	tower.rotation.y = yaw
	tower.scale *= house_scale_mult
	add_child(tower)


func _spawn_house_variant_l_shape(wpos: Vector3, yaw: float) -> void:
	var a := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(cell_size * 0.55, cell_size * 0.5, cell_size * 0.25)
	a.mesh = am
	a.material_override = _house_material_color(Color(0.80, 0.76, 0.70))
	a.position = wpos + Vector3(0, am.size.y * 0.5, 0)
	a.rotation.y = yaw
	a.scale *= house_scale_mult
	add_child(a)

	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(cell_size * 0.25, cell_size * 0.5, cell_size * 0.55)
	b.mesh = bm
	b.material_override = _house_material_color(Color(0.84, 0.80, 0.75))
	# Offset b to form an L around local -Z front
	var dir: Vector3 = _dir_from_yaw(yaw) # forward (-Z) in world
	var right: Vector3 = Vector3(dir.z, 0.0, -dir.x)
	b.position = wpos + Vector3(0, bm.size.y * 0.5, 0) + right * (cell_size * 0.4)
	b.rotation.y = yaw
	b.scale *= house_scale_mult
	add_child(b)


func _spawn_house_variant_flat_roof(wpos: Vector3, yaw: float) -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(cell_size * 0.65, cell_size * 0.55, cell_size * 0.65)
	base.mesh = bm
	base.material_override = _house_material_color(Color(0.78, 0.77, 0.82))
	base.position = wpos + Vector3(0, bm.size.y * 0.5, 0)
	base.rotation.y = yaw
	base.scale *= house_scale_mult
	add_child(base)

	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(bm.size.x * 0.95, cell_size * 0.06, bm.size.z * 0.95)
	roof.mesh = rm
	roof.material_override = _house_material_color(Color(0.23, 0.23, 0.25))
	roof.position = wpos + Vector3(0, bm.size.y + rm.size.y * 0.5, 0)
	roof.rotation.y = yaw
	roof.scale *= house_scale_mult
	add_child(roof)


# ----------------------------
# TREES
# ----------------------------
func _scatter_extra_trees() -> void:
	for i: int in range(tree_count):
		var gx: int = randi_range(0, grid_size - 1)
		var gz: int = randi_range(0, grid_size - 1)
		if _house_cells.has(Vector2i(gx, gz)):
			continue
		var wpos: Vector3 = _grid_to_world(gx, gz)
		if _is_inside_road_band_world(wpos):
			continue
		_spawn_tree(wpos + _jitter_vec2d() * 1.5)


func _spawn_tree(wpos: Vector3) -> void:
	if tree_scene:
		var t: Node3D = tree_scene.instantiate() as Node3D
		t.position = wpos
		t.scale *= tree_scale
		add_child(t)
	else:
		var trunk := MeshInstance3D.new()
		var tmesh := CylinderMesh.new()
		tmesh.top_radius = 0.16
		tmesh.bottom_radius = 0.2
		tmesh.height = 1.8
		trunk.mesh = tmesh
		trunk.material_override = _trunk_material()
		trunk.position = wpos + Vector3(0.0, tmesh.height * 0.5, 0.0)
		trunk.scale *= tree_scale
		add_child(trunk)

		var canopy := MeshInstance3D.new()
		var cmesh := SphereMesh.new()
		cmesh.radius = 0.9
		canopy.mesh = cmesh
		canopy.material_override = _leaf_material()
		canopy.position = wpos + Vector3(0.0, tmesh.height + cmesh.radius * 0.9, 0.0) * tree_scale
		add_child(canopy)


# ----------------------------
# ORDER / ORIENTATION HELPERS
# ----------------------------
func _house_order_offset(gx: int, gz: int) -> Vector3:
	# FIXED ternary to GDScript form:
	var sign: float = 1.0 if (((gx + gz) % 2) == 0) else -1.0
	var amount: float = cell_size * 0.15
	if vertical_main_road:
		# Perpendicular to road (X) so distribute slightly along Z to form straighter rows
		return Vector3(0.0, 0.0, sign * amount)
	else:
		# Perpendicular to road (Z) so distribute slightly along X
		return Vector3(sign * amount, 0.0, 0.0)


func _yaw_towards_main_road(wpos: Vector3) -> float:
	var target: Vector3 = _nearest_point_on_main_road(wpos)
	var dir: Vector3 = (target - wpos)
	dir.y = 0.0
	if dir.length() < 0.0001:
		return 0.0
	dir = dir.normalized()
	# In Godot, -Z is forward. Convert world direction to yaw.
	return atan2(-dir.x, -dir.z)


func _nearest_point_on_main_road(wpos: Vector3) -> Vector3:
	if vertical_main_road:
		var cx: float = _grid_to_world(main_road_index, 0).x
		return Vector3(cx, wpos.y, wpos.z)
	else:
		var cz: float = _grid_to_world(0, main_road_index).z
		return Vector3(wpos.x, wpos.y, cz)


func _dir_from_yaw(yaw: float) -> Vector3:
	# Forward vector for an object whose forward is -Z (Godot default)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


# ----------------------------
# WORLD / BOUNDS HELPERS
# ----------------------------
func _grid_to_world(x: int, z: int) -> Vector3:
	var wx: float = (float(x) - float(grid_size) * 0.5) * cell_size
	var wz: float = (float(z) - float(grid_size) * 0.5) * cell_size
	return Vector3(wx, 0.0, wz)


func _is_inside_road_band_world(p: Vector3) -> bool:
	var band_half: float = (float(road_band_count) - 1.0) * 0.5 * (cell_size * road_band_spacing_factor)
	if vertical_main_road:
		var center_x: float = _grid_to_world(main_road_index, 0).x
		return absf(p.x - center_x) <= band_half + (cell_size * 0.6)
	else:
		var center_z: float = _grid_to_world(0, main_road_index).z
		return absf(p.z - center_z) <= band_half + (cell_size * 0.6)


func _has_neighbor_house(gx: int, gz: int) -> bool:
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var nx: int = gx + dx
			var nz: int = gz + dz
			if nx < 0 or nx >= grid_size or nz < 0 or nz >= grid_size:
				continue
			if _house_cells.has(Vector2i(nx, nz)):
				return true
	return false


# ----------------------------
# MATERIALS (fallbacks)
# ----------------------------
func _road_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.12)
	m.roughness = 1.0
	return m


func _house_material_color(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _trunk_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.23, 0.12)
	m.roughness = 0.8
	return m


func _leaf_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.55, 0.25)
	m.roughness = 0.6
	return m


# ----------------------------
# SMALL UTILS
# ----------------------------
func _jitter_vec2d() -> Vector3:
	return Vector3(
		randf_range(-random_jitter, random_jitter) * cell_size,
		0.0,
		randf_range(-random_jitter, random_jitter) * cell_size
	)
