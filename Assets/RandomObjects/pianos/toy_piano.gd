extends Node3D


@onready var animation_player: AnimationPlayer = $AnimationPlayer


signal puzzleOneComplete
# Called when the node enters the scene tree for the first time.
#func _on_mousefree_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	## Check for Left Mouse Button Click
	#if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		#print("The object was clicked!")
		# Call whatever logic you want here


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
			


func _on_cube_2_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("The object was clicked!")
			animation_player.play("Cube_002Action")


func _on_cube_3_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("The object was clicked!")
			animation_player.play("Cube_003Action")


func _on_cube_4_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("The object was clicked!")
			animation_player.play("Cube_004Action")


func _on_cube_5_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("The object was clicked!")
			animation_player.play("Cube_005Action")


func _on_cube_6_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("The object was clicked!")
			animation_player.play("Cube_006Action")


func _on_cube_7_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("The object was clicked!")
			animation_player.play("Cube_007Action")
			puzzleOneComplete.emit()
