extends Node

@export var effect_start_distance: float = 25.0   # start sanity drain + screen FX + slowing
@export var hard_lock_distance: float = 60.0      # beyond this you can ONLY move toward partner
@export var min_speed_multiplier: float = 0.15    # slowest speed when far (but still can move toward)

@export var tick_rate_hz: float = 10.0

@export var drain_per_sec: float = 10.0
@export var recover_per_sec: float = 4.0

# FX shaping (still only sends fx_intensity; shader does the visuals)
@export var vignette_boost: float = 0.35          # pushes intensity up toward the high end
@export var close_recover_boost: float = 2.0      # >1.0 = effect fades faster when close

# DEBUG: force the effect on (for testing the shader)
@export var debug_force_fx: bool = false
@export var debug_force_intensity: float = 1.0    # 0..1

# Optional debug prints
@export var debug_print: bool = false
@export var debug_print_every_sec: float = 1.0

var _sanity: Dictionary[int, float] = {}  # peer_id -> 0..100
var _accum: float = 0.0
var _dbg_accum: float = 0.0

func _process(delta: float) -> void:
	# Server-only driver
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

	var by_id: Dictionary[int, Node3D] = {}

	# Build id -> player map and init sanity
	for p in players:
		var p3d: Node3D = p as Node3D
		if p3d == null:
			continue

		var id: int = _player_id_from_node(p3d)
		if id <= 0:
			continue

		by_id[id] = p3d
		if not _sanity.has(id):
			_sanity[id] = 100.0

	# Compute tether effects per player
	for id in by_id.keys():
		var me: Node3D = by_id[id]

		var nearest_id: int = -1
		var nearest_dist: float = INF

		for other_id in by_id.keys():
			if other_id == id:
				continue
			var other: Node3D = by_id[other_id]
			var d: float = me.global_position.distance_to(other.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_id = other_id

		if nearest_id == -1:
			continue

		var partner: Node3D = by_id[nearest_id]

		# DEBUG FORCE (lets you see the shader regardless of distance)
		if debug_force_fx:
			_send_tether_to_owner(
				id,
				me,
				partner.global_position,
				nearest_dist,
				1.0, # speed_mult
				false, # hard_lock
				float(_sanity[id]),
				clampf(debug_force_intensity, 0.0, 1.0)
			)
			continue

		var denom: float = maxf(hard_lock_distance - effect_start_distance, 0.001)
		var dist_factor: float = clampf((nearest_dist - effect_start_distance) / denom, 0.0, 1.0)

		var s: float = float(_sanity[id])

		# Drain far, recover close (with faster fade when close)
		if nearest_dist > effect_start_distance:
			s = maxf(0.0, s - drain_per_sec * dist_factor * dt)
		else:
			# closer -> more recovery boost
			var close_t: float = 1.0 - clampf(nearest_dist / maxf(effect_start_distance, 0.001), 0.0, 1.0)
			var recover_mult: float = lerpf(1.0, close_recover_boost, close_t)
			s = minf(100.0, s + recover_per_sec * recover_mult * dt)

		_sanity[id] = s

		var sanity_factor: float = 1.0 - (s / 100.0)

		# Base intensity
		var fx_intensity: float = clampf(maxf(dist_factor, sanity_factor), 0.0, 1.0)

		# Push intensity up near high end so vignette/static feels heavier
		fx_intensity = clampf(fx_intensity + vignette_boost * fx_intensity, 0.0, 1.0)

		var speed_mult: float = lerpf(1.0, min_speed_multiplier, dist_factor)
		var hard_lock: bool = nearest_dist >= hard_lock_distance

		_send_tether_to_owner(
			id,
			me,
			partner.global_position,
			nearest_dist,
			speed_mult,
			hard_lock,
			s,
			fx_intensity
		)

	# Optional debug print throttled
	if debug_print:
		_dbg_accum += dt
		if _dbg_accum >= maxf(debug_print_every_sec, 0.1):
			_dbg_accum = 0.0
			for id2 in by_id.keys():
				print("[Tether] id=", id2, " sanity=", _sanity[id2])

func _send_tether_to_owner(
	owner_id: int,
	me: Node3D,
	partner_pos: Vector3,
	nearest_dist: float,
	speed_mult: float,
	hard_lock: bool,
	sanity: float,
	fx_intensity: float
) -> void:
	if not me.has_method("server_set_tether_state"):
		if debug_print:
			push_warning("Player missing server_set_tether_state(): " + String(me.get_path()))
		return

	me.rpc_id(
		owner_id,
		"server_set_tether_state",
		partner_pos,
		nearest_dist,
		speed_mult,
		hard_lock,
		sanity,
		fx_intensity
	)

func _player_id_from_node(p: Node) -> int:
	# Prefer multiplayer authority (most reliable).
	var auth: int = int(p.get_multiplayer_authority())
	if auth > 0:
		return auth

	# Fallback: if node name is numeric.
	var n: String = String(p.name)
	if n.is_valid_int():
		return int(n)

	return -1
