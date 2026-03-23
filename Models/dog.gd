extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var dog: Node3D = $"."

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_player.play("DogWalk")
	questHub.iteration_changed.connect(iterationChange)

func iterationChange(value: int):
	
	#Dog disappears at iteration 3 (2), "teleports" to random location (house near abigail)
	if value >= 2:
		dog.visible = false
	else:
		dog.visible = true
		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
