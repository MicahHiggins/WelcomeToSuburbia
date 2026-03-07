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


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	worldBlocks2 = [world_block_1, world_block_2, world_block_3, 
	world_block_4, world_block_5]
	#print(worldBlocks2[1])


## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
	
func algoForIterations(worldBlocks):
	if GlobalVariables.algoDebug == true:
		return
	#print(worldBlocks2[1])
	#print("TESTESTES")
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
				GlobalVariables.iterations +=1
				#print("EST")
				#print(counter)
				#print(worldBlocks2[i].position.x)
				currentWorldBlockIterationX = worldBlocks2[worldBlocks].global_position.x
				worldBlocks2[i].global_position = currentWorldBlockIteration
				worldBlocks2[i].global_position.x = currentWorldBlockIterationX + displacement
				displacement = -DISPLACEMENT
				counter = counter + 1
				#print(displacement)
				
			else:
				#print("F")
				#print(worldBlocks2[i].position.z)
				worldBlocks2[i].global_position = currentWorldBlockIteration
				currentWorldBlockIterationZ = worldBlocks2[worldBlocks].global_position.z
				worldBlocks2[i].global_position.z = currentWorldBlockIterationZ + displacement
				displacement = DISPLACEMENT
				counter = counter + 1
				#print(displacement)
				
	GlobalVariables.algoDebug = false

	


func _on_load_zone_1_body_entered(body: Node3D) -> void:
	print(body)
	iteration1 = iteration1 + 1
	#print(iteration1)
	#print(player)
	if iteration1 == 2:
		#GlobalVariables.algoDebug = true
		algoForIterations(0)
		iteration1 = 0
	#print(GlobalVariables)
	print("numba 0")


func _on_load_zone_2_body_entered(body: Node3D) -> void:
	iteration2 = iteration2 + 1
	#print(player)
	#print(iteration2)
	if iteration2 == 2:
		#GlobalVariables.algoDebug = true
		algoForIterations(1)
		iteration2 = 0
	print("numba 1")


func _on_load_zone_3_body_entered(body: Node3D) -> void:
	iteration3 = iteration3 + 1
	#print(player)
	#print(iteration3)
	if iteration3 == 2:
		#GlobalVariables.algoDebug = true
		algoForIterations(2)
		iteration3 = 0
	print("numba 2")


func _on_load_zone_4_body_entered(body: Node3D) -> void:
	iteration4 = iteration4 + 1
	#print(player)
	#print(iteration4)
	if iteration4 == 2:
		#GlobalVariables.algoDebug = true
		algoForIterations(3)
		iteration4 = 0
	print("numba 3")


func _on_load_zone_5_body_entered(body: Node3D) -> void:
	iteration5 = iteration5 + 1
	#print(iteration5)
	if iteration5 == 2:
		#GlobalVariables.algoDebug = true
		algoForIterations(4)
		iteration5 = 0
	print("numba 4")



func _on_load_zone_1_body_exited(body: Node3D) -> void:
	iteration1 = 0


func _on_load_zone_2_body_exited(body: Node3D) -> void:
	iteration2 = 0


func _on_load_zone_3_body_exited(body: Node3D) -> void:
	iteration3 = 0


func _on_load_zone_4_body_exited(body: Node3D) -> void:
	iteration4 = 0


func _on_load_zone_5_body_exited(body: Node3D) -> void:
	iteration5 = 0
