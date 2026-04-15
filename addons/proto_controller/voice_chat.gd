# res://voice_chat.gd
extends Node
class_name VoiceChat

@export var enable_voice: bool = true
@export var push_to_talk: bool = true
@export var ptt_action: StringName = &"voice"

@export var send_rate_hz: float = 30.0
@export var max_compressed_bytes: int = 16384

# --- PROXIMITY (AudioStreamPlayer3D base settings) ---
@export var hear_radius: float = 32.0          # was 18
@export var unit_size: float = 0.65            # was 1.0 (smaller = louder close)
@export var base_volume_db: float = 0.0        # baseline before extra distance gain

@export var playback_buffer_sec: float = 0.70

# --- EXTRA PROXIMITY CURVE (stacks on top of 3D attenuation) ---
# This only runs on LISTENERS (non-local authority instances) so it doesn't affect sending.
@export var use_extra_distance_gain: bool = true
@export var near_boost_db: float = 10.0        # extra gain at 0m
@export var far_cut_db: float = -10.0          # extra cut at max_distance
@export var gain_curve_pow: float = 1.8        # >1 = punchier close, faster falloff
@export var gain_update_hz: float = 12.0       # how often we update gain

# script is on Head, VoicePlayer3D is a child under Head
@export var voice_player_path: NodePath = NodePath("VoicePlayer3D")

@export var debug_print: bool = true
@export var debug_interval_sec: float = 0.75

var _steam: Object = null
var _steam_ok: bool = false
var _sample_rate: int = 48000

var _recording: bool = false
var _last_send_t: float = 0.0

var _voice_player: AudioStreamPlayer3D = null
var _playback: AudioStreamGeneratorPlayback = null

var _dbg_t: float = 0.0
var _gain_t: float = 0.0

func _enter_tree() -> void:
	_inherit_authority_from_owner()

func _ready() -> void:
	_steam = _get_steam_singleton()
	_steam_ok = _init_steam_voice()

	_voice_player = get_node_or_null(voice_player_path) as AudioStreamPlayer3D
	if _voice_player == null:
		push_error("VoiceChat: missing AudioStreamPlayer3D at " + str(voice_player_path))
		return

	# 3D proximity settings (voice emits from THIS node's position)
	_voice_player.max_distance = hear_radius
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_player.unit_size = unit_size
	_voice_player.bus = &"Master"
	_voice_player.volume_db = base_volume_db
	_voice_player.stream_paused = false

	# generator stream for decoded PCM (16-bit mono -> we push stereo frames)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _sample_rate
	gen.buffer_length = playback_buffer_sec
	_voice_player.stream = gen
	_voice_player.play()

	_playback = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback
	set_process(true)

	if debug_print:
		print("VoiceChat ready | node_auth:", int(get_multiplayer_authority()),
			" local_uid:", (multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1),
			" local_auth:", _is_local_authority_player(),
			" steam:", _steam != null,
			" steam_ok:", _steam_ok,
			" sr:", _sample_rate,
			" playback:", _playback != null,
			" hear_radius:", hear_radius,
			" unit_size:", unit_size)

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		return

	_run_steam_callbacks_safe()

	# ONLY the local authority player instance captures + broadcasts
	if _is_local_authority_player():
		_capture_and_send_voice()
	else:
		# listeners apply extra distance gain to make "close louder / far quieter"
		if use_extra_distance_gain:
			_gain_t += dt
			var step: float = 1.0 / maxf(gain_update_hz, 1.0)
			if _gain_t >= step:
				_gain_t = 0.0
				_apply_extra_distance_gain()

	_dbg_t += dt
	if debug_print and _dbg_t >= debug_interval_sec:
		_dbg_t = 0.0
		_debug_tick()

# =========================
#   AUTHORITY
# =========================
func _inherit_authority_from_owner() -> void:
	var owner_player: Node = _find_owner_player_node()
	if owner_player == null:
		return
	var auth: int = int(owner_player.get_multiplayer_authority())
	if auth > 0 and auth != int(get_multiplayer_authority()):
		set_multiplayer_authority(auth)

func _find_owner_player_node() -> Node:
	var cur: Node = self
	while cur != null:
		if cur.is_in_group("player"):
			return cur
		cur = cur.get_parent()
	return null

func _is_local_authority_player() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return int(get_multiplayer_authority()) == int(multiplayer.get_unique_id())

# =========================
#   STEAM
# =========================
func _get_steam_singleton() -> Object:
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	push_error("Steam engine singleton not found (GodotSteam not loaded).")
	return null

func _init_steam_voice() -> bool:
	if _steam == null:
		return false
	if _steam.has_method("getVoiceOptimalSampleRate"):
		_sample_rate = int(_steam.call("getVoiceOptimalSampleRate"))
	else:
		_sample_rate = 48000
	return true

func _run_steam_callbacks_safe() -> void:
	if _steam == null:
		return
	if _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")
	elif _steam.has_method("runCallbacks"):
		_steam.call("runCallbacks")

# =========================
#   SEND
# =========================
func _wants_talk() -> bool:
	if not enable_voice:
		return false
	if not _steam_ok:
		return false
	if push_to_talk:
		if not InputMap.has_action(ptt_action):
			return false
		return Input.is_action_pressed(ptt_action)
	return true

func _start_recording_if_needed() -> void:
	if _recording:
		return
	if _steam != null and _steam.has_method("startVoiceRecording"):
		_steam.call("startVoiceRecording")
	_recording = true

