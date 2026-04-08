extends TileMapLayer

@onready var clear: Button = $"../Clear"
@onready var enter: Button = $"../../Buttons4Draw/Enter"
@onready var label: Label = $"../../Buttons4Draw/Label"

var gridSize = 30
var Dict = {}
var Grid = {}
var mask_arr = []
var drawn_tiles = []

var can_draw: bool = true

func _ready() -> void:
	mask_arr.clear()
	label.text = "Hello!"
	
	# --- STEP 1: BUILD THE GRID DATA FIRST ---
	# We must fill Dict and Grid before calling _drawing1
	for x in gridSize:
		for y in gridSize:
			# Setup the Grey Grid Lines (every 10 tiles)
			for i in range(0, 31, 10):
				if i > 0:
					var g_pos1 = Vector2i(x + 20, i)
					var g_pos2 = Vector2i(i + 20, y)
					Grid[g_pos1] = {"Type": "Grid"}
					Grid[g_pos2] = {"Type": "Grid"}
			
			# Setup the White Drawing Area
			var pos = Vector2i(x + 20, y)
			Dict[pos] = {"Type": "Blank"}
	
	# --- STEP 2: GENERATE THE SPIRAL MASK ---
	# Now that Dict exists, this function will find the tiles it needs
	_drawing1()
	
	# --- STEP 3: INITIALIZE THE VISUALS ---
	_on_clear_pressed()

func _process(_delta: float) -> void:
	# Assuming 'symbol' is a global or external reference; 
	# if it's local, ensure it's defined. Using 'can_draw' as a fallback.
	if not can_draw: 
		return 
		
	var tile = local_to_map(get_local_mouse_position())
	
	# Only draw if it's a valid tile and NOT a grid line
	if Dict.has(tile) and Input.is_action_pressed("use-attack") and not Grid.has(tile):
		set_cell(tile, 1, Vector2i(0, 0), 0) # Draw black tile
		if not drawn_tiles.has(tile):
			drawn_tiles.append(tile)

func _drawing1():
	print("Generating Spiral Mask...")
	mask_arr.clear()
	
	# Center of your 30x30 board (X is shifted by 20)
	var center_x = 35 
	var center_y = 15
	
	# Spiral settings for a clean shape
	var steps = 800      # High steps to prevent gaps in the line
	var growth = 0.08    # How fast the arms spread
	var tightness = 0.25 # How many loops it makes
	
	for i in range(steps):
		var t = i * tightness
		var r = growth * t
		
		# Polar to Cartesian math
		var x = center_x + r * cos(t)
		var y = center_y + r * sin(t)
		
		var pic = Vector2i(round(x), round(y))
		
		# Check if tile is in the playable area and not a grey line
		if Dict.has(pic) and not Grid.has(pic):
			if not mask_arr.has(pic):
				mask_arr.append(pic)

	print("Spiral logic complete. Tiles to match: ", mask_arr.size())

func _on_clear_pressed() -> void:
	print("Clearing Canvas")
	drawn_tiles.clear()
	
	# Reset the visual tiles on the map
	for pos in Dict:
		set_cell(pos, 0, Vector2i(0, 0), 0) # Set to white
	
	for pos in Grid:
		set_cell(pos, 2, Vector2(0, 0), 0) # Set to grey grid

func _on_button_pressed() -> void:
	print("Calculating Results...")
	
	var mask_size = mask_arr.size()
	
	# Safety Check for -nan
	if mask_size == 0:
		label.text = "Error: Mask not generated"
		return

	var count : float = 0.0
	
	# Compare player drawing to the spiral mask
	for tile in mask_arr:
		if drawn_tiles.has(tile):
			count += 1.0
	
	var perc = count / float(mask_size)
	var percentage = perc * 100.0

	label.text = "Calculating Results..."
	await get_tree().create_timer(1.0).timeout 
	
	if percentage >= 60.0:
		label.text = "You Win: %.2f%%" % percentage
	else:
		label.text = "You Lose: %.2f%%" % percentage

func _on_enter_pressed() -> void:
	_on_button_pressed()
