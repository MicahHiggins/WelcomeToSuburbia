extends Node

@export var warn_distance: float = 25.0            # sanity starts draining past this
@export var teleport_distance: float = 55.0        # past this you can teleport (after grace)
@export var teleport_grace_seconds: float = 1.25   # must be beyond teleport_distance for this long
@export var tick_rate_hz: float = 10.0             # server tick rate for tether checks

@export var drain_per_sec: float = 10.0            # sanity drain at max intensity
@export var recover_per_sec: float = 4.0           # sanity recovery when close enough

@export var teleport_offset_forward: float = 2.5
@export var teleport_offset_side: float = 1.0
@export var teleport_offset_up: float = 0.5
@export var teleport_cooldown: float = 3.0

const SERVER_ID: int = 1

var _sanity: Dictionary[int, float] = {}             # peer_id -> 0..100
var _over_teleport_time: Dictionary[int, float] = {} # peer_id -> seconds
var _last_teleport_at: Dictionary[int, float] = {}   # peer_id -> seconds
var _accum: float = 0.0

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	_accum += delta
	var step: float = 1.0 / maxf(tick_rate_hz, 1.0)
	if _accum < step:
		return

	var dt: float = _accum
	_accum = 0.0
	_server_tick(dt)

func _server_tick(dt: float) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() < 2:
		return

	# Map peer_id -> player node
	var by_id: Dictionary[int, Node3D] = {}

	for p in players:
		var p3d := p as Node3D
		if p3d == null:
			continue

		var id: int = _player_id_from_node(p3d)
		if id <= 0:
			continue

		by_id[id] = p3d
		if not _sanity.has(id): _sanity[id] = 100.0
		if not _over_teleport_time.has(id): _over_teleport_time[id] = 0.0
		if not _last_teleport_at.has(id): _last_teleport_at[id] = -9999.0

	for id: int in by_id.keys():
		var me: Node3D = by_id[id]

		var nearest_id: int = -1
		var nearest_dist: float = INF

		for other_id: int in by_id.keys():
			if other_id == id:
				continue
			var other: Node3D = by_id[other_id]
			var d: float = me.global_position.distance_to(other.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_id = other_id

		if nearest_id == -1:
			continue

		# Distance -> intensity (0..1)
		var denom: float = maxf(teleport_distance - warn_distance, 0.001)
		var dist_factor: float = clamp((nearest_dist - warn_distance) / denom, 0.0, 1.0)

		# Sanity update
		var s: float = _sanity[id]
		if nearest_dist > warn_distance:
			s = maxf(0.0, s - drain_per_sec * dist_factor * dt)
		else:
			s = minf(100.0, s + recover_per_sec * dt)
		_sanity[id] = s

		var sanity_factor: float = 1.0 - (s / 100.0)
		var fx_intensity: float = clamp(maxf(dist_factor, sanity_factor), 0.0, 1.0)

		# Send to the owning peer (their local player will apply screen FX)
		if me.has_method("server_set_sanity"):
			me.rpc_id(id, "server_set_sanity", s, fx_intensity)

		# Teleport logic
		if nearest_dist > teleport_distance:
			_over_teleport_time[id] += dt

			# Only teleport ONE side of the pair to prevent “both teleporting”
			var anchor_id: int = mini(id, nearest_id)
			var mover_id: int = maxi(id, nearest_id)

			# Only the mover processes the teleport
			if id != mover_id:
				continue

			if _over_teleport_time[mover_id] >= teleport_grace_seconds:
				var now: float = Time.get_ticks_msec() * 0.001
				if now - _last_teleport_at[mover_id] < teleport_cooldown:
					continue

				_last_teleport_at[mover_id] = now
				_over_teleport_time[mover_id] = 0.0
				_teleport_player(by_id[mover_id], by_id[anchor_id], mover_id)
		else:
			_over_teleport_time[id] = 0.0

func _teleport_player(mover: Node3D, anchor: Node3D, mover_id: int) -> void:
	var forward: Vector3 = (-anchor.global_transform.basis.z).normalized()
	var side: Vector3 = (anchor.global_transform.basis.x).normalized()
	var side_sign: float = 1.0 if (mover_id % 2) == 0 else -1.0

	var target: Vector3 = anchor.global_position \
		+ forward * teleport_offset_forward \
		+ side * teleport_offset_side * side_sign \
		+ Vector3.UP * teleport_offset_up

	var yaw: float = anchor.global_transform.basis.get_euler().y

	# Tell the owning client to move itself (your players are client-authority)
	if mover.has_method("server_force_teleport"):
		mover.rpc_id(mover_id, "server_force_teleport", target, yaw)

	# Update server-side copy too (helps other peers converge immediately)
	mover.global_position = target

func _player_id_from_node(p: Node) -> int:
	var n: String = String(p.name)
	if n.is_valid_int():
		return int(n)
	return int(p.get_multiplayer_authority())
