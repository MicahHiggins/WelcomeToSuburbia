extends Node3D

@onready var world_block_1: Node3D = $worldBlock1
@onready var world_block_2: Node3D = $worldBlock2
@onready var world_block_3: Node3D = $worldBlock3
@onready var world_block_4: Node3D = $worldBlock4
@onready var world_block_5: Node3D = $worldBlock5

var prevWB
var worldBlocks2: Array[Node3D]

var iteration1 = 0
var iteration2 = 0
var iteration3 = 0
var iteration4 = 0
var iteration5 = 0

var player

const DISPLACEMENT = 176

# ADDED: server id for Steam multiplayer (host is usually 1)
const SERVER_ID: int = 1


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	worldBlocks2 = [world_block_1, world_block_2, world_block_3,
	world_block_4, world_block_5]
	
	AudioManager.gameStart.emit()
	#print(worldBlocks2[1])


## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass


func algoForIterations(worldBlocks):
	# ADDED: in multiplayer, only the server is allowed to compute/move blocks
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if GlobalVariables.algoDebug == true:
		return

	var currentWorldBlockIteration = worldBlocks2[worldBlocks].global_position
	var currentWorldBlockIterationZ = worldBlocks2[worldBlocks].global_position.z
	var currentWorldBlockIterationX = worldBlocks2[worldBlocks].global_position.x
	var displacement = DISPLACEMENT

	var counter = 0
	print("TESTETSTSETETESRE")
	for i in range(5):

		if i != worldBlocks:

			if counter < 2:
				print("AHAHAHAH")
				GlobalVariables.ITERS+=0.5
				currentWorldBlockIterationX = worldBlocks2[worldBlocks].global_position.x
				worldBlocks2[i].global_position = currentWorldBlockIteration
				worldBlocks2[i].global_position.x = currentWorldBlockIterationX + displacement
				displacement = -DISPLACEMENT
				counter = counter + 1

			else:
				worldBlocks2[i].global_position = currentWorldBlockIteration
				currentWorldBlockIterationZ = worldBlocks2[worldBlocks].global_position.z
				worldBlocks2[i].global_position.z = currentWorldBlockIterationZ + displacement
				displacement = DISPLACEMENT
				counter = counter + 1

	GlobalVariables.algoDebug = false

	# ADDED: after server moves blocks, broadcast the final positions to all peers
	_broadcast_worldblock_positions()


# ADDED: send block positions to everyone (server authoritative)
func _broadcast_worldblock_positions() -> void:
	# singleplayer: nothing to sync
	if not multiplayer.has_multiplayer_peer():
		return

	# server broadcasts current positions
	if multiplayer.is_server():
		var positions: Array = []
		for b in worldBlocks2:
			positions.append(b.global_position)
		rpc("_rpc_apply_worldblock_positions", positions)


# ADDED: apply the server's positions on all peers
@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_worldblock_positions(positions: Array) -> void:
	# safety: expect 5 Vector3s
	if positions.size() != 5:
		return

	for i in range(5):
		var v: Variant = positions[i]
		if typeof(v) == TYPE_VECTOR3:
			worldBlocks2[i].global_position = v


func _on_load_zone_1_body_entered(body: Node3D) -> void:
	# ADDED: if multiplayer client, request server to run iteration instead of running locally
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_request_iteration", 0)
		return

	print(body)
	iteration1 = iteration1 + 1
	if iteration1 == 2:
		algoForIterations(0)
		iteration1 = 0
	print("numba 0")


func _on_load_zone_2_body_entered(body: Node3D) -> void:
	# ADDED: client requests server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_request_iteration", 1)
		return

	iteration2 = iteration2 + 1
	if iteration2 == 2:
		algoForIterations(1)
		iteration2 = 0
	print("numba 1")


func _on_load_zone_3_body_entered(body: Node3D) -> void:
	# ADDED: client requests server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_request_iteration", 2)
		return

	iteration3 = iteration3 + 1
	if iteration3 == 2:
		algoForIterations(2)
		iteration3 = 0
	print("numba 2")


func _on_load_zone_4_body_entered(body: Node3D) -> void:
	# ADDED: client requests server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_request_iteration", 3)
		return

	iteration4 = iteration4 + 1
	if iteration4 == 2:
		algoForIterations(3)
		iteration4 = 0
	print("numba 3")


func _on_load_zone_5_body_entered(body: Node3D) -> void:
	# ADDED: client requests server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(SERVER_ID, "_rpc_request_iteration", 4)
		return

	iteration5 = iteration5 + 1
	if iteration5 == 2:
		algoForIterations(4)
		iteration5 = 0
	print("numba 4")


# ADDED: server receives iteration request
@rpc("any_peer", "reliable")
func _rpc_request_iteration(zone_idx: int) -> void:
	if not multiplayer.is_server():
		return

	match zone_idx:
		0:
			iteration1 += 1
			if iteration1 == 2:
				algoForIterations(0)
				iteration1 = 0
		1:
			iteration2 += 1
			if iteration2 == 2:
				algoForIterations(1)
				iteration2 = 0
		2:
			iteration3 += 1
			if iteration3 == 2:
				algoForIterations(2)
				iteration3 = 0
		3:
			iteration4 += 1
			if iteration4 == 2:
				algoForIterations(3)
				iteration4 = 0
		4:
			iteration5 += 1
			if iteration5 == 2:
				algoForIterations(4)
				iteration5 = 0


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
