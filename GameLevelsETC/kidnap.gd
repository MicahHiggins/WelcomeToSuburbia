extends Node3D

@onready var cohesion: AnimationPlayer = $Cohesion

var _anim_player: AnimationPlayer = null
var _last_anim: StringName = &""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_toy_piano_puzzle_one_complete() -> void:
	#cohesion.play("puzzle1Complete")
	_play_anim_server(&"puzzle1Complete")

#
#func _play_anim_local(anim_name: StringName) -> void:
	#if _anim_player == null:
		#_cache_anim_player()




func _get_anim_player() -> AnimationPlayer:
	if _anim_player != null and is_instance_valid(_anim_player):
		return _anim_player

	# simplest: if the AnimationPlayer is a direct child, use this:
	_anim_player = get_node_or_null("Cohesion") as AnimationPlayer
	return _anim_player



func _play_anim_server(anim: StringName) -> void:
	# 1) if multiplayer, only server is allowed to decide
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# 2) don't spam the same anim
	if _last_anim == anim:
		return
	_last_anim = anim

	# 3) play locally (server also needs to see it)
	var ap := _get_anim_player()
	if ap != null:
		ap.play(String(anim))

	# 4) tell everyone else
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_play_anim", String(anim))

@rpc("any_peer", "call_local", "unreliable")
func _rpc_play_anim(anim_name: String) -> void:
	# server ignores its own packet (optional, but clean)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return

	_last_anim = StringName(anim_name)

	var ap := _get_anim_player()
	if ap != null:
		ap.play(anim_name)
		
	
