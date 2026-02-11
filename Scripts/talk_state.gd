extends NPCState
class_name TalkState

@export var talk_detection: Area3D
@export var exit_delay_sec: float = 0.35

var _empty_time: float = 0.0

func enter(_msg := {}) -> void:
	_empty_time = 0.0
	_stop_npc()

func physics_update(delta: float) -> void:
	_stop_npc()

	# If the area isn't set, just "stay talking" (prevents ping-pong).
	if talk_detection == null or not is_instance_valid(talk_detection):
		_empty_time = 0.0
		return

	# Check if ANY player is still inside the area
	var player_in_range := false
	for b in talk_detection.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			player_in_range = true
			break

	if player_in_range:
		_empty_time = 0.0
	else:
		_empty_time += delta
		if _empty_time >= exit_delay_sec:
			change_state.emit(&"PatrolState")

func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0
