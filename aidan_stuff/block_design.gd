extends Node3D

@onready var houses: Node3D = $Houses
@onready var roads: Node3D = $Roads

const PATROL_BUNDLE: PackedScene = preload("res://aidan_stuff/patrol_path.tscn")
const PATROL_BUNDLE_ABIGAIL: PackedScene = preload("res://NPC/patrol_bundel_abigail.tscn")
const PATROL_BUNDLE_CAMPBELL: PackedScene = preload("res://NPC/patrol_bundle_campbells.tscn")

# we want all npcs to spawn on this block, so we keep separate instances
var patrol_instance_bob: Node3D = null
var patrol_instance_abigail: Node3D = null
var patrol_instance_campbell: Node3D = null

var entered := false

func _ready() -> void:
	houses.visible = false
	roads.visible = false

	# late joiners: if someone joins after we spawned, server tells them the current state
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
	# bring the new peer up to date
	rpc_id(peer_id, "_rpc_set_active", entered, global_transform)

func _on_area_3d_body_entered(body: Node3D) -> void:
	print("WHAT!")
	print("name: ", body)

	if body == null or not body.is_in_group("player"):
		return

	# multiplayer: ONLY server decides spawn/despawn
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if entered:
		return
	entered = true

	GlobalVariables.iterations = GlobalVariables.iterations + 1

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
	houses.visible = active
	roads.visible = active

	if active:
		_spawn_all(block_xform)
	else:
		_despawn_all()

func _spawn_all(block_xform: Transform3D) -> void:
	# Spawn Bob bundle
	if patrol_instance_bob == null or not is_instance_valid(patrol_instance_bob):
		patrol_instance_bob = PATROL_BUNDLE.instantiate() as Node3D
		add_child(patrol_instance_bob)
		patrol_instance_bob.name = "PatrolBundle" # force same name on all peers
		patrol_instance_bob.global_transform = block_xform

	# Spawn Abigail bundle
	if patrol_instance_abigail == null or not is_instance_valid(patrol_instance_abigail):
		patrol_instance_abigail = PATROL_BUNDLE_ABIGAIL.instantiate() as Node3D
		add_child(patrol_instance_abigail)
		patrol_instance_abigail.name = "PatrolBundelAbigail" # match your existing path spelling
		patrol_instance_abigail.global_transform = block_xform

	# Spawn Campbell bundle
	if patrol_instance_campbell == null or not is_instance_valid(patrol_instance_campbell):
		patrol_instance_campbell = PATROL_BUNDLE_CAMPBELL.instantiate() as Node3D
		add_child(patrol_instance_campbell)
		patrol_instance_campbell.name = "PatrolBundleCampbells"
		patrol_instance_campbell.global_transform = block_xform

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
