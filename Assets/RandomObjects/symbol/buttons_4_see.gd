extends Control

@onready var instr: Label = $instr
@onready var buttons_4_see: Control = $"."
#@onready var seeing: TileMapLayer = $"../Seeing/seeing"
@onready var seeing: Node2D = $"../Seeing"



func _ready():
	buttons_4_see.visible = false
	seeing.visible = false

func _on_obs_area_body_entered(body: Node3D) -> void:
	buttons_4_see.visible = true
	seeing.visible = true


func _on_obs_area_body_exited(body: Node3D) -> void:
	buttons_4_see.visible = false
	seeing.visible = false
