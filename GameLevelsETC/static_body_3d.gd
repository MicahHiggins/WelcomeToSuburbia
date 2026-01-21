@tool
extends StaticBody3D

# =========================
#         PLAYER / EDITOR
# =========================

@export var player: Node3D
@export_tool_button("Preview Terrain") var preview_terrain = generate_preview

# =========================
#        NEAR TERRAIN
# =========================

@export_group("Near Terrain")
@export var generate_terrain := true
@export var generate_new_chunks := true
@export var terrain_chunk_size: float = 30.0
@export var chunk_radius: int = 20
@export_range(0.1, 2.0, 0.15) var mesh_resolution: float = 0.2
@export var terrain_height_multiplier: float = 150.0  # not used; flat town
@export var terrain_height_offset: float = 0.5        # raise a bit so it meets assets
@export var two_colors := false
@export var terrain_level_color: Color = Color.DARK_OLIVE_GREEN
@export var terrain_cliff_color: Color = Color.DIM_GRAY
@export var terrain_material: StandardMaterial3D

# =========================
#       DISTANT TERRAIN
# =========================

@export_group("Distant Terrain")
@export var enable_distant_terrain := true
@export var distant_terrain_update_during_gameplay := true
@export_range(0.1, 1.0, 0.1) var distant_terrain_mesh_resolution: float = 0.5
@export var distant_terrain_mesh_size: float = 16000.0

# =========================
#          MULTIMESH
# =========================

@export_group("Multimesh")
@export var use_multimesh := false
@export var multimesh_cast_shadow: MeshInstance3D.ShadowCastingSetting
@export var multimesh_radius: int = 6
@export var multimesh_mesh: Mesh
@export_range(0.0, 1.0, 0.01) var multimesh_coverage: float = 0.5
@export_range(0.0, 10.0, 0.1) var multimesh_jitter: float = 5.0
@export var multimesh_on_cliffs := false
@export_range(0.0, 1.0, 0.1) var multimesh_steep_threshold: float = 0.5
@export_range(1.0, 10.0, 1.0) var multimesh_repeats: int = 1

# =========================
#        TOWN PROPS
# =========================

@export_group("Town Props")
@export var road_scene: PackedScene         # road segment scene
@export var house_scene: PackedScene        # house scene

# Roads along Z axis, centered at X = 0
@export var town_road_count: int = 12       # how many road segments in the line (each side)
@export var town_road_spacing: float = 180.0 # spacing between road segments (more spread)
@export var house_offset_from_road: float = 40.0 # how far houses sit from road center (X)

# Big visible roads
@export var road_scale: Vector3 = Vector3(5.0, 1.0, 5.0)
@export var road_height_offset: float = 0.35   # slightly above terrain so visible

# =========================
#    RUNTIME STATE / DATA
# =========================

var current_player_chunk: Vector2i:
	set(value):
		if current_player_chunk:
			if current_player_chunk != value:
				_player_in_new_chunk()
		current_player_chunk = value

var mesh_dict: Dictionary = {}
var collider_dict: Dictionary = {}
var multimesh_dict: Dictionary = {}
var big_mesh: MeshInstance3D

var mutex: Mutex
var semaphore: Semaphore
var thread: Thread
var exit_thread := false
var queue_thread := false
var load_counter: int = 0

# =========================
#           READY
# =========================

func _ready() -> void:
	ensure_default_values()
	
	if generate_terrain and not Engine.is_editor_hint():
		if generate_new_chunks:
			mutex = Mutex.new()
			semaphore = Semaphore.new()
			exit_thread = true
			
			thread = Thread.new()
			thread.start(_thread_function, Thread.PRIORITY_HIGH)
		
		for x: int in range(-chunk_radius, chunk_radius + 1):
			for y: int in range(-chunk_radius, chunk_radius + 1):
				var newmesh_and_mm: Variant = generate_terrain_mesh(Vector2i(x, y))
				if newmesh_and_mm:
					var newmesh: MeshInstance3D = newmesh_and_mm[0]
					if use_multimesh:
						var newmm: MultiMeshInstance3D = newmesh_and_mm[1]
						newmm.add_to_group("do_not_own")
						add_child(newmm)
						newmm.global_position.y = terrain_height_offset
						var vis: bool = Vector2(x, y).length() < float(multimesh_radius)
						newmm.visible = vis
					newmesh.add_to_group("do_not_own")
					add_child(newmesh)
					newmesh.global_position.y = terrain_height_offset
				
				var newcollider: CollisionShape3D = generate_terrain_collision(Vector2i(x, y))
				if newcollider:
					newcollider.add_to_group("do_not_own")
					add_child(newcollider)
					newcollider.rotation.y = -PI / 2.0
					newcollider.global_position = Vector3(
						float(x) * terrain_chunk_size,
						terrain_height_offset,
						float(y) * terrain_chunk_size
					)
		
		if enable_distant_terrain:
			var new_bigmesh: MeshInstance3D = generate_bigmesh(Vector2i(0, 0))
			new_bigmesh.add_to_group("do_not_own")
			add_child(new_bigmesh)
			new_bigmesh.global_position.y = terrain_height_offset - 3.0
			big_mesh = new_bigmesh
		
		# Spawn the repeating town layout (roads + houses)
		_generate_town_layout()

