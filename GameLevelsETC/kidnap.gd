extends Node3D

@onready var cohesion: AnimationPlayer = $Cohesion

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_toy_piano_puzzle_one_complete() -> void:
	cohesion.play("puzzle1Complete")
