extends TileMapLayer
@onready var clear: Button = $"../Clear"
@onready var label: Label = $"../../Buttons/Label"

var gridSize = 30
var Dict = {}
var Grid = {}
var Mask = {}
var mask_arr = []
var drawn_tiles = []

# ADDED: server id
const SERVER_ID: int = 1

# ADDED: delay init until puzzleType is set
var _did_init: bool = false

func rand_num():
	return randi_range(1, 3)

func _ready() -> void:
	# CHANGED: do not randomize puzzleType here (manager/server owns it)
	label.text = "Hello!"
	# ADDED: do not build here; we build once puzzleType is valid

func _process(delta: float) -> void:
	# ADDED: one-time init once puzzleType exists on this peer
	if not _did_init:
		var num := int(GlobalVariables.puzzleType)
		if num >= 1 and num <= 3:
			_build_base_grid()
			_apply_mask_for_type(num)
			_did_init = true

	# Original drawing logic, but now synced
	var tile = local_to_map(get_local_mouse_position())
	if Dict.has(tile) && Input.is_action_pressed("use-attack") && !Grid.has(tile):
		_request_draw_tile(tile)

# ADDED: request draw (client->server, server->all). Singleplayer applies locally.
func _request_draw_tile(tile: Vector2i) -> void:
	if drawn_tiles.has(tile):
		return

	if not multiplayer.has_multiplayer_peer():
		_apply_draw_tile(tile)
		return

	if multiplayer.is_server():
		_rpc_apply_draw(tile)
	else:
		var mp: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		rpc_id(SERVER_ID, "_rpc_request_draw", tile)

@rpc("any_peer", "reliable")
func _rpc_request_draw(tile: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	_rpc_apply_draw(tile)

@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_draw(tile: Vector2i) -> void:
	_apply_draw_tile(tile)

# ADDED: actual local apply
func _apply_draw_tile(tile: Vector2i) -> void:
	set_cell(tile, 1, Vector2i(0, 0), 0)
	drawn_tiles.append(tile)

func _on_clear_pressed() -> void:
	# CHANGED: clear is synced too
	if not multiplayer.has_multiplayer_peer():
		_apply_clear()
		return

	if multiplayer.is_server():
		_rpc_apply_clear()
	else:
		var mp: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		rpc_id(SERVER_ID, "_rpc_request_clear")

@rpc("any_peer", "reliable")
func _rpc_request_clear() -> void:
	if not multiplayer.is_server():
		return
	_rpc_apply_clear()

@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_clear() -> void:
	_apply_clear()

func _apply_clear() -> void:
	drawn_tiles.clear()
	_build_base_grid()

	# Rebuild mask array too (so button check still works)
	mask_arr.clear()
	var num := int(GlobalVariables.puzzleType)
	if num >= 1 and num <= 3:
		_apply_mask_for_type(num)

func _build_base_grid() -> void:
	Dict.clear()
	Grid.clear()

	for x in gridSize:
		for y in gridSize:
			for i in range(0, 30, 10):
				if i > 0:
					var grid = Vector2i(x + 20, i)
					var grid2 = Vector2i(i + 20, y)
					Grid[grid] = {"Type": "Grid"}
					Grid[grid2] = {"Type": "Grid"}

					set_cell(grid, 2, Vector2(0, 0), 0)
					set_cell(grid2, 2, Vector2(0, 0), 0)

			var pos = Vector2i(x + 20, y)
			Dict[pos] = {"Type": "Blank"}
			set_cell(pos, 0, Vector2i(0, 0), 0)

func _apply_mask_for_type(num: int) -> void:
	mask_arr.clear()
	match num:
		1:
			_drawing1()
		2:
			_drawing2()
		3:
			_drawing3()

func _drawing1():
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x + 20, eyes)
			mask_arr.append(pic)
			var pic2 = Vector2i(eyes + 20, x)
			mask_arr.append(pic2)

func _drawing2():
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x + 20, eyes)
			mask_arr.append(pic)
			var pic2 = Vector2i(x + 20, eyes + 20)
			mask_arr.append(pic2)

func _drawing3():
	var eyes = 5
	for x in gridSize:
		if x != 10 && x != 20:
			var pic = Vector2i(x + 20, eyes)
			mask_arr.append(pic)

func _on_button_pressed() -> void:
	var count := 0.0
	var perc := 0.0
	var mask_size := float(mask_arr.size())
	if mask_size <= 0.0:
		label.text = "No puzzle loaded."
		return

	for i in mask_arr.size():
		for j in drawn_tiles.size():
			if mask_arr[i] == drawn_tiles[j]:
				count += 1.0

	perc = count / mask_size

	label.text = "Calculating Results."
	await get_tree().create_timer(0.3).timeout
	label.text = "Calculating Results.."
	await get_tree().create_timer(0.3).timeout
	label.text = "Calculating Results..."
	await get_tree().create_timer(0.3).timeout

	if perc * 100.0 >= 60.0:
		label.text = "You Win:  %.2f" % perc
	else:
		label.text = "You Lose: %.2f" % perc