# =========================
#          PROCESS
# =========================

func _process(_delta: float) -> void:
	if player and generate_terrain and not Engine.is_editor_hint() and generate_new_chunks:
		var player_pos_3d: Vector3 = (
			player.global_position.snapped(
				Vector3(terrain_chunk_size, terrain_chunk_size, terrain_chunk_size)
			) / terrain_chunk_size
		)
		current_player_chunk = Vector2i(int(player_pos_3d.x), int(player_pos_3d.z))
		
		if queue_thread:
			if exit_thread:
				exit_thread = false
				semaphore.post()
				queue_thread = false

# =========================
#    MATERIAL / DEFAULTS
# =========================

func ensure_default_values() -> void:
	if terrain_material == null:
		terrain_material = StandardMaterial3D.new()
		terrain_material.vertex_color_use_as_albedo = false
		terrain_material.albedo_color = terrain_level_color

# =========================
#     EDITOR PREVIEW BTN
# =========================

func generate_preview() -> void:
	if Engine.is_editor_hint():
		ensure_default_values()
		
		for child: Node in get_children():
			child.queue_free()
		
		for x: int in range(-chunk_radius, chunk_radius + 1):
			for y: int in range(-chunk_radius, chunk_radius + 1):
				var newmesh_and_mm: Variant = generate_terrain_mesh(Vector2i(x, y), true)
				if newmesh_and_mm:
					var newmesh: MeshInstance3D = newmesh_and_mm[0]
					if use_multimesh:
						var newmm: MultiMeshInstance3D = newmesh_and_mm[1]
						add_child(newmm)
						newmm.global_position.y = terrain_height_offset
					add_child(newmesh)
					newmesh.global_position.y = terrain_height_offset
				
				var newcollider: CollisionShape3D = generate_terrain_collision(Vector2i(x, y), true)
				if newcollider:
					add_child(newcollider)
					newcollider.rotation.y = -PI / 2.0
					newcollider.global_position = Vector3(
						float(x) * terrain_chunk_size,
						terrain_height_offset,
						float(y) * terrain_chunk_size
					)
		
		if enable_distant_terrain:
			var new_bigmesh: MeshInstance3D = generate_bigmesh(Vector2i(0, 0))
			add_child(new_bigmesh)
			new_bigmesh.global_position.y = terrain_height_offset - 3.0
			big_mesh = new_bigmesh
		
		# Show roads + houses in the editor preview too
		_generate_town_layout()

# =========================
#    CHUNK / THREAD LOGIC
# =========================

func _player_in_new_chunk() -> void:
	if exit_thread:
		exit_thread = false
		semaphore.post()
	else:
		queue_thread = true

