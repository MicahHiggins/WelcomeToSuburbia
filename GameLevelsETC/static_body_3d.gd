@tool
extends StaticBody3D

@export var player: Node3D
@export_tool_button("Preview Terrain") var preview_terrain = generate_preview

@export_group("Near Terrain")
@export var generate_terrain := true
@export var generate_new_chunks := true
@export var terrain_chunk_size: float = 30.0
@export var chunk_radius: int = 20
@export_range(0.1, 2.0, 0.15) var mesh_resolution: float = 0.2
@export var terrain_height_multiplier: float = 150.0  # not really used now
@export var terrain_height_offset: float = 0.0
@export var two_colors := false
@export var terrain_level_color: Color = Color.DARK_OLIVE_GREEN
@export var terrain_cliff_color: Color = Color.DIM_GRAY
@export var terrain_material: StandardMaterial3D

@export_group("Distant Terrain")
@export var enable_distant_terrain := true
@export var distant_terrain_update_during_gameplay := true
@export_range(0.1, 1.0, 0.1) var distant_terrain_mesh_resolution: float = 0.5
@export var distant_terrain_mesh_size: float = 16000.0

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

func _ready():
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
				var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y))
				if newmesh_and_mm:
					var newmesh = newmesh_and_mm[0]
					if use_multimesh:
						var newmm = newmesh_and_mm[1]
						newmm.add_to_group("do_not_own")
						add_child(newmm)
						newmm.global_position.y = terrain_height_offset
						var vis = Vector2(x, y).length() < multimesh_radius
						newmm.visible = vis
					newmesh.add_to_group("do_not_own")
					add_child(newmesh)
					newmesh.global_position.y = terrain_height_offset
				var newcollider = generate_terrain_collision(Vector2i(x, y))
				if newcollider:
					newcollider.add_to_group("do_not_own")
					add_child(newcollider)
					newcollider.rotation.y = -PI/2.0
					newcollider.global_position = Vector3(x * terrain_chunk_size, terrain_height_offset, y * terrain_chunk_size)
		if enable_distant_terrain:
			var new_bigmesh = generate_bigmesh(Vector2i(0, 0))
			new_bigmesh.add_to_group("do_not_own")
			add_child(new_bigmesh)
			new_bigmesh.global_position.y = terrain_height_offset - 3.0
			big_mesh = new_bigmesh

func _process(_delta):
	if player and generate_terrain and not Engine.is_editor_hint() and generate_new_chunks:
		var player_pos_3d: Vector3 = player.global_position.snapped(Vector3(terrain_chunk_size, terrain_chunk_size, terrain_chunk_size)) / terrain_chunk_size
		current_player_chunk = Vector2i(player_pos_3d.x, player_pos_3d.z)
		
		if queue_thread:
			if exit_thread:
				exit_thread = false
				semaphore.post()
				queue_thread = false

func ensure_default_values() -> void:
	if not terrain_material:
		terrain_material = StandardMaterial3D.new()
		terrain_material.vertex_color_use_as_albedo = false
		terrain_material.albedo_color = terrain_level_color

func generate_preview():
	if Engine.is_editor_hint():
		ensure_default_values()
		for child in get_children():
			child.queue_free()
		
		for x in range(-chunk_radius, chunk_radius + 1):
			for y in range(-chunk_radius, chunk_radius + 1):
				var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y), true)
				if newmesh_and_mm:
					var newmesh = newmesh_and_mm[0]
					if use_multimesh:
						var newmm = newmesh_and_mm[1]
						add_child(newmm)
						newmm.global_position.y = terrain_height_offset
					add_child(newmesh)
					newmesh.global_position.y = terrain_height_offset
				var newcollider = generate_terrain_collision(Vector2i(x, y), true)
				if newcollider:
					add_child(newcollider)
					newcollider.rotation.y = -PI/2.0
					newcollider.global_position = Vector3(x * terrain_chunk_size, terrain_height_offset, y * terrain_chunk_size)
		if enable_distant_terrain:
			var new_bigmesh = generate_bigmesh(Vector2i(0, 0))
			add_child(new_bigmesh)
			new_bigmesh.global_position.y = terrain_height_offset - 3.0
			big_mesh = new_bigmesh

func _player_in_new_chunk():
	if exit_thread:
		exit_thread = false
		semaphore.post()
	else:
		queue_thread = true

