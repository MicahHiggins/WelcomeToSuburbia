extends Node3D


class_name questMarker

static var campbells := false
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_player.play("Move!")
	#visible = false
	#if questMarker.campbells == true:
		#visible = true
	
	
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	#if questMarker.campbells == true:
		#visible = true
	