func _thread_function() -> void:
	while true:
		semaphore.wait()
		mutex.lock()
		var should_exit: bool = exit_thread
		mutex.unlock()
		
		if should_exit:
			break
		
		mutex.lock()
		load_counter += 1
		var ccc: Vector2i = current_player_chunk
		
		if (load_counter < 20 or not distant_terrain_update_during_gameplay):
			for ix: int in range(-chunk_radius, chunk_radius + 1):
				var x: int = ccc.x + ix
				for iy: int in range(-chunk_radius, chunk_radius + 1):
					var y: int = ccc.y + iy
					
					var newmesh_and_mm: Variant = generate_terrain_mesh(Vector2i(x, y))
					if newmesh_and_mm:
						var newmesh: MeshInstance3D = newmesh_and_mm[0]
						
						if use_multimesh:
							# safe-guard in case we ever return [mesh] only
							var newmm: MultiMeshInstance3D = (
								newmesh_and_mm[1] if newmesh_and_mm.size() > 1 else null
							)
							if newmm != null:
								newmm.call_deferred("add_to_group", "do_not_own")
								call_deferred("add_child", newmm)
								newmm.call_deferred(
									"global_translate",
									Vector3(0.0, terrain_height_offset, 0.0)
								)
								var vis: bool = Vector2(float(ix), float(iy)).length() < float(multimesh_radius)
								newmm.call_deferred("set_visible", vis)
						
						newmesh.call_deferred("add_to_group", "do_not_own")
						call_deferred("add_child", newmesh)
						newmesh.call_deferred(
							"global_translate",
							Vector3(0.0, terrain_height_offset, 0.0)
						)
					
					var newcollider: CollisionShape3D = generate_terrain_collision(Vector2i(x, y))
					if newcollider:
						newcollider.call_deferred("add_to_group", "do_not_own")
						call_deferred("add_child", newcollider)
						newcollider.call_deferred("rotate_y", -PI / 2.0)
						newcollider.call_deferred(
							"set_global_position",
							Vector3(
								float(x) * terrain_chunk_size,
								terrain_height_offset,
								float(y) * terrain_chunk_size
							)
						)
		else:
			load_counter = 0
			if enable_distant_terrain and distant_terrain_update_during_gameplay:
				var new_bigmesh: MeshInstance3D = generate_bigmesh(ccc)
				big_mesh.call_deferred("queue_free")
				call_deferred("add_child", new_bigmesh)
				new_bigmesh.call_deferred(
					"global_translate",
					Vector3(0.0, terrain_height_offset - 3.0, 0.0)
				)
				new_bigmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				big_mesh = new_bigmesh
		
		# --- cleanup meshes out of range ---
		for k: Vector2i in mesh_dict.keys():
			if absi(ccc.x - k.x) > chunk_radius or absi(ccc.y - k.y) > chunk_radius:
				var mesh_to_remove: MeshInstance3D = mesh_dict[k]
				
				if collider_dict.has(k):
					var col_to_remove: CollisionShape3D = collider_dict[k]
					collider_dict.erase(k)
					col_to_remove.call_deferred("queue_free")
				
				if use_multimesh and multimesh_dict.has(k):
					var mm_to_remove: MultiMeshInstance3D = multimesh_dict[k]
					multimesh_dict.erase(k)
					mm_to_remove.call_deferred("queue_free")
				
				mesh_dict.erase(k)
				mesh_to_remove.call_deferred("queue_free")
			else:
				if multimesh_dict.has(k):
					var chunk: Vector2i = k - ccc
					var vis: bool = Vector2(float(chunk.x), float(chunk.y)).length() < float(multimesh_radius)
					multimesh_dict[k].call_deferred("set_visible", vis)
		
		mutex.unlock()
		mutex.lock()
		exit_thread = true
		mutex.unlock()

# =========================
#   TERRAIN MESH / COLLIDER
# =========================

