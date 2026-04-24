extends Node3D

@onready var npc_bob: NPC = $NPC_bob
@onready var dog: Node3D = $Dog
@onready var quest_marker_blue: Node3D = $QuestMarkerBlue
@onready var collision_shape_3d: CollisionShape3D = $Area3D/CollisionShape3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_player.play("dogSpin")
	questHub.iteration_changed.connect(iterationChanged)
	npc_bob.visible = false
	dog.visible = false
	quest_marker_blue.visible = false
	collision_shape_3d.set_deferred("disabled", true)

	

			



func iterationChanged(value: int):
	if value >= 4:
		collision_shape_3d.set_deferred("disabled", false)
		dog.visible = true
		npc_bob.visible = true
		quest_marker_blue.visible = true
		
		
		
		await get_tree().create_timer(3.0).timeout
		collision_shape_3d.set_deferred("disabled", false)
		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass




func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") && body.is_multiplayer_authority():
		quest_marker_blue.visible = false
		
