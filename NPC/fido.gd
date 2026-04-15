extends  CharacterBody3D

class_name fido_dog
#@onready var quest_marker_: questMarker = $"QuestMarker!"
@onready var fido: CharacterBody3D = $"."
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var area_3d: Area3D = $"../Area3D"
@onready var fido_collision: CollisionShape3D = $"../Area3D/FidoCollision"
@onready var quest_marker_: Node3D = $QuestMarkerBlue

static var fido_toggle := false


@onready var bark_2: AudioStreamPlayer3D = $Bark2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#found_fido_early = false
	#collision_shape_3d.set_deferred("disabled", true)
	questHub.iteration_changed.connect(iterationChange)
	questHub.campbellQuest.connect(campbellProgression)
	fido.visible = false
	fido_collision.set_deferred("disabled", true)
	
	match(questHub.campbellProg):
		0: 
			quest_marker_.visible = false
		1:
			quest_marker_.visible = true
		2:
			quest_marker_.visible = true
		3:
			quest_marker_.visible = false
			


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass



func campbellProgression(value: int):

	if questHub.campbellProg == 2:
		print("FIDO Progression!!!")
		print("Fido Progression: ", questHub.campbellProg)
		quest_marker_.visible = true

func iterationChange(value: int):
	print("FIDO DETECTED!")
	
	#If on iteration 3, turn fido on
	if value == 2:
	
		#print(fido.global_position)
		fido_collision.set_deferred("disabled", false)
		animation_player.play("Bark")
		#print("FIDO ON!")
		fido.visible = true
		
		bark_2.play()
		
	if value > 5: # YOU FAIL QUEST IT YOU DO NOT FIND FIDO BY IT. 6
		bark_2.stop()
		fido.visible = false
		fido_collision.set_deferred("disabled", true)
		
		#animation_player.stop()



# Inside questHub.gd

func found_fido_trigger():
	if not multiplayer.is_server():
		rpc_id(1, "server_found_fido")
	else:
		server_found_fido()

@rpc("any_peer", "call_local", "reliable")
func server_found_fido():
	if not multiplayer.is_server(): return
	
	# Update the logic state
	#questHub.campbellProg = 3
	
	# Tell everyone to sync their variables and delete the dog
	sync_fido_found.rpc()

@rpc("authority", "call_local", "reliable")
func sync_fido_found():
	# Sync the variable locally for everyone
	questHub.campbellProg = 3
	
	# Sync the world: Stop sounds and remove the dog nodes
	# Assuming 'bark_2' is accessible or managed globally
	# If not, you might need a signal to tell the specific scene to stop sounds
	
	get_tree().call_group("doggy", "queue_free")
	print("Fido has been found and synced for everyone!")