func generate_terrain_mesh(chunk: Vector2i, ignore_dict: bool = false) -> Variant:
	if not mesh_dict.has(chunk) or ignore_dict:
		var chunkmesh: MeshInstance3D = MeshInstance3D.new()
		if not ignore_dict:
			mesh_dict[chunk] = chunkmesh
		
		var arrmesh: ArrayMesh = ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		
		var verts: PackedVector3Array = PackedVector3Array()
		var uvs: PackedVector2Array = PackedVector2Array()
		var norms: PackedVector3Array = PackedVector3Array()
		var colors: PackedColorArray = PackedColorArray()
		var indices: PackedInt32Array = PackedInt32Array()
		
		var chunk_x: float = float(chunk.x)
		var chunk_z: float = float(chunk.y)
		var chunk_center: Vector2 = Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
		
		var start_x: float = chunk_center.x - (terrain_chunk_size * 0.5)
		var start_z: float = chunk_center.y - (terrain_chunk_size * 0.5)
		var end_x: float = chunk_center.x + (terrain_chunk_size * 0.5)
		var end_z: float = chunk_center.y + (terrain_chunk_size * 0.5)
		
		var four_counter: int = 0
		var chunk_subdivisions: int = int(terrain_chunk_size * mesh_resolution)
		
		for x_division: int in chunk_subdivisions:
			var progress_x: float = float(x_division) / float(chunk_subdivisions)
			var x_coord: float = lerpf(start_x, end_x, progress_x)
			var progress_x_next: float = float(x_division + 1) / float(chunk_subdivisions)
			var x_coord_next: float = lerpf(start_x, end_x, progress_x_next)
			
			for z_division: int in chunk_subdivisions:
				var progress_z: float = float(z_division) / float(chunk_subdivisions)
				var z_coord: float = lerpf(start_z, end_z, progress_z)
				var progress_z_next: float = float(z_division + 1) / float(chunk_subdivisions)
				var z_coord_next: float = lerpf(start_z, end_z, progress_z_next)
				
				var uv_scale: float = 500.0 / terrain_chunk_size
				
				var coord_3d: Vector3 = Vector3(x_coord, terrain_height_offset, z_coord)
				var coord_3d_next_x: Vector3 = Vector3(x_coord_next, terrain_height_offset, z_coord)
				var coord_3d_next_z: Vector3 = Vector3(x_coord, terrain_height_offset, z_coord_next)
				var coord_3d_next_xz: Vector3 = Vector3(x_coord_next, terrain_height_offset, z_coord_next)
				
				var uv1: Vector2 = Vector2(progress_x, progress_z) / uv_scale
				var uv2: Vector2 = Vector2(progress_x_next, progress_z) / uv_scale
				var uv3: Vector2 = Vector2(progress_x, progress_z_next) / uv_scale
				var uv4: Vector2 = Vector2(progress_x_next, progress_z_next) / uv_scale
				
				verts.append(coord_3d)
				norms.append(Vector3.UP)
				uvs.append(uv1)
				colors.append(terrain_level_color)
				
				verts.append(coord_3d_next_x)
				norms.append(Vector3.UP)
				uvs.append(uv2)
				colors.append(terrain_level_color)
				
				verts.append(coord_3d_next_z)
				norms.append(Vector3.UP)
				uvs.append(uv3)
				colors.append(terrain_level_color)
				
				verts.append(coord_3d_next_xz)
				norms.append(Vector3.UP)
				uvs.append(uv4)
				colors.append(terrain_level_color)
				
				indices.append_array(
					[
						four_counter + 0,
						four_counter + 1,
						four_counter + 3,
						four_counter + 3,
						four_counter + 2,
						four_counter + 0
					]
				)
				four_counter += 4
		
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		
		arrmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		chunkmesh.mesh = arrmesh
		chunkmesh.set_surface_override_material(0, terrain_material)
		
		# NOTE: currently no multimesh data, so we just return [mesh]
		return [chunkmesh]
	else:
		return false

func generate_terrain_collision(chunk: Vector2i, ignore_dict: bool = false) -> CollisionShape3D:
	if not collider_dict.has(chunk) or ignore_dict:
		var newcollider: CollisionShape3D = CollisionShape3D.new()
		var hshape: HeightMapShape3D = HeightMapShape3D.new()
		newcollider.shape = hshape
		
		# +1 so borders overlap nicely
		hshape.map_width = terrain_chunk_size + 1.0
		hshape.map_depth = terrain_chunk_size + 1.0
		
		if not ignore_dict:
			collider_dict[chunk] = newcollider
		
		var map_data: PackedFloat32Array = PackedFloat32Array()
		var size_int: int = int(terrain_chunk_size) + 1
		
		for _x_division: int in size_int:
			for _z_division: int in size_int:
				map_data.append(terrain_height_offset)
		
		hshape.map_data = map_data
		return newcollider
	else:
		return null

# =========================
#      BIG DISTANT MESH
# =========================

