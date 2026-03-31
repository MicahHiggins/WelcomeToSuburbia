extends Node3D

class_name symbol


@onready var drawing: Node2D = $Drawing
@onready var seeing: Node2D = $Seeing
@onready var exit: Button = $Buttons/Exit
@onready var label: Label = $Buttons/Label
@onready var button: Button = $Buttons/Button
@onready var clear: Button = $Buttons/Clear
#@onready var puzzle_draw: Node2D = $Drawing
#@onready var puzzle_see: Node2D = $Seeing

@onready var interact: Label = $interact

@onready var buttons: Control = $Buttons



static var can_draw: bool = true
var in_area = false
var see = false
var do = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	see = false
	do = false
	randPuzzle()
	print("NUMM:, ", GlobalVariables.puzzleType)
	seeing.visible = false

	buttons.visible = false
	drawing.visible = false
	buttons.visible = false

func randPuzzle():
	GlobalVariables.puzzleType = randi_range(1, 3)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#print(in_area)
	if in_area == true:
		#print("HU")
		interact.visible = true
	else: 
		interact.visible = false
		

func _input(event: InputEvent) -> void:
	#print(see)
	if in_area == true && event.is_action("interact") && see == true:
		seeing.visible = true
		buttons.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif in_area == true && event.is_action_pressed("interact") && do == true:
		drawing.visible = true
		buttons.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		
		
		
		
func _on_obs_area_body_entered(body: Node3D) -> void:
	print("TESTETES")
	if body.is_multiplayer_authority() && body.is_in_group("player"):
		in_area = true
		print("IN")
		see = true
		#exit.visible = true
		#puzzle_see.visible = true

func _on_obs_area_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority() && body.is_in_group("player"):
		in_area = false
		see = false
		


func _on_do_area_body_entered(body: Node3D) -> void:
	if body.is_multiplayer_authority() && body.is_in_group("player"):
		in_area = true
		do = true

		#exit.visible = true


func _on_do_area_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority() && body.is_in_group("player"):
		in_area = false
		do = false


func _on_exit_pressed() -> void:
	seeing.visible = false
	buttons.visible = false
	drawing.visible = false
	buttons.visible = false
