extends Node

@export var effect_start_distance: float = 25.0   # start sanity drain + screen FX + slowing
@export var hard_lock_distance: float = 60.0      # beyond this you can ONLY move toward partner
@export var min_speed_multiplier: float = 0.15    # slowest speed when far (but still can move toward)

@export var tick_rate_hz: float = 10.0

@export var drain_per_sec: float = 10.0
@export var recover_per_sec: float = 4.0

var _sanity: Dictionary[int, float] = {}  # peer_id -> 0..100
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

	var by_id: Dictionary[int, Node3D] = {}

	for p in players:
		var p3d := p as Node3D
		if p3d == null:
			continue

		var id: int = _player_id_from_node(p3d)
		if id <= 0:
			continue

		by_id[id] = p3d
		if not _sanity.has(id):
			_sanity[id] = 100.0

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

		var partner: Node3D = by_id[nearest_id]

		var denom: float = maxf(hard_lock_distance - effect_start_distance, 0.001)
		var dist_factor: float = clamp((nearest_dist - effect_start_distance) / denom, 0.0, 1.0)

		var s: float = _sanity[id]
		if nearest_dist > effect_start_distance:
			s = maxf(0.0, s - drain_per_sec * dist_factor * dt)
		else:
			s = minf(100.0, s + recover_per_sec * dt)
		_sanity[id] = s

		var sanity_factor: float = 1.0 - (s / 100.0)
		var fx_intensity: float = clamp(maxf(dist_factor, sanity_factor), 0.0, 1.0)

		var speed_mult: float = lerpf(1.0, min_speed_multiplier, dist_factor)
		var hard_lock: bool = nearest_dist >= hard_lock_distance

		if not me.has_method("server_set_tether_state"):
			continue

		# IMPORTANT: call directly on host, rpc for everyone else
		if id == multiplayer.get_unique_id():
			me.call(
				"server_set_tether_state",
				partner.global_position,
				nearest_dist,
				speed_mult,
				hard_lock,
				s,
				fx_intensity
			)
		else:
			me.rpc_id(
				id,
				"server_set_tether_state",
				partner.global_position,
				nearest_dist,
				speed_mult,
				hard_lock,
				s,
				fx_intensity
			)

func _player_id_from_node(p: Node) -> int:
	var n: String = String(p.name)
	if n.is_valid_int():
		return int(n)
	return int(p.get_multiplayer_authority())
