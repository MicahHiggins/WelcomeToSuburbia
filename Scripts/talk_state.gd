extends NPCState
class_name TalkState

@export var talk_detection: Area3D
@export var exit_delay_sec: float = 0.35

var _empty_time: float = 0.0

func enter(_msg := {}) -> void:
	_empty_time = 0.0
	_stop_npc()
	
	if npc == null:
		return

func physics_update(delta: float) -> void:
	_stop_npc()
	var npc3d := npc as NPC
	if npc3d == null:
		return
	#Find and play animations for NPC models
	var model_node = find_descendant_in_group(npc3d, "NPC_Body")
	if model_node:
		var anim_player = find_descendant_in_group(model_node, "NPC_Animation")
		if anim_player:
			anim_player.play("NewStanding")
	
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
			
	if GlobalVariables.playerTalking == true:
		change_state.emit(&"SpeakState")

func _stop_npc() -> void:
	if npc == null:
		return
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0
	
#For finding nodes within nodes using groups
func find_descendant_in_group(node: Node, group: String) -> Node:
	if node.is_in_group(group):
		return node
		
	for child in node.get_children():
		var result = find_descendant_in_group(child, group)
		if result:
			return result
			
	return null