func _stop_recording_if_needed() -> void:
	if not _recording:
		return
	if _steam != null and _steam.has_method("stopVoiceRecording"):
		_steam.call("stopVoiceRecording")
	_recording = false

func _capture_and_send_voice() -> void:
	var talk: bool = _wants_talk()
	if talk:
		_start_recording_if_needed()
	else:
		_stop_recording_if_needed()
		return

	var now: float = float(Time.get_ticks_msec()) * 0.001
	var min_dt: float = 1.0 / maxf(send_rate_hz, 1.0)
	if now - _last_send_t < min_dt:
		return
	_last_send_t = now

	var compressed: PackedByteArray = _read_compressed_voice()
	if debug_print:
		print("SEND | uid:", multiplayer.get_unique_id(), " auth:", int(get_multiplayer_authority()),
			" bytes:", compressed.size(), " recording:", _recording)

	if compressed.is_empty():
		return

	# Broadcast on THIS player's node. On each peer, the packet is received on the
	# speaker's corresponding node, so audio emits from the correct world position.
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_voice_packet", compressed)

func _read_compressed_voice() -> PackedByteArray:
	var out := PackedByteArray()
	if _steam == null:
		return out

	if _steam.has_method("getVoice"):
		var res: Variant = _steam.call("getVoice", max_compressed_bytes)
		if typeof(res) == TYPE_DICTIONARY:
			var d: Dictionary = res as Dictionary
			var bb: PackedByteArray = (d.get("buffer", PackedByteArray()) as PackedByteArray)
			# If GodotSteam includes a "written" field, trim to it
			var w: int = int(d.get("written", 0))
			if w > 0 and w <= bb.size():
				return bb.slice(0, w)
			return bb
		if res is PackedByteArray:
			return res as PackedByteArray

	return out

# =========================
#   RECEIVE / PLAY
# =========================
@rpc("any_peer", "call_local", "unreliable")
func _rpc_voice_packet(compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	# Don't echo your own voice locally.
	if _is_local_authority_player():
		return

	if debug_print:
		print("RECV | local_uid:", multiplayer.get_unique_id(),
			" node_auth:", int(get_multiplayer_authority()),
			" from:", sender_id,
			" cbytes:", compressed.size())

	_play_compressed_local(sender_id, compressed)

func _play_compressed_local(sender_id: int, compressed: PackedByteArray) -> void:
	if _steam == null or not _steam.has_method("decompressVoice"):
		return
	if _playback == null:
		return

	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)

	var pcm: PackedByteArray = PackedByteArray()
	var sz: int = 0

	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary
		# different builds return different keys:
		# - "uncompressed" + "size"
		# - "buffer" + "written"
		if d.has("uncompressed"):
			pcm = d.get("uncompressed", PackedByteArray()) as PackedByteArray
			sz = int(d.get("size", pcm.size()))
		elif d.has("buffer"):
			pcm = d.get("buffer", PackedByteArray()) as PackedByteArray
			sz = int(d.get("written", pcm.size()))
	else:
		return

	if sz > 0 and sz < pcm.size():
		pcm = pcm.slice(0, sz)

	if debug_print:
		print("DECOMP | from:", sender_id, " pcm:", pcm.size(), " size:", sz)

	if pcm.is_empty():
		return

	_push_pcm_to_playback(_playback, pcm)

func _push_pcm_to_playback(pb: AudioStreamGeneratorPlayback, pcm: PackedByteArray) -> void:
	var sample_count: int = pcm.size() / 2
	if sample_count <= 0:
		return

	var room: int = pb.get_frames_available()
	if room <= 0:
		return

	var to_push: int = mini(sample_count, room)
	var idx: int = 0

	for i in range(to_push):
		var lo: int = int(pcm[idx])
		var hi: int = int(pcm[idx + 1])
		var s16: int = (hi << 8) | lo
		if s16 >= 32768:
			s16 -= 65536

		var f: float = float(s16) / 32768.0
		pb.push_frame(Vector2(f, f))
		idx += 2

# =========================
#   EXTRA DISTANCE GAIN (listener-side)
# =========================
func _apply_extra_distance_gain() -> void:
	if _voice_player == null:
		return

	var listener_cam: Camera3D = get_viewport().get_camera_3d()
	if listener_cam == null:
		return

	var maxd: float = maxf(_voice_player.max_distance, 0.001)
	var d: float = listener_cam.global_position.distance_to(_voice_player.global_position)
	var t: float = clampf(d / maxd, 0.0, 1.0)

	var shaped: float = pow(t, gain_curve_pow)
	var extra_db: float = lerp(near_boost_db, far_cut_db, shaped)

	_voice_player.volume_db = base_volume_db + extra_db

# =========================
#   DEBUG
# =========================
func _debug_tick() -> void:
	var mp_on: bool = multiplayer.has_multiplayer_peer()
	var local_uid: int = (multiplayer.get_unique_id() if mp_on else -1)

	var ptt_ok: bool = (not push_to_talk) or InputMap.has_action(ptt_action)
	var ptt_pressed: bool = false
	if ptt_ok and push_to_talk:
		ptt_pressed = Input.is_action_pressed(ptt_action)

	print("VOICE DBG | mp:", mp_on,
		" node_auth:", int(get_multiplayer_authority()),
		" local_uid:", local_uid,
		" local_auth:", _is_local_authority_player(),
		" ptt_ok:", ptt_ok,
		" ptt:", ptt_pressed,
		" recording:", _recording,
		" sr:", _sample_rate,
		" maxd:", hear_radius,
		" unit:", unit_size,
		" base_db:", base_volume_db,
		" extra_gain:", use_extra_distance_gain)
