# NetSceneManager.gd (autoload)
extends Node

@export var player_scene: PackedScene = preload("res://addons/proto_controller/proto_controller.tscn")

# -----------------------------
#   SCENE CHANGE (GROUP VOTE)
# -----------------------------
var _pending_spawn_after_scene_change: bool = false
var _last_requested_scene: String = ""

# Server tracks votes for the currently requested scene
var _scene_vote_path: String = ""
var _scene_votes: Dictionary = {} # peer_id -> true


func _ready() -> void:
	# When the scene actually finishes switching, we spawn players into it.
	# This runs on every peer.
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)

# PATCH: convert PackedInt32Array -> Array[int] safely
func _peers_as_int_array() -> Array[int]:
	var out: Array[int] = []
	var packed: PackedInt32Array = multiplayer.get_peers()
	for i in packed:
		out.append(int(i))
	return out


# Call this from your interactable object.
func request_group_scene_change(scene_path: String) -> void:
	if scene_path == "":
		push_error("[NetSceneManager] request_group_scene_change: empty scene_path")
		return

	_last_requested_scene = scene_path

	# Solo test (no multiplayer): just change scene locally + spawn.
	if not multiplayer.has_multiplayer_peer():
		_pending_spawn_after_scene_change = true
		_change_scene_local(scene_path)
		return

	# Multiplayer: send our vote to the server.
	if multiplayer.is_server():
		# Host voting for itself (sender_id is 0 when called locally)
		_server_register_vote(multiplayer.get_unique_id(), scene_path)
	else:
		# Client vote to server
		rpc_id(1, "_rpc_server_vote_scene_change", scene_path)


@rpc("any_peer", "reliable")
func _rpc_server_vote_scene_change(scene_path: String) -> void:
	# Runs on SERVER when any peer votes
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_server_register_vote(sender_id, scene_path)


func _server_register_vote(peer_id: int, scene_path: String) -> void:
	# If the requested scene changes, reset votes
	if _scene_vote_path != scene_path:
		_scene_vote_path = scene_path
		_scene_votes.clear()

	_scene_votes[peer_id] = true

	# Expected voters = all connected peers + server/host (id=1)
	var expected: Array[int] = _peers_as_int_array() # PATCH
	if not expected.has(1):
		expected.append(1)

	# Check if everyone voted
	for id in expected:
		if not _scene_votes.has(id):
			# Still waiting on someone
			return

	# Everyone voted -> change scene for all
	_scene_votes.clear()
	_scene_vote_path = ""

	# Reliable RPC: all peers switch scenes
	rpc("_rpc_change_scene_for_all", scene_path)


@rpc("any_peer", "call_local", "reliable")
func _rpc_change_scene_for_all(scene_path: String) -> void:
	_pending_spawn_after_scene_change = true
	_change_scene_local(scene_path)


func _change_scene_local(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[NetSceneManager] change_scene_to_file failed: %s  err=%d" % [scene_path, err])
		_pending_spawn_after_scene_change = false


func _on_scene_changed() -> void:
	# Scene finished switching. Spawn players into the new current scene.
	if not _pending_spawn_after_scene_change:
		return

	_pending_spawn_after_scene_change = false
	_spawn_players_into_current_scene()


# -----------------------------
#   YOUR EXISTING SPAWN LOGIC
# -----------------------------
func _spawn_players_into_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var peers: Array[int] = _peers_as_int_array() # PATCH
	peers.sort()
	peers.push_front(multiplayer.get_unique_id()) # ensure host/local included

	for id in peers:
		_spawn_one(id)


func _spawn_one(peer_id: int) -> void:
	var scene := get_tree().current_scene
	if scene == null or player_scene == null:
		return

	# Avoid double-spawning
	if scene.has_node(str(peer_id)):
		return

	var p := player_scene.instantiate()
	p.name = str(peer_id)
	scene.add_child(p)

	# Authority setup
	p.set_multiplayer_authority(peer_id)

	# Place at spawn marker if present
	var sp := _get_spawn_for(peer_id)
	if sp != null:
		p.global_transform = sp.global_transform


func _get_spawn_for(peer_id: int) -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null

	var sp_root := scene.get_node_or_null("SpawnPoints")
	if sp_root == null:
		return null

	# Simple mapping: host=1 -> Spawn_1, client=2 -> Spawn_2, etc.
	var idx := 1
	if peer_id >= 1:
		idx = peer_id
	var node := sp_root.get_node_or_null("Spawn_%d" % idx)
	return node as Node3D
