extends Node
@onready var join: Button = $CanvasLayer/Join
@onready var quit_2: Button = $CanvasLayer/quit2
@onready var ui_click: AudioStreamPlayer = $"../UI Sounds/UiClick"
@onready var page_flip: AudioStreamPlayer = $"../UI Sounds/PageFlip"



func _ready() -> void:
	GlobalVariables.menuMusic.emit()
	AudioManager.gameStart.emit()
	


func _input(event: InputEvent) -> void:
	pass
