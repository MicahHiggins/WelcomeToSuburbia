extends TileMapLayer

@onready var clear: Button = $"../Clear"
@onready var enter: Button = $"../../Buttons4Draw/Enter"
@onready var label: Label = $"../../Buttons4Draw/Label"
@onready var win: AudioStreamPlayer = $"../../Sounds/win"
@onready var lose: AudioStreamPlayer = $"../../Sounds/lose"
@onready var cabinet: AudioStreamPlayer = $"../../Sounds/cabinet"

var gridSize = 30
var Dict = {}
var Grid = {}
var mask_arr = []
var drawn_tiles = []

var can_draw: bool = true

signal puzzleTwoComplete

const SERVER_ID: int = 1
var _puzzle_done: bool = false

func _ready() -> void:
	mask_arr.clear()
	label.text = "Hello!"

	for x in gridSize:
		for y in gridSize:
			for i in range(0, 31, 10):
				if i > 0:
					var g_pos1 = Vector2i(x + 20, i)
					var g_pos2 = Vector2i(i + 20, y)
					Grid[g_pos1] = {"Type": "Grid"}
					Grid[g_pos2] = {"Type": "Grid"}

			var pos = Vector2i(x + 20, y)
			Dict[pos] = {"Type": "Blank"}

	_drawing1()
	_on_clear_pressed()

func _process(_delta: float) -> void:
	if not can_draw:
		return

	var tile = local_to_map(get_local_mouse_position())

	if Dict.has(tile) and Input.is_action_pressed("use-attack") and not Grid.has(tile):
		set_cell(tile, 1, Vector2i(0, 0), 0)
		if not drawn_tiles.has(tile):
			drawn_tiles.append(tile)

func _drawing1():
	print("Generating Spiral Mask...")
	mask_arr.clear()

	var center_x = 35
	var center_y = 15

	var radius = 8
	var thickness = 1.0
	for x in range(center_x - radius - 1, center_x + radius + 1):
		for y in range(center_y - radius - 1, center_y + radius + 1):
			var dx = x - center_x
			var dy = y - center_y
			var dist = sqrt(dx * dx + dy * dy)

			if abs(dist - radius) < thickness:
				var pic = Vector2i(x, y)

				if Dict.has(pic) and not Grid.has(pic):
					if not mask_arr.has(pic):
						mask_arr.append(pic)
						set_cell(pic, 1, Vector2i(0, 0), 0)

	var tri_height = 6
	var tri_top_y = center_y - radius - tri_height
	for y in range(tri_top_y, tri_top_y + tri_height):
		var width = (y - tri_top_y) * 2
		for x in range(center_x - width / 2, center_x + width / 2 + 1):
			var pic = Vector2i(x, y)

			if Dict.has(pic) and not Grid.has(pic):
				if not mask_arr.has(pic):
					mask_arr.append(pic)
					set_cell(pic, 1, Vector2i(0, 0), 0)

	print("Spiral logic complete. Tiles to match: ", mask_arr.size())

func _on_clear_pressed() -> void:
	print("Clearing Canvas")
	drawn_tiles.clear()

	for pos in Dict:
		set_cell(pos, 0, Vector2i(0, 0), 0)

	for pos in Grid:
		set_cell(pos, 2, Vector2(0, 0), 0)

func _on_button_pressed() -> void:
	print("Calculating Results...")

	var mask_size = mask_arr.size()
	if mask_size == 0:
		label.text = "Error: Mask not generated"
		return

	var count: float = 0.0
	for tile in mask_arr:
		if drawn_tiles.has(tile):
			count += 1.0

	var perc = count / float(mask_size)
	var percentage = perc * 100.0

	label.text = "Calculating Results..."
	await get_tree().create_timer(1.0).timeout 
	
	if percentage >= 60.0:
		label.text = "You Win: %.2f" % percentage
		win.play()
		cabinet.play()
		puzzleTwoComplete.emit()


		_request_puzzle_two_complete()
		




	else:
		lose.play()
		label.text = "You Lose: %.2f%%" % percentage

func _on_enter_pressed() -> void:
	_on_button_pressed()

func _request_puzzle_two_complete() -> void:
	if _puzzle_done:
		return

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_mark_puzzle_two_complete()
		else:
			rpc_id(SERVER_ID, "_rpc_request_puzzle_two_complete")
	else:
		_puzzle_done = true
		puzzleTwoComplete.emit()

@rpc("any_peer", "reliable")
func _rpc_request_puzzle_two_complete() -> void:
	if not multiplayer.is_server():
		return
	_server_mark_puzzle_two_complete()

func _server_mark_puzzle_two_complete() -> void:
	if _puzzle_done:
		return
	_puzzle_done = true
	puzzleTwoComplete.emit()
	rpc("_rpc_puzzle_two_complete_all")

@rpc("any_peer", "call_local", "reliable")
func _rpc_puzzle_two_complete_all() -> void:
	if _puzzle_done:
		return
	_puzzle_done = true
	puzzleTwoComplete.emit()
