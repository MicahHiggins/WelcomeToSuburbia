# res://voice_chat.gd
extends Node
class_name VoiceChat

@export var enable_voice: bool = true
@export var push_to_talk: bool = true
@export var ptt_action: StringName = &"voice"

@export var send_rate_hz: float = 20.0
@export var max_compressed_bytes: int = 8192

@export var hear_radius: float = 18.0
@export var unit_size: float = 1.0
@export var playback_buffer_sec: float = 0.35

# Script is on Head, VoicePlayer3D is a child under Head
@export var voice_player_path: NodePath = NodePath("VoicePlayer3D")

@export var debug_print: bool = true
@export var debug_interval_sec: float = 0.75

# If you hold PTT and still never send >0 bytes, warn after this
@export var no_data_warn_sec: float = 2.0

var _steam: Object = null
var _steam_ok: bool = false
var _sample_rate: int = 48000

var _recording: bool = false
var _last_send_t: float = 0.0

var _voice_player: AudioStreamPlayer3D = null
var _playback: AudioStreamGeneratorPlayback = null

var _dbg_t: float = 0.0

# "why is joiner sending 0" tracker
var _ptt_hold_time: float = 0.0
var _warned_no_data: bool = false

func _ready() -> void:
	_inherit_authority_from_owner()

	_steam = _get_steam_singleton()
	_steam_ok = _init_steam_voice()

	_voice_player = get_node_or_null(voice_player_path) as AudioStreamPlayer3D
	if _voice_player == null:
		push_error("VoiceChat: missing AudioStreamPlayer3D at voice_player_path: " + str(voice_player_path))
		return

	_voice_player.max_distance = hear_radius
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_player.unit_size = unit_size
	_voice_player.bus = &"Master"
	_voice_player.volume_db = 0.0
	_voice_player.stream_paused = false

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _sample_rate
	gen.buffer_length = playback_buffer_sec
	_voice_player.stream = gen
	_voice_player.play()
	_playback = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback

	# Always process so remote nodes can receive+play.
	set_process(true)

	if debug_print:
		print("VoiceChat ready | node_auth:", int(get_multiplayer_authority()),
			" local_uid:", (multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1),
			" local_auth:", _is_local_authority_player())
		print("steam:", _steam != null, " steam_ok:", _steam_ok, " sr:", _sample_rate)
		print("voice player:", _voice_player != null, " playback:", _playback != null)

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		return

	_run_steam_callbacks_safe()

	if _is_local_authority_player():
		_capture_and_send_voice(dt)
	else:
		# never track PTT / warn on non-local nodes
		_ptt_hold_time = 0.0
		_warned_no_data = false

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

	var vp := get_node_or_null(voice_player_path)
	if vp != null:
		vp.set_multiplayer_authority(auth)

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
	push_error("Steam engine singleton not found. Make sure GodotSteam is enabled and loaded.")
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
#   RECORD / SEND
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
	if _steam == null:
		return
	if _steam.has_method("startVoiceRecording"):
		_steam.call("startVoiceRecording")
	_recording = true

func _stop_recording_if_needed() -> void:
	if not _recording:
		return
	if _steam == null:
		return
	if _steam.has_method("stopVoiceRecording"):
		_steam.call("stopVoiceRecording")
	_recording = false

func _capture_and_send_voice(dt: float) -> void:
	# HARD GATE: only local authority may ever send
	if not _is_local_authority_player():
		return

	var talk: bool = _wants_talk()
	if talk:
		_start_recording_if_needed()
		_ptt_hold_time += dt
	else:
		_ptt_hold_time = 0.0
		_warned_no_data = false
		_stop_recording_if_needed()
		return

	var now: float = float(Time.get_ticks_msec()) * 0.001
	var min_dt: float = 1.0 / maxf(send_rate_hz, 1.0)
	if now - _last_send_t < min_dt:
		return
	_last_send_t = now

	var compressed: PackedByteArray = _read_compressed_voice()

	# Only print SEND from the local authority node
	if debug_print:
		print("SEND | uid:", multiplayer.get_unique_id(),
			" auth:", int(get_multiplayer_authority()),
			" bytes:", compressed.size(),
			" recording:", _recording)

	if compressed.is_empty():
		if not _warned_no_data and _ptt_hold_time >= no_data_warn_sec and debug_print:
			_warned_no_data = true
			print("WARN | No mic data after holding PTT for ", no_data_warn_sec, "s on uid:", multiplayer.get_unique_id(),
				" -> Steam voice is returning empty on this machine.")
		return

	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_voice_packet", compressed)

func _read_compressed_voice() -> PackedByteArray:
	var out := PackedByteArray()
	if _steam == null:
		return out
	if not _steam.has_method("getVoice"):
		if debug_print:
			print("ERR | Steam missing getVoice()")
		return out

	# Try getAvailableVoice if it exists, BUT treat <=0 (including -1) as "unknown"
	var avail: int = 0
	if _steam.has_method("getAvailableVoice"):
		avail = int(_steam.call("getAvailableVoice"))
		if debug_print:
			print("avail voice:", avail)

	# If avail is positive, request that many (capped). Otherwise, just pull max bytes.
	var want: int = max_compressed_bytes
	if avail > 0:
		want = mini(avail, max_compressed_bytes)

	var res: Variant = _steam.call("getVoice", want)
	return _extract_voice_buffer(res)

