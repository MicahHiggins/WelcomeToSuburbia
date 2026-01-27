extends CanvasLayer

var player : CharacterBody3D

func _ready():
	player = get_parent()

func _physics_process(delta: float):
	$Item1Label.text = str(player.inventory[0])
