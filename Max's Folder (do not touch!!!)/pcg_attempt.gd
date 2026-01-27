extends Node3D

@onready var world_block_1: Node3D = $worldBlock1
@onready var world_block_2: Node3D = $worldBlock2
@onready var world_block_3: Node3D = $worldBlock3
@onready var world_block_4: Node3D = $worldBlock4
@onready var world_block_5: Node3D = $worldBlock5

var prevWB
var worldBlocks2: Array[Node3D]

const DISPLACEMENT = 32

## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	worldBlocks2 = [world_block_1, world_block_2, world_block_3, 
	world_block_4, world_block_5]
	print(worldBlocks2[1])


## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
	
func algoForIterations(worldBlocks):
	print(worldBlocks2[1])
	print("TESTESTES")
	var currentWorldBlockIteration = worldBlocks2[worldBlocks].global_position
	var currentWorldBlockIterationZ = worldBlocks2[worldBlocks].global_position.z
	var currentWorldBlockIterationX = worldBlocks2[worldBlocks].global_position.x
	var displacement = DISPLACEMENT
	
	
	var counter = 0
	for i in range(5):
		
		if i != worldBlocks:
			
			if counter < 2:
				#print("EST")
				print(counter)
				print(worldBlocks2[i].position.x)
				currentWorldBlockIterationX = worldBlocks2[worldBlocks].global_position.x
				worldBlocks2[i].global_position = currentWorldBlockIteration
				worldBlocks2[i].global_position.x = currentWorldBlockIterationX + displacement
				displacement = -DISPLACEMENT
				counter = counter + 1
				print(displacement)
				
			else:
				#print("F")
				print(worldBlocks2[i].position.z)
				worldBlocks2[i].global_position = currentWorldBlockIteration
				currentWorldBlockIterationZ = worldBlocks2[worldBlocks].global_position.z
				worldBlocks2[i].global_position.z = currentWorldBlockIterationZ + displacement
				displacement = DISPLACEMENT
				counter = counter + 1
				print(displacement)
				
	

	


func _on_load_zone_1_body_entered(body: Node3D) -> void:
	algoForIterations(0)
	print("numba 0")


func _on_load_zone_2_body_entered(body: Node3D) -> void:
	algoForIterations(1)
	print("numba 1")


func _on_load_zone_3_body_entered(body: Node3D) -> void:
	algoForIterations(2)
	print("numba 2")


func _on_load_zone_4_body_entered(body: Node3D) -> void:
	algoForIterations(3)
	print("numba 3")


func _on_load_zone_5_body_entered(body: Node3D) -> void:
	algoForIterations(4)
	print("numba 4")
