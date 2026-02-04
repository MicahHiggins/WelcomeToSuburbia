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

func _physics_process(delta: float) -> void:
	# Prove this script is actually running
	if not _printed_once:
		_printed_once = true
		print("[NPC] physics tick OK:", name)

	# Tick state machine
	if sm != null:
		sm.physics_update(delta)

	# Gravity always
	if not is_on_floor():
		velocity.y += get_gravity().y * gravity_multiplier * delta
	else:
		if stop_y_when_grounded and velocity.y < 0.0:
			velocity.y = 0.0

	move_and_slide()

# Called by PatrolState
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
