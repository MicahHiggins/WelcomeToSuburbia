extends TileMapLayer
@onready var clear: Button = $"../Clear"
@onready var label: Label = $"../../Buttons4See/Label"



var gridSize = 30
var Dict = {}
var Grid = {}
#var Mask = {}
var mask_arr = []
var drawn_tiles = []



var can_draw: bool = true

func rand_num():
	return randi_range(1, 3)
	
func _ready() -> void:
	mask_arr.clear()
	label.text = "Hello!"
	#print("num: ", num)
	_drawing1()

			
	
	for x in gridSize:
		for y in gridSize:
			for i in range(0, 30, 10):
				if i > 0:
					var grid = Vector2i(x+20, i)
					var grid2 = Vector2i(i+20, y)
					Grid[grid] = {
						"Type": "Grid"
					}
					Grid[grid2] = {
						"Type": "Grid"
					}
					
					set_cell(grid, 2, Vector2(0, 0), 0)
					set_cell(grid2, 2, Vector2(0, 0), 0)
			
			var pos = Vector2i(x+20, y)
			Dict[pos] = {
				"Type": "Blank"
			}
				
			set_cell(Vector2i(x+20, y), 0, Vector2i(0, 0), 0)
	_on_clear_pressed()

		

func _process(delta: float) -> void:
	
	if not symbol.can_draw: 
		return # Exit early if drawing is disabled
	var tile = local_to_map(get_local_mouse_position())
	#print(tile)
	#var tile2 = local_to_map(get_local_mouse_position()) + Vector2i(1, 1)
	
	#print(tile)
	if Dict.has(tile) && Input.is_action_pressed("use-attack") && !Grid.has(tile):
		#print(tile)
		set_cell(tile, 1, Vector2i(0, 0), 0)
		#set_cell(tile2, 1, Vector2i(0, 0), 0)
		if not drawn_tiles.has(tile):
			drawn_tiles.append(tile)
			print("Added tile: ", tile, " | Total tiles drawn: ", drawn_tiles.size())


func _on_clear_pressed() -> void:
	print("CLEAR")
	
	drawn_tiles.clear()
	for x in gridSize:
		for y in gridSize:
			for i in range(0, 30, 10):
				if i > 0:
					var grid = Vector2i(x+20, i)
					var grid2 = Vector2i(i+20, y)
					Grid[grid] = {
						"Type": "Grid"
					}
					Grid[grid2] = {
						"Type": "Grid"
					}
					
					set_cell(Vector2i(x+20, i), 2, Vector2(0, 0), 0)
					set_cell(Vector2i(i+20, y), 2, Vector2(0, 0), 0)
			
			var pos = Vector2i(x+20, y)
			Dict[pos] = {
				"Type": "Blank"
			}
				
			set_cell(Vector2i(x+20, y), 0, Vector2i(0, 0), 0)

func _drawing1():
	print("d1")
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x+20, eyes)
			mask_arr.append(pic)
			var pic2 = Vector2i(eyes+20, x)
			#set_cell(pic, 1, Vector2i(0, 0), 0)
			mask_arr.append(pic2)
			#set_cell(pic2, 1, Vector2i(0, 0), 0)



func _on_button_pressed() -> void:
	print("On button pressed: ", GlobalVariables.puzzleType)
	var count := 0.00
	var perc := 0.00
	var mask_size = mask_arr.size()
	print(mask_arr.size())
	for i in mask_arr.size(): 
		for j in drawn_tiles.size():
			if mask_arr[i] == drawn_tiles[j]:
				print("On button pressed: ", GlobalVariables.puzzleType)
				count = count + 1
				#print("count")
	
	count = count
	perc = count/mask_size
	#print(mask_size)
	#print(count)
	#print(perc)
	label.text = "Calculating Results..."
	await get_tree().create_timer(1).timeout 
	var percentage = perc * 100
	print(percentage)
	if percentage >= 60:
		#print("test")
		label.text = "You Win:  %.2f" % perc
	else:
		#print("FUCk")
		label.text = "You Lose: %.2f" % perc
	
		
