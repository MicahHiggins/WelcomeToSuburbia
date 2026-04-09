extends TileMapLayer

@onready var label: Label = $"../../Buttons4See/instr"

var gridSize = 30
var Dict = {}
var Grid = {}
var mask_arr = []

# This is just for visualization, so we don't need drawn_tiles[] here.

func _ready() -> void:
	label.text = "Study the Sigil..."
	
	# --- STEP 1: SETUP THE GRID AND CANVAS ---
	for x in gridSize:
		for y in gridSize:
			# Setup the Grey Grid Lines (Every 5 tiles as per your latest code)
			for i in range(0, 31, 5):
				if i > 0:
					var g_pos1 = Vector2i(x + 20, i)
					var g_pos2 = Vector2i(i + 20, y)
					Grid[g_pos1] = {"Type": "Grid"}
					Grid[g_pos2] = {"Type": "Grid"}
					
					set_cell(g_pos1, 2, Vector2(0, 0), 0)
					set_cell(g_pos2, 2, Vector2(0, 0), 0)
			
			# Setup the White Background
			var pos = Vector2i(x + 20, y)
			Dict[pos] = {"Type": "Blank"}
			set_cell(pos, 0, Vector2i(0, 0), 0)
	
	# --- STEP 2: SHOW THE SPIRAL ---
	_drawing1()

func _drawing1():
	print("Displaying Reference Spiral")
	mask_arr.clear()
	
	# Match the center of the drawing canvas exactly
	var center_x = 35 
	var center_y = 15
	#
	## Spiral parameters - must be identical to the drawing script
	#var steps = 400
	#var growth = 0.08
	#var tightness = 0.25
	#
	#for i in range(steps):
		#var t = i * tightness
		#var r = growth * t
		#
		#var x = center_x + r * cos(t)
		#var y = center_y + r * sin(t)
		#
		#var pic = Vector2i(round(x), round(y))
		#
		## Check if tile is in the playable area and not a grey line
		#if Dict.has(pic) and not Grid.has(pic):
			#if not mask_arr.has(pic):
				#mask_arr.append(pic)
				#
				## PREFILL THE BLACK TILES:
				## This makes the spiral visible so the player can see what to draw.
				#set_cell(pic, 1, Vector2i(0, 0), 0)
				
	var radius = 8
	var thickness = 1.0  # controls how thick the outline is
	for x in range(center_x - radius - 1, center_x + radius + 1):
		for y in range(center_y - radius - 1, center_y + radius + 1):
			var dx = x - center_x
			var dy = y - center_y
			var dist = sqrt(dx * dx + dy * dy)
			
			# Only keep pixels near the edge (empty circle)
			if abs(dist - radius) < thickness:
				var pic = Vector2i(x, y)
				
				if Dict.has(pic) and not Grid.has(pic):
					if not mask_arr.has(pic):
						mask_arr.append(pic)
						set_cell(pic, 1, Vector2i(0, 0), 0)
	var tri_height = 6
	var tri_top_y = center_y - radius - tri_height
	for y in range(tri_top_y, tri_top_y + tri_height):
		var width = (y - tri_top_y) * 2  # triangle expands downward
		for x in range(center_x - width/2, center_x + width/2 + 1):
			var pic = Vector2i(x, y)
			
			if Dict.has(pic) and not Grid.has(pic):
				if not mask_arr.has(pic):
					mask_arr.append(pic)
					set_cell(pic, 1, Vector2i(0, 0), 0)

	print("Observer loaded with ", mask_arr.size(), " tiles.")

# No _process function means the player can't interact with this layer.