func generate_bigmesh(chunk: Vector2i) -> MeshInstance3D:
	# Big flat (or slightly varied) mesh in the distance.
	var new_mesh: MeshInstance3D = MeshInstance3D.new()
	var arrmesh: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	
	var chunk_center: Vector2 = Vector2(chunk.x * terrain_chunk_size, chunk.y * terrain_chunk_size)
	var start_x: float = chunk_center.x - (distant_terrain_mesh_size * 0.5)
	var start_z: float = chunk_center.y - (distant_terrain_mesh_size * 0.5)
	var end_x: float = chunk_center.x + (distant_terrain_mesh_size * 0.5)
	var end_z: float = chunk_center.y + (distant_terrain_mesh_size * 0.5)
	
	var four_counter: int = 0
	var chunk_subdivisions: int = int(distant_terrain_mesh_size * (distant_terrain_mesh_resolution * 0.05))
	
	for x_division: int in chunk_subdivisions:
		var progress_x: float = float(x_division) / float(chunk_subdivisions)
		var x_coord: float = lerpf(start_x, end_x, progress_x)
		var progress_x_next: float = float(x_division + 1) / float(chunk_subdivisions)
		var x_coord_next: float = lerpf(start_x, end_x, progress_x_next)
		
		for z_division: int in chunk_subdivisions:
			var progress_z: float = float(z_division) / float(chunk_subdivisions)
			var z_coord: float = lerpf(start_z, end_z, progress_z)
			var progress_z_next: float = float(z_division + 1) / float(chunk_subdivisions)
			var z_coord_next: float = lerpf(start_z, end_z, progress_z_next)
			
			var uv_scale: float = 500.0 / distant_terrain_mesh_size
			
			var c1: Vector3 = Vector3(x_coord, terrain_height_offset, z_coord)
			var c2: Vector3 = Vector3(x_coord_next, terrain_height_offset, z_coord)
			var c3: Vector3 = Vector3(x_coord, terrain_height_offset, z_coord_next)
			var c4: Vector3 = Vector3(x_coord_next, terrain_height_offset, z_coord_next)
			
			verts.append(c1)
			norms.append(Vector3.UP)
			uvs.append(Vector2(progress_x, progress_z) / uv_scale)
			colors.append(terrain_level_color)
			
			verts.append(c2)
			norms.append(Vector3.UP)
			uvs.append(Vector2(progress_x_next, progress_z) / uv_scale)
			colors.append(terrain_level_color)
			
			verts.append(c3)
			norms.append(Vector3.UP)
			uvs.append(Vector2(progress_x, progress_z_next) / uv_scale)
			colors.append(terrain_level_color)
			
			verts.append(c4)
			norms.append(Vector3.UP)
			uvs.append(Vector2(progress_x_next, progress_z_next) / uv_scale)
			colors.append(terrain_level_color)
			
			indices.append_array(
				[
					four_counter + 0,
					four_counter + 1,
					four_counter + 3,
					four_counter + 3,
					four_counter + 2,
					four_counter + 0
				]
			)
			four_counter += 4
	
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	arrmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	new_mesh.mesh = arrmesh
	new_mesh.set_surface_override_material(0, terrain_material)
	return new_mesh

# =========================
#      HEIGHT SAMPLER
# =========================

func sample_2dv(_point: Vector2) -> float:
	# Flat town world – everything at terrain_height_offset.
	return terrain_height_offset

# =========================
#        TOWN LAYOUT
# =========================

func _generate_town_layout() -> void:
	# One long line of roads through the flat town area, with houses on both sides.
	# Roads run along the Z axis, centered at X = 0.
	if road_scene == null and house_scene == null:
		return
	
	for i: int in range(-town_road_count, town_road_count + 1):
		var z_pos: float = float(i) * town_road_spacing
		
		# --- Road segment ---
		if road_scene != null:
			var road_inst: Node3D = road_scene.instantiate() as Node3D
			if road_inst != null:
				add_child(road_inst)
				var t: Transform3D = road_inst.global_transform
				t.origin = Vector3(
					0.0,
					terrain_height_offset + road_height_offset,
					z_pos
				)
				road_inst.global_transform = t
				# If your road mesh was modeled to point along X, swap this to 90°:
				# road_inst.rotate_y(deg_to_rad(90.0))
				road_inst.rotate_z(deg_to_rad(90.0))
				road_inst.scale = road_scale
		
		# --- Houses on left/right of the road ---
		if house_scene != null:
			var left_house: Node3D = house_scene.instantiate() as Node3D
			var right_house: Node3D = house_scene.instantiate() as Node3D
			
			if left_house != null:
				add_child(left_house)
				var lt: Transform3D = left_house.global_transform
				lt.origin = Vector3(
					-house_offset_from_road,
					terrain_height_offset,
					z_pos
				)
				left_house.global_transform = lt
			
			if right_house != null:
				add_child(right_house)
				var rt: Transform3D = right_house.global_transform
				rt.origin = Vector3(
					house_offset_from_road,
					terrain_height_offset,
					z_pos
				)
				right_house.global_transform = rt

# =========================
#        CLEANUP
# =========================

func _on_tree_exiting() -> void:
	if not Engine.is_editor_hint() and mutex:
		mutex.lock()
		exit_thread = true
		mutex.unlock()
		semaphore.post()
		thread.wait_to_finish()
