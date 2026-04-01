extends NPCState
class_name SpeakState


@export var talk_detection: Area3D

var _empty_time: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_empty_time = 0.0
	_stop_npc()
	
	if npc == null:
		return

# Called every frame. 'delta' is the elapsed time since the previous frame.
func physics_update(delta: float) -> void:
	_stop_npc()
	var npc3d := npc as NPC
	if npc3d == null:
		return
	#Find and play animations for NPC models
	var model_node = find_descendant_in_group(npc3d, "NPC_Body")
	if model_node:
		var anim_player = find_descendant_in_group(model_node, "NPC_Animation")
		if anim_player and GlobalVariables.playerTalking == true:
			anim_player.play("NewTalking")
			
	if GlobalVariables.playerTalking == false:
		change_state.emit(&"TalkState")
		
	for b in talk_detection.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			var target := b.global_position
			var look_target := target
			look_target.y += 1.5
			npc3d.look_at(look_target)


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
