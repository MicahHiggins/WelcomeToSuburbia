extends CanvasLayer

@export var level_2_cutscene = VideoStreamPlayer
var cutscene_2_bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GlobalVariables.level2change.connect(change_second_cutscene)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#change_second_cutscene()
	pass
	
func change_second_cutscene() -> void:
	if cutscene_2_bool == false:
		cutscene_2_bool = true
		level_2_cutscene.visible = true
		level_2_cutscene.paused = false
		await get_tree().create_timer(18).timeout
		level_2_cutscene.visible = false