func _thread_function():
	while true:
		semaphore.wait()
		mutex.lock()
		var should_exit = exit_thread
		mutex.unlock()
		if should_exit:
			break
		
		mutex.lock()
		load_counter += 1
		var ccc := current_player_chunk
		
		if (load_counter < 20 or not distant_terrain_update_during_gameplay):
			for ix in range(-chunk_radius, chunk_radius + 1):
				var x = ccc.x + ix
				for iy in range(-chunk_radius, chunk_radius + 1):
					var y = ccc.y + iy
					var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y))
					if newmesh_and_mm:
						var newmesh = newmesh_and_mm[0]
						if use_multimesh:
							var newmm = newmesh_and_mm[1]
							newmm.call_deferred("add_to_group", "do_not_own")
							call_deferred("add_child", newmm)
							newmm.call_deferred("global_translate", Vector3(0.0, terrain_height_offset, 0.0))
							var vis: bool = Vector2(ix, iy).length() < multimesh_radius
							newmm.call_deferred("set_visible", vis)
						newmesh.call_deferred("add_to_group", "do_not_own")
						call_deferred("add_child", newmesh)
						newmesh.call_deferred("global_translate", Vector3(0.0, terrain_height_offset, 0.0))
					var newcollider = generate_terrain_collision(Vector2i(x, y))
					if newcollider:
						newcollider.call_deferred("add_to_group", "do_not_own")
						call_deferred("add_child", newcollider)
						newcollider.call_deferred("rotate_y", -PI/2.0)
						newcollider.call_deferred("set_global_position", Vector3(x * terrain_chunk_size, terrain_height_offset, y * terrain_chunk_size))
		else:
			load_counter = 0
			if enable_distant_terrain and distant_terrain_update_during_gameplay:
				var new_bigmesh = generate_bigmesh(ccc)
				big_mesh.call_deferred("queue_free")
				call_deferred("add_child", new_bigmesh)
				new_bigmesh.call_deferred("global_translate", Vector3(0.0, terrain_height_offset - 3.0, 0.0))
				new_bigmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				big_mesh = new_bigmesh
		
		# cleanup
		for k: Vector2i in mesh_dict.keys():
			if absi(ccc.x - k.x) > chunk_radius or absi(ccc.y - k.y) > chunk_radius:
				var mesh_to_remove = mesh_dict[k]
				if collider_dict.has(k):
					var col_to_remove = collider_dict[k]
					collider_dict.erase(k)
					col_to_remove.call_deferred("queue_free")
				if use_multimesh and multimesh_dict.has(k):
					var mm_to_remove = multimesh_dict[k]
					multimesh_dict.erase(k)
					mm_to_remove.call_deferred("queue_free")
				mesh_dict.erase(k)
				mesh_to_remove.call_deferred("queue_free")
			else:
				if multimesh_dict.has(k):
					var chunk: Vector2i = k - ccc
					var vis: bool = Vector2(chunk.x, chunk.y).length() < multimesh_radius
					multimesh_dict[k].call_deferred("set_visible", vis)
		
		mutex.unlock()
		mutex.lock()
		exit_thread = true
		mutex.unlock()

func generate_terrain_mesh(chunk: Vector2i, ignore_dict: bool = false):
	if not mesh_dict.has(chunk) or ignore_dict:
		var chunkmesh := MeshInstance3D.new()
		if not ignore_dict:
			mesh_dict[chunk] = chunkmesh
		
		var arrmesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		
		var verts: PackedVector3Array = []
		var uvs: PackedVector2Array = []
		var norms: PackedVector3Array = []
		var colors: PackedColorArray = []
		var indices: PackedInt32Array = []
		
		var chunk_x := float(chunk.x)
		var chunk_z := float(chunk.y)
		var chunk_center := Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
		
		var start_x: float = chunk_center.x - (terrain_chunk_size * 0.5)
		var start_z: float = chunk_center.y - (terrain_chunk_size * 0.5)
		var end_x: float = chunk_center.x + (terrain_chunk_size * 0.5)
		var end_z: float = chunk_center.y + (terrain_chunk_size * 0.5)
		
		var four_counter: int = 0
		var chunk_subdivisions := int(terrain_chunk_size * (mesh_resolution))
		
		for x_division: int in chunk_subdivisions:
			var progress_x := float(x_division) / float(chunk_subdivisions)
			var x_coord := lerpf(start_x, end_x, progress_x)
			var progress_x_next := float(x_division + 1) / float(chunk_subdivisions)
			var x_coord_next := lerpf(start_x, end_x, progress_x_next)
			for z_division: int in chunk_subdivisions:
				var progress_z := float(z_division) / float(chunk_subdivisions)
				var z_coord := lerpf(start_z, end_z, progress_z)
				var progress_z_next := float(z_division + 1) / float(chunk_subdivisions)
				var z_coord_next := lerpf(start_z, end_z, progress_z_next)
				
				var uv_scale := 500.0 / terrain_chunk_size
				
				var coord_3d := Vector3(x_coord, terrain_height_offset, z_coord)
				var coord_3d_next_x := Vector3(x_coord_next, terrain_height_offset, z_coord)
				var coord_3d_next_z := Vector3(x_coord, terrain_height_offset, z_coord_next)
				var coord_3d_next_xz := Vector3(x_coord_next, terrain_height_offset, z_coord_next)
				
				var uv1 := Vector2(progress_x, progress_z) / uv_scale
				var uv2 := Vector2(progress_x_next, progress_z) / uv_scale
				var uv3 := Vector2(progress_x, progress_z_next) / uv_scale
				var uv4 := Vector2(progress_x_next, progress_z_next) / uv_scale
				
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
				
				indices.append_array([four_counter + 0, four_counter + 1, four_counter + 3, four_counter + 3, four_counter + 2, four_counter + 0])
				four_counter += 4
		
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		
		arrmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		chunkmesh.mesh = arrmesh
		chunkmesh.set_surface_override_material(0, terrain_material)
		
		return [chunkmesh]
	else:
		return false

