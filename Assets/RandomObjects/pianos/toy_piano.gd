extends Node3D

@onready var piano_result: AnimationPlayer = $pianoResult

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var note_1: AudioStreamPlayer3D = $Audio/note1
@onready var note_2: AudioStreamPlayer3D = $Audio/note2
@onready var note_3: AudioStreamPlayer3D = $Audio/note3
@onready var note_4: AudioStreamPlayer3D = $Audio/note4
@onready var note_5: AudioStreamPlayer3D = $Audio/note5
@onready var note_6: AudioStreamPlayer3D = $Audio/note6
@onready var note_7: AudioStreamPlayer3D = $Audio/note7

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

func puzzleCheck(value: int):
	if globalPuzzleChecker < 7:
		
		if value == puzzleArr[globalPuzzleChecker]:
			globalPuzzleChecker += 1
			puzzleFail = false
			return
		else:
			globalPuzzleChecker += 1
			puzzleFail = true
	else:
		print("WAIT!")
		globalPuzzleChecker = 0
		puzzleSolved(puzzleFail)
		
	

func puzzleSolved(fail: bool):
	print("PuzzleSolved")
	if fail == true:
		pass
	else:
		puzzleOneComplete.emit()
		
		
	
func _on_mousefree_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		body.set_process_unhandled_input(false)
		symbol.can_draw = false


func _on_mousefree_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
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
