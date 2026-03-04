extends Node3D

@onready var test: Node2D = $CanvasLayer/Control/test

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_obs_area_body_entered(body: Node3D) -> void:
	pass # Replace with function body.