func _extract_voice_buffer(res: Variant) -> PackedByteArray:
	var out := PackedByteArray()

	# Dictionary shape
	if typeof(res) == TYPE_DICTIONARY:
		var d := res as Dictionary

		# Common: {"result": int, "buffer": PackedByteArray, "written": int}
		if d.has("buffer") and d["buffer"] is PackedByteArray:
			var bb: PackedByteArray = d["buffer"]
			var w: int = 0
			if d.has("written"):
				w = int(d["written"])
			elif d.has("size"):
				w = int(d["size"])
			if w > 0 and w <= bb.size():
				return bb.slice(0, w)
			return bb

		for k in ["data", "voice", "output"]:
			if d.has(k) and d[k] is PackedByteArray:
				return d[k] as PackedByteArray

		if debug_print:
			print("getVoice dict keys:", d.keys())
		return out

	# Array shape: [result, buffer] or [result, buffer, written]
	if typeof(res) == TYPE_ARRAY:
		var a := res as Array
		if a.size() >= 2 and a[1] is PackedByteArray:
			var bb2: PackedByteArray = a[1] as PackedByteArray
			if a.size() >= 3:
				var w2: int = int(a[2])
				if w2 > 0 and w2 <= bb2.size():
					return bb2.slice(0, w2)
			return bb2

		if debug_print:
			print("getVoice array size:", a.size(), " types:", _types_of_array(a))
		return out

	# Direct
	if res is PackedByteArray:
		return res as PackedByteArray

	if debug_print:
		print("getVoice unknown typeof:", typeof(res))
	return out

# =========================
#   RECEIVE / PLAY
# =========================
@rpc("any_peer", "call_local", "unreliable")
func _rpc_voice_packet(compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	var local_uid: int = multiplayer.get_unique_id()

	# Only ignore if YOU are the sender
	if sender_id == local_uid:
		return

	if debug_print:
		print("RECV | local:", local_uid, " from:", sender_id, " bytes:", compressed.size())

	_play_compressed_local(compressed)

func _play_compressed_local(compressed: PackedByteArray) -> void:
	if _steam == null:
		return
	if not _steam.has_method("decompressVoice"):
		push_error("Steam missing method decompressVoice")
		return
	if _playback == null:
		push_error("VoiceChat playback missing")
		return

	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)
	var pcm: PackedByteArray = _extract_pcm_bytes(res)

	if debug_print:
		print("PLAY | pcm bytes:", pcm.size())

	if pcm.is_empty():
		if debug_print:
			_debug_print_decompress_shape(res)
		return

	_push_pcm_to_playback(_playback, pcm)

func _extract_pcm_bytes(res: Variant) -> PackedByteArray:
	var out := PackedByteArray()

	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary

		if d.has("buffer") and d["buffer"] is PackedByteArray:
			var bb: PackedByteArray = d["buffer"]
			if d.has("written"):
				var w: int = int(d["written"])
				if w > 0 and w <= bb.size():
					return bb.slice(0, w)
			return bb

		for k in ["data", "pcm", "output", "uncompressed"]:
			if d.has(k) and d[k] is PackedByteArray:
				return d[k] as PackedByteArray

		return out

	if res is PackedByteArray:
		return res as PackedByteArray

	if typeof(res) == TYPE_ARRAY:
		var a: Array = res as Array
		if a.size() >= 3 and a[1] is PackedByteArray:
			var bb2: PackedByteArray = a[1] as PackedByteArray
			var w2: int = int(a[2])
			if w2 > 0 and w2 <= bb2.size():
				return bb2.slice(0, w2)
			return bb2
		if a.size() >= 2 and a[1] is PackedByteArray:
			return a[1] as PackedByteArray

	return out

func _push_pcm_to_playback(pb: AudioStreamGeneratorPlayback, pcm: PackedByteArray) -> void:
	var sample_count: int = pcm.size() / 2
	if sample_count <= 0:
		return

	var room: int = pb.get_frames_available()
	if debug_print:
		print("PUSH | frames:", room, " samples:", sample_count)

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
#   DEBUG
# =========================
func _debug_tick() -> void:
	var mp_on := multiplayer.has_multiplayer_peer()
	var local_uid: int = (multiplayer.get_unique_id() if mp_on else -1)
	var auth := _is_local_authority_player()
	var ptt_ok := (not push_to_talk) or InputMap.has_action(ptt_action)
	var ptt_pressed := false
	if ptt_ok and push_to_talk:
		ptt_pressed = Input.is_action_pressed(ptt_action)

	print("VOICE DBG | mp:", mp_on,
		" node_auth:", int(get_multiplayer_authority()),
		" local_uid:", local_uid,
		" local_auth:", auth,
		" ptt_ok:", ptt_ok,
		" ptt:", ptt_pressed,
		" recording:", _recording,
		" sr:", _sample_rate,
		" playback:", _playback != null)

func _debug_print_decompress_shape(res: Variant) -> void:
	print("DECOMP typeof:", typeof(res))
	if typeof(res) == TYPE_DICTIONARY:
		var d := res as Dictionary
		print("DECOMP keys:", d.keys())
		if d.has("result"):
			print("DECOMP result:", d["result"])
		if d.has("written"):
			print("DECOMP written:", d["written"])
	elif typeof(res) == TYPE_ARRAY:
		var a := res as Array
		print("DECOMP array size:", a.size(), " types:", _types_of_array(a))

func _types_of_array(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(typeof(v))
	return out