func generate_terrain_collision(chunk: Vector2i, ignore_dict: bool = false):
	if not collider_dict.has(chunk) or ignore_dict:
		var newcollider := CollisionShape3D.new()
		newcollider.shape = HeightMapShape3D.new()
		newcollider.shape.map_width = terrain_chunk_size + 1.0
		newcollider.shape.map_depth = terrain_chunk_size + 1.0
		
		if not ignore_dict:
			collider_dict[chunk] = newcollider
		
		var map_data: PackedFloat32Array = []
		
		for x_division: int in int(terrain_chunk_size) + 1:
			for z_division: int in int(terrain_chunk_size) + 1:
				map_data.append(terrain_height_offset)
		
		newcollider.shape.map_data = map_data
		return newcollider
	else:
		return false

func generate_bigmesh(chunk: Vector2i):
	# just make a big flat mesh in the distance
	var new_mesh := MeshInstance3D.new()
	var arrmesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []
	
	var chunk_center := Vector2(chunk.x * terrain_chunk_size, chunk.y * terrain_chunk_size)
	var start_x: float = chunk_center.x - (distant_terrain_mesh_size * 0.5)
	var start_z: float = chunk_center.y - (distant_terrain_mesh_size * 0.5)
	var end_x: float = chunk_center.x + (distant_terrain_mesh_size * 0.5)
	var end_z: float = chunk_center.y + (distant_terrain_mesh_size * 0.5)
	
	var four_counter := 0
	var chunk_subdivisions := int(distant_terrain_mesh_size * (distant_terrain_mesh_resolution * 0.05))
	
	for x_division: int in chunk_subdivisions:
		var progress_x := float(x_division) / float(chunk_subdivisions)
		var x_coord := lerpf(start_x, end_x, progress_x)
		var progress_x_next := float(x_division + 1) / float(chunk_subdivisions)
		var x_coord_next := lerpf(start_x, end_x, progress_x_next)
		for z_division: int in chunk_subdivisions:
			var progress_z := float(z_division) / float(chunk_subdivisions)
			var z_coord := lerpf(start_z, end_z, progress_z)
			var progress_z_next := float(z_division + 1) / float(chunk_subdivisions)
			var z_coord_next := lerpf(start_z, end_z, progress_z_next)
			
			var uv_scale := 500.0 / distant_terrain_mesh_size
			
			var c1 := Vector3(x_coord, terrain_height_offset, z_coord)
			var c2 := Vector3(x_coord_next, terrain_height_offset, z_coord)
			var c3 := Vector3(x_coord, terrain_height_offset, z_coord_next)
			var c4 := Vector3(x_coord_next, terrain_height_offset, z_coord_next)
			
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
			
			indices.append_array([four_counter + 0, four_counter + 1, four_counter + 3, four_counter + 3, four_counter + 2, four_counter + 0])
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

func sample_2dv(point: Vector2) -> float:
	# flat world
	return 0.0

func _on_tree_exiting():
	if not Engine.is_editor_hint() and mutex:
		mutex.lock()
		exit_thread = true
		mutex.unlock()
		semaphore.post()
		thread.wait_to_finish()
