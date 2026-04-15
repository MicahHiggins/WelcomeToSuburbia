# res://voice_net.gd
extends Node

@export var debug_print: bool = true

# sender_id -> Node (VoiceChat)
var _targets: Dictionary = {}

func register_voice_target(peer_id: int, voice_chat: Node) -> void:
	_targets[peer_id] = voice_chat
	if debug_print:
		print("VoiceNet | registered:", peer_id, " -> ", voice_chat.get_path())

func unregister_voice_target(peer_id: int, voice_chat: Node) -> void:
	if _targets.has(peer_id) and _targets[peer_id] == voice_chat:
		_targets.erase(peer_id)
		if debug_print:
			print("VoiceNet | unregistered:", peer_id)

func send_voice(compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return
	if not multiplayer.has_multiplayer_peer():
		return
	rpc("_rpc_voice_packet", multiplayer.get_unique_id(), compressed)

@rpc("any_peer", "call_local", "unreliable")
func _rpc_voice_packet(sender_id: int, compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return

	var local_uid: int = multiplayer.get_unique_id()
	if sender_id == local_uid:
		return

	if not _targets.has(sender_id):
		if debug_print:
			print("VoiceNet | RECV from", sender_id, "but no target registered yet")
		return

	var vc_node: Node = _targets[sender_id] as Node
	if vc_node == null:
		return

	if debug_print:
		print("VoiceNet | RECV from", sender_id, "bytes:", compressed.size())

	vc_node.call("_voice_receive_compressed", sender_id, compressed)
