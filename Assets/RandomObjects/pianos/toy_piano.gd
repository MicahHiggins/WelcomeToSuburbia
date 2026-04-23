extends Node3D



@onready var piano_failure: AnimationPlayer = $pianoFailure
@onready var track_1: AudioStreamPlayer = $"../../../Sound/Track1"
@onready var drawer_1: AudioStreamPlayer3D = $"../../../Sound/Drawer1"
@onready var drawer_2: AudioStreamPlayer3D = $"../../../Sound/Drawer2"
@onready var move_bookcase: AudioStreamPlayer = $"../../../Sound/moveBookcase"
@onready var move_bat: AudioStreamPlayer = $"../../../Sound/moveBat"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var note_1: AudioStreamPlayer3D = $Audio/note1
@onready var note_2: AudioStreamPlayer3D = $Audio/note2
@onready var note_3: AudioStreamPlayer3D = $Audio/note3
@onready var note_4: AudioStreamPlayer3D = $Audio/note4
@onready var note_5: AudioStreamPlayer3D = $Audio/note5
@onready var note_6: AudioStreamPlayer3D = $Audio/note6
@onready var note_7: AudioStreamPlayer3D = $Audio/note7

@onready var notesArr = [note_1, note_5, note_3, note_7, note_4, note_6, note_2]
@onready var animArr = ["Cube_001Action","Cube_005Action", "Cube_003Action", "Cube_007Action", "Cube_004Action", "Cube_006Action", "Cube_006Action"]

var puzzleArr = [1, 5, 3, 7, 4, 6, 6, 2]
var arrPlay = []

var globalPuzzleChecker := 0
var puzzleFail := false
signal puzzleOneComplete
# Called when the node enters the scene tree for the first time.
#func _on_mousefree_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	## Check for Left Mouse Button Click
	#if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		#print("The object was clicked!")
		# Call whatever logic you want here
var _result_locked := false

func _server_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return -1
	if multiplayer.is_server():
		return multiplayer.get_unique_id()
	var peers := multiplayer.get_peers()
	if peers == null or peers.is_empty():
		return -1
	var best := int(peers[0])
	for p_any in peers:
		var p := int(p_any)
		if p < best:
			best = p
	return best

func puzzleCheck(value: int):
	if _result_locked:
		return

	if globalPuzzleChecker < 7:
		if value == puzzleArr[globalPuzzleChecker] && puzzleFail != true:
			print("Value: ", value)
			print("puzzle: ", puzzleArr[globalPuzzleChecker])
			globalPuzzleChecker += 1
			puzzleFail = false
		else:
			globalPuzzleChecker += 1
			puzzleFail = true
	else:
		print("WAIT!")
		globalPuzzleChecker = 0
		puzzleSolved(puzzleFail)

	print(puzzleFail)

func puzzleSolved(fail: bool):
	print("PuzzleSolved")

	if multiplayer.has_multiplayer_peer():
		var sid := _server_peer_id()
		if multiplayer.is_server():
			_rpc_request_puzzle_solved(fail)
		else:
			if sid > 0:
				rpc_id(sid, "_rpc_request_puzzle_solved", fail)
		return

	_apply_puzzle_result_local(fail)

@rpc("any_peer", "reliable")
func _rpc_request_puzzle_solved(fail: bool) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _result_locked:
		return
	_result_locked = true
	rpc("_rpc_apply_puzzle_result", fail)

@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_puzzle_result(fail: bool) -> void:
	_apply_puzzle_result_local(fail)

func _apply_puzzle_result_local(fail: bool) -> void:
	if fail == true:
		animation_player.stop()
		piano_failure.play("pianoSuccess")
		puzzleFail = false
		
	else:
		puzzleOneComplete.emit()
		piano_failure.play("green")
		
		#audio cue
		track_1.play()
		drawer_1.play()
		drawer_2.play()
		move_bookcase.play()
		%R2SpotLight3D.visible = false
		%R1SpotLight3D.visible = false
		%R2OmniLight3D.visible = false
		%R1OmniLight3D.visible = false
		
		for i in range(7):
			notesArr[i].play()
			animation_player.play(animArr[i])
			await get_tree().create_timer(.15).timeout

func _on_mousefree_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") && body.is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		body.set_process_unhandled_input(false)
		symbol.can_draw = false

func _on_mousefree_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") && body.is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		body.set_process_unhandled_input(true)
		symbol.can_draw = true

func _on_cube_1_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_001Action")
		note_1.play()
		puzzleCheck(1)

func _on_cube_2_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_002Action")
		note_2.play()
		puzzleCheck(2)

func _on_cube_3_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_003Action")
		note_3.play()
		puzzleCheck(3)

func _on_cube_4_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_004Action")
		note_4.play()
		puzzleCheck(4)

func _on_cube_5_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_005Action")
		note_5.play()
		puzzleCheck(5)

func _on_cube_6_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_006Action")
		note_6.play()
		puzzleCheck(6)

func _on_cube_7_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("The object was clicked!")
		animation_player.play("Cube_007Action")
		note_7.play()
		puzzleCheck(7)
