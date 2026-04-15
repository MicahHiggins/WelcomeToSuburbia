# res://voice_net.gd
extends Node

@export var debug_print: bool = true

# peer_id(int) -> VoiceChat node
var _targets: Dictionary = {}

func _ready() -> void:
	set_process(false)
	if debug_print:
		print("VoiceNet ready | mp:", multiplayer.has_multiplayer_peer(), " uid:", _uid())

# =========================
#   REGISTER / UNREGISTER
# =========================
func register_voice_target(peer_id: int, voice_chat_node: Node) -> void:
	if peer_id <= 0 or voice_chat_node == null:
		return
	_targets[peer_id] = voice_chat_node
	if debug_print:
		print("VoiceNet | register peer:", peer_id, " node:", voice_chat_node.get_path())

func unregister_voice_target(peer_id: int, voice_chat_node: Node) -> void:
	if not _targets.has(peer_id):
		return
	if _targets[peer_id] == voice_chat_node:
		_targets.erase(peer_id)
		if debug_print:
			print("VoiceNet | unregister peer:", peer_id)

# =========================
#        SEND VOICE
# =========================
func send_voice(compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return
	if not multiplayer.has_multiplayer_peer():
		return

	var sender_id: int = _uid()
	if sender_id <= 0:
		return

	# Server can broadcast to everyone directly
	if multiplayer.is_server():
		_broadcast_voice_local(sender_id, compressed)
		return

	# Clients send to server (host is usually peer 1)
	rpc_id(1, "_rpc_voice_from_client", compressed)

@rpc("any_peer", "unreliable")
func _rpc_voice_from_client(compressed: PackedByteArray) -> void:
	# server receives from clients, then broadcasts to everyone
	if not multiplayer.is_server():
		return

	var sender_id: int = int(multiplayer.get_remote_sender_id())
	if sender_id <= 0 or compressed.is_empty():
		return

	_broadcast_voice_local(sender_id, compressed)

func _broadcast_voice_local(sender_id: int, compressed: PackedByteArray) -> void:
	# broadcast to all peers INCLUDING server local
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_voice_broadcast_packet", sender_id, compressed)

	# also deliver locally on the server instance
	_deliver(sender_id, compressed)

@rpc("any_peer", "call_local", "unreliable")
func _rpc_voice_broadcast_packet(sender_id: int, compressed: PackedByteArray) -> void:
	_deliver(sender_id, compressed)

# =========================
#        DELIVER
# =========================
func _deliver(sender_id: int, compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return

	# don't play your own voice locally
	if sender_id == _uid():
		return

	# play audio FROM the speaker's avatar on this client
	var target: Node = _targets.get(sender_id, null) as Node
	if target == null:
		if debug_print:
			print("VoiceNet | DROP (no target) from:", sender_id,
				" size:", compressed.size(),
				" known:", _targets.keys())
		return

	if not target.has_method("_voice_receive_compressed"):
		if debug_print:
			print("VoiceNet | DROP (target missing _voice_receive_compressed) peer:", sender_id,
				" node:", target.get_path())
		return

	if debug_print:
		print("VoiceNet | DELIVER from:", sender_id,
			" bytes:", compressed.size(),
			" -> ", target.get_path())

	target.call("_voice_receive_compressed", sender_id, compressed)

# =========================
#          UTIL
# =========================
func _uid() -> int:
	if multiplayer.has_multiplayer_peer():
		return int(multiplayer.get_unique_id())
	return -1
