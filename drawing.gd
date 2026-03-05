extends TileMapLayer


var gridSize = 20
var Dict = {}
var drawn_tiles = []

func _ready() -> void:
	for x in gridSize:
		for y in gridSize:
			var pos = Vector2i(x+20, y)
			Dict[pos] = {
				"Type": "Blank"
			}
				
			set_cell(Vector2i(x+20, y), 0, Vector2i(0, 0), 0)
			
			

		print(Dict)



func _process(delta: float) -> void:
	var tile = local_to_map(get_local_mouse_position())
	
	#print(tile)
	if Dict.has(tile) && Input.is_action_pressed("use-attack"):
		#print(tile)
		set_cell(tile, 1, Vector2i(0, 0), 0)
		if not drawn_tiles.has(tile):
			drawn_tiles.append(tile)
			print("Added tile: ", tile, " | Total tiles drawn: ", drawn_tiles.size())
