extends Node3D
class_name Level1WorldPCGSync

@onready var world_block_1: Node3D = $worldBlock1
@onready var world_block_2: Node3D = $worldBlock2
@onready var world_block_3: Node3D = $worldBlock3
@onready var world_block_4: Node3D = $worldBlock4
@onready var world_block_5: Node3D = $worldBlock5

const DISPLACEMENT: float = 176.0
const SERVER_ID: int = 1

var world_blocks: Array[Node3D] = []

# Per-zone debounce
var iteration: Array[int] = [0, 0, 0, 0, 0]


func _ready() -> void:
	world_blocks = [world_block_1, world_block_2, world_block_3, world_block_4, world_block_5]


# -------------------------
# ZONE EVENTS (client -> server request, server decides)
# -------------------------
func _on_load_zone_1_body_entered(body: Node3D) -> void:
	_on_zone_enter(0, body)

func _on_load_zone_2_body_entered(body: Node3D) -> void:
	_on_zone_enter(1, body)

func _on_load_zone_3_body_entered(body: Node3D) -> void:
	_on_zone_enter(2, body)

func _on_load_zone_4_body_entered(body: Node3D) -> void:
	_on_zone_enter(3, body)

func _on_load_zone_5_body_entered(body: Node3D) -> void:
	_on_zone_enter(4, body)

func _on_load_zone_1_body_exited(_body: Node3D) -> void:
	iteration[0] = 0

func _on_load_zone_2_body_exited(_body: Node3D) -> void:
	iteration[1] = 0

func _on_load_zone_3_body_exited(_body: Node3D) -> void:
	iteration[2] = 0

func _on_load_zone_4_body_exited(_body: Node3D) -> void:
	iteration[3] = 0

func _on_load_zone_5_body_exited(_body: Node3D) -> void:
	iteration[4] = 0


#
#func _on_load_zone_1_body_exited(body: Node3D) -> void:
	#iteration1 = 0
#
#
#func _on_load_zone_2_body_exited(body: Node3D) -> void:
	#iteration2 = 0
#
#
#func _on_load_zone_3_body_exited(body: Node3D) -> void:
	#iteration3 = 0
#
#
#func _on_load_zone_4_body_exited(body: Node3D) -> void:
	#iteration4 = 0
#
#
#func _on_load_zone_5_body_exited(body: Node3D) -> void:
	#iteration5 = 0
func _on_zone_enter(zone_idx: int, body: Node3D) -> void:
	# Only react to players (prevents physics junk triggering layout)
	if body == null or (not body.is_in_group("player")):
		return

	iteration[zone_idx] += 1
	if iteration[zone_idx] < 2:
		return
	iteration[zone_idx] = 0

	# SINGLEPLAYER: just run locally
	if not multiplayer.has_multiplayer_peer():
		_server_apply_layout(zone_idx)
		return

	# MULTIPLAYER: server decides
	if multiplayer.is_server():
		_server_apply_layout(zone_idx)
	else:
		# Ask server to apply layout based on this zone
		rpc_id(SERVER_ID, "_rpc_request_layout", zone_idx)


@rpc("any_peer", "reliable")
func _rpc_request_layout(zone_idx: int) -> void:
	# Server only
	if not multiplayer.is_server():
		return
	_server_apply_layout(zone_idx)


# -------------------------
# SERVER: compute layout + broadcast
# -------------------------
func _server_apply_layout(center_idx: int) -> void:
	# Optional global kill switch (but DO NOT rely on GlobalVariables for syncing)
	# If you still want this, keep it server-only:
	if typeof(GlobalVariables) != TYPE_NIL and GlobalVariables.algoDebug == true:
		return

	var layout: Array[Vector3] = _compute_layout_positions(center_idx)

	# Broadcast final positions to ALL peers (including host)
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_apply_layout", layout)
	else:
		_rpc_apply_layout(layout)


func _compute_layout_positions(center_idx: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(5)

	var center_pos: Vector3 = world_blocks[center_idx].global_position
	out[center_idx] = center_pos

	var displacement_x: float = DISPLACEMENT
	var displacement_z: float = DISPLACEMENT

	var counter := 0
	for i in range(5):
		if i == center_idx:
			continue

		var p := center_pos

		# first 2 go +/-X, last 2 go +/-Z 
		if counter < 2:
			p.x = center_pos.x + displacement_x
			displacement_x = -DISPLACEMENT
		else:
			p.z = center_pos.z + displacement_z
			displacement_z = DISPLACEMENT

		out[i] = p
		counter += 1

	return out


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_layout(layout: Array) -> void:
	# layout is expected size 5, items are Vector3
	if layout.size() != 5:
		return

	for i in range(5):
		var b: Node3D = world_blocks[i]
		if b == null:
			continue

		
		var v_any: Variant = layout[i]
		if typeof(v_any) == TYPE_VECTOR3:
			b.global_position = v_any as Vector3
