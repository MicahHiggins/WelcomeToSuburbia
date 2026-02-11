extends CharacterBody3D
class_name NPC

@export var move_speed: float = 3.5
@export var accel: float = 12.0

# Gravity tuning
@export var gravity_multiplier: float = 1.0
@export var stop_y_when_grounded: bool = true

# Optional: manually assign a PatrolPath. If blank, we auto-find nearest.
@export var patrol_path: PatrolPath
@export var auto_find_patrol_path: bool = true
@export var auto_find_max_dist: float = 800.0

@onready var sm: NPCStateMachine = $StateMachine

var _printed_once := false

# --------------------------------------------
# SERVER-AUTH NPC SIM + NET SYNC (LIKE BAT)
# --------------------------------------------
@export var authority_only_ai: bool = true

# NET SYNC SETTINGS
@export var net_send_rate_hz: float = 15.0
@export var net_lerp_alpha: float = 0.25

# HARD CORRECTION (snap instead of lerp if too far off)
@export var snap_distance_m: float = 2.0

var _net_last_send_time: float = 0.0
var _net_target_transform: Transform3D = Transform3D.IDENTITY
var _net_has_target: bool = false

# --------------------------------------------
# NEW: PATROL RESUME CACHE (states can resume patrol mid-path)
# --------------------------------------------
var patrol_resume_has_data: bool = false
var patrol_resume_idx: int = 0
var patrol_resume_wait_t: float = 0.0

func save_patrol_resume(idx: int, wait_t: float) -> void:
	patrol_resume_has_data = true
	patrol_resume_idx = idx
	patrol_resume_wait_t = wait_t

func consume_patrol_resume() -> Dictionary:
	# One-time consume (PatrolState reads this in enter(), then it clears)
	var d := {
		"has_data": patrol_resume_has_data,
		"idx": patrol_resume_idx,
		"wait_t": patrol_resume_wait_t
	}
	patrol_resume_has_data = false
	patrol_resume_wait_t = 0.0
	return d


func _enter_tree() -> void:
	# HARD FORCE: server always owns NPC authority
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		set_multiplayer_authority(1)


func _ready() -> void:
	add_to_group("npc")
	print("[NPC] ready:", name)

	# Auto-find patrol path
	if patrol_path == null and auto_find_patrol_path:
		patrol_path = find_nearest_patrol_path(auto_find_max_dist)
		print("[NPC] auto-found patrol_path:", patrol_path)

	if sm == null:
		push_error("[NPC] Missing StateMachine child node or wrong node name.")
		return

	# Initialize interpolation target
	_net_target_transform = global_transform

	# IMPORTANT: late joiners need a reliable snapshot of NPC transform
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# When someone connects later, send them THIS npc’s current transform (reliable)
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

		# Also send an initial reliable snapshot to everyone already connected
		_broadcast_initial_state()


func _broadcast_initial_state() -> void:
	# Send current transform to all peers reliably so everyone starts synced
	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_net_set_state_reliable", global_transform)


func _on_peer_connected(peer_id: int) -> void:
	# New peer joined: hard-set their starting NPC transform reliably
	rpc_id(peer_id, "_net_set_state_reliable", global_transform)


func _physics_process(delta: float) -> void:
	# Prove this script is actually running
	if not _printed_once:
		_printed_once = true
		print("[NPC] physics tick OK:", name)

	var has_peer := multiplayer.has_multiplayer_peer()

	# Same pattern as Bat:
	# - Authority simulates
	# - Non-authority interpolates
	if authority_only_ai and has_peer:
		if is_multiplayer_authority():
			_do_simulation(delta)
			_net_maybe_send_state()
		else:
			_net_interpolate_remote()
		return

	# Singleplayer / or if you disable authority_only_ai:
	_do_simulation(delta)


# -------------------------
#  AUTHORITY SIM STEP
# -------------------------
func _do_simulation(delta: float) -> void:
	# Tick state machine (AI) ONLY when simulating
	if sm != null:
		sm.physics_update(delta)

	# Gravity always
	if not is_on_floor():
		velocity.y += get_gravity().y * gravity_multiplier * delta
	else:
		if stop_y_when_grounded and velocity.y < 0.0:
			velocity.y = 0.0

	move_and_slide()


# Called by PatrolState (authority side)
func move_toward_world(target: Vector3, delta: float) -> void:
	var to := target - global_position
	to.y = 0.0

	if to.length() < 0.001:
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
		velocity.z = move_toward(velocity.z, 0.0, accel * delta)
		return

	var dir := to.normalized()
	var desired := dir * move_speed

	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)


func find_nearest_patrol_path(max_dist: float) -> PatrolPath:
	var best: PatrolPath = null
	var best_d := INF

	for n in get_tree().get_nodes_in_group("patrol_path"):
		var p := n as PatrolPath
		if p == null:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d and d <= max_dist:
			best_d = d
			best = p

	return best


# -------------------------
#   NET SYNC HELPERS
# -------------------------
func _net_maybe_send_state() -> void:
	# Only send if we have a proper multiplayer peer and are connected.
	if not multiplayer.has_multiplayer_peer():
		return

	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp == null:
		return
	if mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	# Throttle sending to net_send_rate_hz
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = 1.0 / max(net_send_rate_hz, 1.0)
	if now - _net_last_send_time < min_interval:
		return

	_net_last_send_time = now

	# Broadcast transform (unreliable is fine for continuous updates)
	rpc("_net_set_state_unreliable", global_transform)


@rpc("any_peer", "call_local", "unreliable")
func _net_set_state_unreliable(new_transform: Transform3D) -> void:
	# Ignore on authority (we already simulate locally)
	if is_multiplayer_authority():
		return

	_net_target_transform = new_transform
	_net_has_target = true


@rpc("any_peer", "call_local", "reliable")
func _net_set_state_reliable(new_transform: Transform3D) -> void:
	# Reliable snapshot for join-in-progress / hard correction
	if is_multiplayer_authority():
		return

	# Hard snap immediately on snapshot
	global_transform = new_transform
	_net_target_transform = new_transform
	_net_has_target = true


func _net_interpolate_remote() -> void:
	if not _net_has_target:
		return

	# HARD CORRECTION: if we are far off, snap instead of lerp
	var dist := global_position.distance_to(_net_target_transform.origin)
	if dist >= snap_distance_m:
		global_transform = _net_target_transform
		return

	# Otherwise smooth
	global_transform = global_transform.interpolate_with(_net_target_transform, net_lerp_alpha)


var in_bob_area = false
var bob_talking = false
signal dialogueSig



func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		dialogueSig.emit()
		
	if in_bob_area == true && Input.is_action_just_pressed("interact"):
		enter_bob_dialogue()
		
		
		
func enter_bob_dialogue():
	if bob_talking == false:
		bob_talking = true
		dialogue.toggle = true
		dialogue.uniqueName= "DAVE"
		await dialogueSig
		dialogue.uniqueName= "HI"
		await dialogueSig
		dialogue.toggle = false
		await get_tree().create_timer(1).timeout
		bob_talking = false
	
func _on_interact_body_entered(body: Node3D) -> void:
	in_bob_area = true
	print("TRUE")
	
	
func _on_interact_body_exited(body: Node3D) -> void:
	in_bob_area = false
	print("FALSE")
