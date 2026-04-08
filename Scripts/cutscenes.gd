extends CanvasLayer

@export var level_2_cutscene: VideoStreamPlayer

var cutscene_2_bool: bool = false

func _ready() -> void:
	GlobalVariables.level2change.connect(change_second_cutscene)

func change_second_cutscene() -> void:
	if cutscene_2_bool:
		return

	cutscene_2_bool = true

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc("_rpc_play_cutscene_2")
		else:
			rpc_id(1, "_rpc_request_cutscene_2")
	else:
		_play_cutscene_local()

@rpc("any_peer", "reliable")
func _rpc_request_cutscene_2() -> void:
	if not multiplayer.is_server():
		return
	rpc("_rpc_play_cutscene_2")

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_cutscene_2() -> void:
	_play_cutscene_local()

func _play_cutscene_local() -> void:
	if level_2_cutscene == null:
		return

	level_2_cutscene.visible = true
	level_2_cutscene.paused = false

	await get_tree().create_timer(18.0).timeout

	level_2_cutscene.visible = false
	level_2_cutscene.paused = true
