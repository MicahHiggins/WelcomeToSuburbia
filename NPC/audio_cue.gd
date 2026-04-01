extends Node3D
@onready var audio_cue: Node3D = $"."

@onready var toddler_crying: AudioStreamPlayer3D = $toddlerCrying
@onready var dog_bark_1: AudioStreamPlayer3D = $DogBark1

var toddlerToggle = false
var players
var max_distance: float = 100.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	players = get_tree().get_nodes_in_group("player")
	questHub.iteration_changed.connect(iterationChange)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	#if players.size() >= 1 && toddlerToggle == true:
		#var distance = audio_cue.position.distance_to(players[0].position)
		#var volume_linear = 1.0 - clamp(distance/max_distance, 0.0, 1.0)
		#toddler_crying.volume_db = linear_to_db(volume_linear) if volume_linear > 0 else -100.0
		


func iterationChange(value: int):
	
	
	if value > 0 && value < 2:
		print("Dog Barking: AudioCue")
		dog_bark_1.play()
	if value >= 2 && value <= 5:
		toddlerToggle = true
		print("Toddler Crying, play! Stop Dog Barking")
		dog_bark_1.stop()
		toddler_crying.play()
	elif value > 5:
		toddlerToggle = false
		print("Toddler Crying, stop!")
		toddler_crying.stop()
	
