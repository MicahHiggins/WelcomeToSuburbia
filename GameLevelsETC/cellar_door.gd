extends Node3D
class_name LevelSwapInteractable

@export var next_level: PackedScene
@export var level_flow_manager_path: NodePath = NodePath("/root/GameRoot/LevelFlowManager")

# Optional: prevent spam
@export var cooldown_seconds: float = 1.0
var _cooldown_t: float = 0.0

func _ready() -> void:
	add_to_group("interactable")

func _process(delta: float) -> void:
	if _cooldown_t > 0.0:
		_cooldown_t = maxf(0.0, _cooldown_t - delta)

func interact(from_player: Node) -> void:
	if _cooldown_t > 0.0:
		return
	_cooldown_t = cooldown_seconds

	# Multiplayer: ONLY server should initiate
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_swap")
		return

	_server_swap()

@rpc("any_peer", "reliable")
func _rpc_request_swap() -> void:
	if not multiplayer.is_server():
		return
	_server_swap()

func _server_swap() -> void:
	if next_level == null:
		push_error("[LevelSwapInteractable] next_level not assigned.")
		return

	var lfm := get_node_or_null(level_flow_manager_path)
	if lfm == null:
		push_error("[LevelSwapInteractable] LevelFlowManager not found at: " + String(level_flow_manager_path))
		return

	# 1) Load the cellar level on all peers
	lfm.call("load_level_server", next_level)

	# 2) After a frame, place everyone at the new Spawn
	lfm.call_deferred("teleport_all_players_to_current_spawn_server")

	# 3) After another frame, apply your “cellar movement rules”
	call_deferred("_deferred_apply_cellar_roles")

func _deferred_apply_cellar_roles() -> void:
	_apply_cellar_roles_server()

func _apply_cellar_roles_server() -> void:
	# Server-only guard
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# --- YOUR CELLAR MOVEMENT RULES GO HERE ---
	# Example: lowest peer id is leader, everyone else becomes follower
	var players := get_tree().get_nodes_in_group("player")

	var leader_id := 999999
	for p in players:
		var p3 := p as Node3D
		if p3 == null:
			continue
		var pid := int(p3.get_multiplayer_authority())
		if pid > 0 and pid < leader_id:
			leader_id = pid

	if leader_id == 999999:
		return

	for p in players:
		var p3 := p as Node3D
		if p3 == null:
			continue
		var pid := int(p3.get_multiplayer_authority())
		if pid <= 0:
			continue

		var is_leader := (pid == leader_id)

		# these RPCs already exist in your Player script
		if p3.has_method("server_set_cellar_role"):
			p3.rpc_id(pid, "server_set_cellar_role", is_leader, 0.35, 2.2, 0.25, leader_id)

	#
