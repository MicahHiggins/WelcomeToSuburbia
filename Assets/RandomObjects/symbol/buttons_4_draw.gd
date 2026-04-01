extends Control

@onready var buttons_4_draw: Control = $"."
#@onready var interact: Label = $"../interact"
@onready var drawing: TileMapLayer = $"../Drawing/drawing"
@onready var seeing: TileMapLayer = $"../Seeing/seeing"

var in_area := false


signal draw_it(toggle: bool)

func _ready() -> void:
	buttons_4_draw.visible = false
	drawing.visible = false
	seeing.visible = false



func _on_do_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		buttons_4_draw.visible = true
		drawing.visible = true
		print("Do: In")
		draw_it.emit(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_do_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		buttons_4_draw.visible = false
		print("Do: Out")
		draw_it.emit(true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
