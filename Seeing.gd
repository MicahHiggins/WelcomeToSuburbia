extends TileMapLayer
@onready var label: Label = $"../../Buttons/Label"

var gridSize = 30
var Dict = {}
var Grid = {}
var Mask = {}
var mask_arr = []
var drawn_tiles = []

func rand_num():
	return randi_range(1, 3)

func _ready() -> void:
	label.text = "Hello!"

	# ADDED: in multiplayer, the puzzleType comes from the server/manager RPC.
	# If the client runs _ready before that RPC arrives, it can build the wrong puzzle.
	# Wait briefly until puzzleType is in the expected range.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var tries := 0
		while (GlobalVariables.puzzleType < 1 or GlobalVariables.puzzleType > 3) and tries < 30:
			tries += 1
			await get_tree().process_frame

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

	var num = GlobalVariables.puzzleType
	match(num):
		1:
			_drawing1()
		2:
			_drawing2()
		3:
			_drawing3()

func _drawing1():
	print("d1")
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x+20, eyes)
			mask_arr.append(pic)
			var pic2 = Vector2i(eyes+20, x)
			set_cell(pic, 1, Vector2i(0, 0), 0)
			mask_arr.append(pic2)
			set_cell(pic2, 1, Vector2i(0, 0), 0)

func _drawing2():
	print("d2")
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x+20, eyes)
			mask_arr.append(pic)
			var pic2 = Vector2i(x+20, eyes+20)
			set_cell(pic, 1, Vector2i(0, 0), 0)
			mask_arr.append(pic2)
			set_cell(pic2, 1, Vector2i(0, 0), 0)

func _drawing3():
	print("d3")
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x+20, eyes)
			mask_arr.append(pic)
			set_cell(pic, 1, Vector2i(0, 0), 0)
