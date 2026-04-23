extends Node
@onready var join: Button = $CanvasLayer/Join
@onready var quit_2: Button = $CanvasLayer/quit2


func _ready() -> void:
	GlobalVariables.menuMusic.emit()
	AudioManager.gameStart.emit()
