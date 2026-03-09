extends Node3D
@onready var drawing: Node2D = $Drawing
@onready var seeing: Node2D = $Seeing
@onready var exit: Button = $Buttons/Exit
@onready var label: Label = $Buttons/Label
@onready var button: Button = $Buttons/Button
@onready var clear: Button = $Buttons/Clear
#@onready var puzzle_draw: Node2D = $Drawing
#@onready var puzzle_see: Node2D = $Seeing

@onready var buttons: Control = $Buttons

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#GlobalVariables.puzzleType = randi_range(1, 3)
	print("NUMM:, ", GlobalVariables.puzzleType)

func randPuzzle():
	GlobalVariables.puzzleType = randi_range(1, 3)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass


func _on_obs_area_body_entered(body: Node3D) -> void:
	print("TESTETES")
	if body.is_multiplayer_authority():
		print("IN")
		seeing.visible = true
		buttons.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		#exit.visible = true
		#puzzle_see.visible = true

func _on_obs_area_body_exited(body: Node3D) -> void:
		if body.is_multiplayer_authority():
			seeing.visible = false
			#exit.visible = false
			#puzzle_see.visible = false
			buttons.visible = false
			#


func _on_do_area_body_entered(body: Node3D) -> void:
		if body.is_multiplayer_authority():
			drawing.visible = true
			buttons.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		#exit.visible = true


func _on_do_area_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority():
			drawing.visible = false
			#exit.visible = false
			#puzzle_see.visible = false
			buttons.visible = false
