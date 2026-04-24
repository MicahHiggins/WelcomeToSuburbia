extends Node3D

@onready var area_det: Area3D = $AreaDet

@onready var wailing: AudioStreamPlayer3D = $wailing
@onready var collision_shape_3d: CollisionShape3D = $AreaDet/CollisionShape3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var quest_marker_blue: Node3D = $QuestMarkerBlue

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationProgress)
	
	collision_shape_3d.set_deferred("disabled", true)
	quest_marker_blue.visible = false
	
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func iterationProgress(value: int):
	if value == 3:
		quest_marker_blue.visible = true
		collision_shape_3d.set_deferred("disabled", false)
	
		

func _on_area_det_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") != null:
		
		collision_shape_3d.set_deferred("disabled", false)
		quest_marker_blue.visible = false
		animation_player.play("move")
		wailing.play()
