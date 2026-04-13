extends Node3D

@onready var houses: Node3D = $Houses
@onready var roads: Node3D = $Roads


const PATROL_BUNDLE: PackedScene = preload("res://aidan_stuff/patrol_path.tscn")
const PATROL_BUNDLE_ABIGAIL: PackedScene = preload("res://NPC/patrol_bundel_abigail.tscn")
const PATROL_BUNDLE_CAMPBELL: PackedScene = preload("res://NPC/patrol_bundle_campbells.tscn")
const PATROL_BUNDLE_SUS: PackedScene = preload("res://NPC/patrol_bundel_sus.tscn")
const PATROL_BUNDLE_ISSACC: PackedScene = preload("res://NPC/patrol_bundel_issacc.tscn")
const PATROL_BUNDLE_RH: PackedScene = preload("res://NPC/patrol_bundel_rh.tscn")

# we want all npcs to spawn on this block, so we keep separate instances
var patrol_instance_bob: Node3D = null
var patrol_instance_abigail: Node3D = null
var patrol_instance_campbell: Node3D = null
var patrol_instance_sus: Node3D = null
var patrol_instance_issacc: Node3D = null
var patrol_instance_rh: Node3D = null

var entered := false

func _ready() -> void:
	
	#AudioManager.gameStart.emit()
	
	GlobalVariables.iterations = 0
	GlobalVariables.gameStart.emit()
	houses.visible = false
	roads.visible = false

	# late joiners: if someone joins after we spawned, server tells them the current state
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
	# ADDED: defer one frame so the joining peer has finished instancing the level tree
	call_deferred("_deferred_send_state_to_peer", peer_id)

# ADDED: actual send happens after one frame
func _deferred_send_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# bring the new peer up to date
	rpc_id(peer_id, "_rpc_set_active", entered, global_transform)

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return

	# multiplayer: ONLY server decides spawn/despawn
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if entered:
		return
	entered = true

	# tell everyone to show + spawn
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_set_active", true, global_transform)
	else:
		_rpc_set_active(true, global_transform)

func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return

	# multiplayer: ONLY server decides spawn/despawn
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not entered:
		return
	entered = false

	# tell everyone to hide + despawn
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_set_active", false, global_transform)
	else:
		_rpc_set_active(false, global_transform)

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_active(active: bool, block_xform: Transform3D) -> void:
	# ADDED: apply the authoritative transform first
	# This prevents "finicky" visibility/spawns when the client has not yet applied PCG block moves.
	global_transform = block_xform

	houses.visible = active
	roads.visible = active
	print("SET")

	if active:
		_spawn_all(block_xform)
	else:
		_despawn_all()

func _spawn_all(block_xform: Transform3D) -> void:
	# Spawn Bob bundle
	if patrol_instance_bob == null or not is_instance_valid(patrol_instance_bob):
		patrol_instance_bob = PATROL_BUNDLE.instantiate() as Node3D
		if patrol_instance_bob != null:
			add_child(patrol_instance_bob)
			patrol_instance_bob.name = "PatrolBundle"
			patrol_instance_bob.global_transform = block_xform

	# Spawn Abigail bundle
	if patrol_instance_abigail == null or not is_instance_valid(patrol_instance_abigail):
		patrol_instance_abigail = PATROL_BUNDLE_ABIGAIL.instantiate() as Node3D
		if patrol_instance_abigail != null:
			add_child(patrol_instance_abigail)
			patrol_instance_abigail.name = "PatrolBundelAbigail"
			patrol_instance_abigail.global_transform = block_xform

	# Spawn Campbell bundle
	if patrol_instance_campbell == null or not is_instance_valid(patrol_instance_campbell):
		patrol_instance_campbell = PATROL_BUNDLE_CAMPBELL.instantiate() as Node3D
		if patrol_instance_campbell != null:
			add_child(patrol_instance_campbell)
			patrol_instance_campbell.name = "PatrolBundleCampbells"
			patrol_instance_campbell.global_transform = block_xform

	# Spawn Sus bundle
	if patrol_instance_sus == null or not is_instance_valid(patrol_instance_sus):
		patrol_instance_sus = PATROL_BUNDLE_SUS.instantiate() as Node3D
		if patrol_instance_sus != null:
			add_child(patrol_instance_sus)
			patrol_instance_sus.name = "PatrolBundelSus"
			patrol_instance_sus.global_transform = block_xform
		else:
			push_error("Failed to instantiate res://NPC/patrol_bundel_sus.tscn as Node3D")

	# Spawn Issacc bundle
	if patrol_instance_issacc == null or not is_instance_valid(patrol_instance_issacc):
		patrol_instance_issacc = PATROL_BUNDLE_ISSACC.instantiate() as Node3D
		if patrol_instance_issacc != null:
			add_child(patrol_instance_issacc)
			patrol_instance_issacc.name = "PatrolBundelIssacc"
			patrol_instance_issacc.global_transform = block_xform
		else:
			push_error("Failed to instantiate res://NPC/patrol_bundel_issacc.tscn as Node3D")

	# Spawn RH bundle
	if patrol_instance_rh == null or not is_instance_valid(patrol_instance_rh):
		patrol_instance_rh = PATROL_BUNDLE_RH.instantiate() as Node3D
		if patrol_instance_rh != null:
			add_child(patrol_instance_rh)
			patrol_instance_rh.name = "PatrolBundelRh"
			patrol_instance_rh.global_transform = block_xform
		else:
			push_error("Failed to instantiate res://NPC/patrol_bundel_rh.tscn as Node3D")

func _despawn_all() -> void:
	# Despawn Bob bundle
	if patrol_instance_bob != null and is_instance_valid(patrol_instance_bob):
		patrol_instance_bob.queue_free()
	patrol_instance_bob = null

	# Despawn Abigail bundle
	if patrol_instance_abigail != null and is_instance_valid(patrol_instance_abigail):
		patrol_instance_abigail.queue_free()
	patrol_instance_abigail = null

	# Despawn Campbell bundle
	if patrol_instance_campbell != null and is_instance_valid(patrol_instance_campbell):
		patrol_instance_campbell.queue_free()
	patrol_instance_campbell = null

	# Despawn Sus bundle
	if patrol_instance_sus != null and is_instance_valid(patrol_instance_sus):
		patrol_instance_sus.queue_free()
	patrol_instance_sus = null

	# Despawn Issacc bundle
	if patrol_instance_issacc != null and is_instance_valid(patrol_instance_issacc):
		patrol_instance_issacc.queue_free()
	patrol_instance_issacc = null

	# Despawn RH bundle
	if patrol_instance_rh != null and is_instance_valid(patrol_instance_rh):
		patrol_instance_rh.queue_free()
	patrol_instance_rh = null

func _on_iteration_detector_body_entered(body: Node3D) -> void:
	pass

func _on_timer_timeout() -> void:
	pass
