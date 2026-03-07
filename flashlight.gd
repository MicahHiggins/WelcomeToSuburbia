extends CharacterBody3D
class_name UVFlashlight

@onready var interact_area: Area3D = $Area3D
@onready var uv_light: SpotLight3D = $SpotLight3D

# CHANGED: ShapeCast3D instead of RayCast3D
# Set this in the inspector if your node isn't named "ShapeCast3D"
@export var uv_cast_path: NodePath = NodePath("ShapeCast3D")
var uv_cast: ShapeCast3D = null

# optional outline like your bat (set path if you have it)
@export var outline_mesh_path: NodePath
var outline_mesh: MeshInstance3D = null

@export var authority_only_physics: bool = true

# beam/reveal tuning
@export var uv_range_m: float = 10.0
@export var reveal_radius_m: float = 1.75
@export var reveal_max_targets_per_frame: int = 12

# input
@export var toggle_action: StringName = &"toggle_flashlight"  # add in InputMap

# net (optional: makes other players see beam on/off)
@export var replicate_light_toggle: bool = true

var _held: bool = false
var _hovered: bool = false
var _uv_on: bool = false

# cache for “things we turned on this frame”
var _revealed_this_frame: Dictionary = {}
var _previous_reveals: Array[UvRevealTarget] = []

func _ready() -> void:
	add_to_group("pickup")

	# outline hover
	if outline_mesh_path != NodePath(""):
		outline_mesh = get_node_or_null(outline_mesh_path) as MeshInstance3D
		if outline_mesh != null:
			outline_mesh.visible = false

	# pickup ray target layer setup (same pattern as your bat)
	if interact_area != null:
		interact_area.set_collision_layer_value(4, true)
		interact_area.collision_mask = 0

	# bind shapecast safely
	uv_cast = get_node_or_null(uv_cast_path) as ShapeCast3D
	if uv_cast == null:
		push_error("[UVFlashlight] ShapeCast3D not found. Set uv_cast_path to your ShapeCast3D node.")
	else:
		uv_cast.enabled = false
		uv_cast.target_position = Vector3(0, 0, -uv_range_m)
		# NOTE: make sure the ShapeCast3D has a Shape assigned in the inspector

	# default off
	if uv_light != null:
		uv_light.visible = false

func set_hovered(v: bool) -> void:
	_hovered = v
	if outline_mesh != null and not _held:
		outline_mesh.visible = v

func set_held(v: bool) -> void:
	_held = v
	if outline_mesh != null:
		outline_mesh.visible = false

	# when dropped, kill UV
	if not v:
		_set_uv_on(false)

func _unhandled_input(event: InputEvent) -> void:
	# only allow toggle when held
	if not _held:
		return
	if event.is_action_pressed(String(toggle_action)):
		_set_uv_on(not _uv_on)

func _process(_delta: float) -> void:
	# purely visual reveal, do it locally
	if not _held or not _uv_on:
		_revealed_this_frame.clear()
		_clear_previous_reveals()
		return

	# update cast
	if uv_cast != null:
		uv_cast.enabled = true
		uv_cast.target_position = Vector3(0, 0, -uv_range_m)
		uv_cast.force_shapecast_update()

	_revealed_this_frame.clear()
	_reveal_in_beam()
	_clear_previous_reveals()

func _reveal_in_beam() -> void:
	# We pick a "beam center" point:
	# - if ShapeCast hits something: use closest collision point
	# - else: point straight ahead at max range
	var hit_pos := global_transform.origin + (-global_transform.basis.z.normalized() * uv_range_m)

	if uv_cast != null and uv_cast.is_colliding():
		# pick the closest collision
		var best_d := INF
		for i in range(uv_cast.get_collision_count()):
			var p := uv_cast.get_collision_point(i)
			var d := global_transform.origin.distance_to(p)
			if d < best_d:
				best_d = d
				hit_pos = p

	# reveal nearby targets
	var targets: Array = get_tree().get_nodes_in_group("uv_reveal")
	var count := 0

	for t in targets:
		if count >= reveal_max_targets_per_frame:
			break

		var rt := t as UvRevealTarget
		if rt == null or not is_instance_valid(rt):
			continue

		var d := rt.global_position.distance_to(hit_pos)
		if d <= reveal_radius_m:
			rt.set_reveal(true)
			_revealed_this_frame[rt] = true
			count += 1

	# maintain previous list (only valid ones)
	_previous_reveals = _previous_reveals.filter(func(x): return x != null and is_instance_valid(x))
	for k in _revealed_this_frame.keys():
		var rr := k as UvRevealTarget
		if rr != null and _previous_reveals.find(rr) == -1:
			_previous_reveals.append(rr)

func _clear_previous_reveals() -> void:
	for rt in _previous_reveals:
		if rt == null or not is_instance_valid(rt):
			continue
		if not _revealed_this_frame.has(rt):
			rt.set_reveal(false)

func _set_uv_on(v: bool) -> void:
	_uv_on = v

	if uv_light != null:
		uv_light.visible = v
	if uv_cast != null:
		uv_cast.enabled = v

	# optional: replicate the light visible to others (cosmetic)
	if replicate_light_toggle and multiplayer.has_multiplayer_peer():
		rpc("_rpc_set_uv_visible", v)

@rpc("any_peer", "call_local", "unreliable")
func _rpc_set_uv_visible(v: bool) -> void:
	if uv_light != null:
		uv_light.visible = v
