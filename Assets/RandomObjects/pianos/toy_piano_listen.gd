extends Node3D


@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2



@onready var collision_shape_3d: CollisionShape3D = $Cube/Area3D/CollisionShape3D

@onready var note_1: AudioStreamPlayer3D = $Audio/note1
@onready var note_2: AudioStreamPlayer3D = $Audio/note2
@onready var note_3: AudioStreamPlayer3D = $Audio/note3
@onready var note_4: AudioStreamPlayer3D = $Audio/note4
@onready var note_5: AudioStreamPlayer3D = $Audio/note5
@onready var note_6: AudioStreamPlayer3D = $Audio/note6
@onready var note_7: AudioStreamPlayer3D = $Audio/note7
@onready var notesArr = [note_1, note_5, note_3, note_7, note_4, note_6, note_6, note_2]
@onready var animArr = ["Cube_001Action","Cube_005Action", "Cube_003Action", "Cube_007Action", "Cube_004Action", "Cube_006Action",
 "Cube_006Action", "Cube_002Action"]

signal puzzleOneComplete


var puzzleArr = [1, 5, 3, 7, 4, 6, 6, 2]

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





func _on_area_3d_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		collision_shape_3d.set_deferred("disabled", true)
		for i in range(8):
			notesArr[i].play()
			animation_player_2.stop()
			animation_player_2.play(animArr[i])
			await get_tree().create_timer(1).timeout
		collision_shape_3d.set_deferred("disabled", false)
