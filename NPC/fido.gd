extends  CharacterBody3D

class_name fido_dog

@onready var fido: CharacterBody3D = $"."
@onready var animation_player: AnimationPlayer = $AnimationPlayer

@onready var area_3d: Area3D = $"../Area3D"

@onready var fido_collision: CollisionShape3D = $"../Area3D/FidoCollision"

static var fido_toggle := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#collision_shape_3d.set_deferred("disabled", true)
	questHub.iteration_changed.connect(iterationChange)
	fido.visible = false
	fido_collision.set_deferred("disabled", true)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



func iterationChange(value: int):
	print("FIDO DETECTED!")
	
	#If on iteration 3, turn fido on
	if value == 2:
		print(fido.global_position)
		fido_collision.set_deferred("disabled", false)
		print("FIDO ON!")
		fido.visible = true
		animation_player.play("Bark")
	if value > 5:
		fido.visible = false
		fido_collision.set_deferred("disabled", true)
		#animation_player.stop()




func _on_area_3d_body_entered(body: Node3D) -> void:
	
	if fido_toggle == true:
		return 
	if body.is_in_group("player"):
		print("Fido: Player Detected")
		fido_toggle = true
		uiStuff.ObjectiveToggle = true
		
