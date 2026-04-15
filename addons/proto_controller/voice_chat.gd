# res://voice_chat.gd
extends Node
class_name VoiceChat

@export var enable_voice: bool = true
@export var push_to_talk: bool = true
@export var ptt_action: StringName = &"voice"

@export var send_rate_hz: float = 30.0
@export var max_compressed_bytes: int = 16384

@export var hear_radius: float = 18.0
@export var unit_size: float = 1.0
@export var playback_buffer_sec: float = 0.70

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
	_voice_player.volume_db = 0.0
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
			" playback:", _playback != null)

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		return

	_run_steam_callbacks_safe()

	# ONLY the local authority player instance captures + broadcasts
	if _is_local_authority_player():
		_capture_and_send_voice()

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

	# Optional check (some builds return -1 or odd values; don't rely on it too hard)
	if _steam.has_method("getAvailableVoice"):
		var avail_res: Variant = _steam.call("getAvailableVoice")
		if typeof(avail_res) == TYPE_DICTIONARY:
			var ad: Dictionary = avail_res as Dictionary
			var abuf: PackedByteArray = (ad.get("buffer", PackedByteArray()) as PackedByteArray)
			# If there's no buffer available, early out
			if abuf.is_empty():
				# still fall through to getVoice on some builds? usually safe to return empty
				return out

	# Main fetch: getVoice(max_bytes) -> { result, buffer }
	if _steam.has_method("getVoice"):
		var res: Variant = _steam.call("getVoice", max_compressed_bytes)
		if typeof(res) == TYPE_DICTIONARY:
			var d: Dictionary = res as Dictionary
			var bb: PackedByteArray = (d.get("buffer", PackedByteArray()) as PackedByteArray)
			# Some builds include extra bytes; but generally buffer is already the correct length.
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
	# (This node instance is the speaker's node, so when you speak, you will also receive call_local.)
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

	# decompressVoice(compressed, desired_sample_rate) -> { result, uncompressed, size }
	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)
	if typeof(res) != TYPE_DICTIONARY:
		return

	var d: Dictionary = res as Dictionary
	var pcm: PackedByteArray = (d.get("uncompressed", PackedByteArray()) as PackedByteArray)
	var sz: int = int(d.get("size", pcm.size()))

	if sz > 0 and sz < pcm.size():
		pcm = pcm.slice(0, sz)

	if debug_print:
		print("DECOMP | from:", sender_id, " pcm:", pcm.size(), " size:", sz)

	if pcm.is_empty():
		return

	_push_pcm_to_playback(_playback, pcm)

func _push_pcm_to_playback(pb: AudioStreamGeneratorPlayback, pcm: PackedByteArray) -> void:
	# pcm = 16-bit signed little-endian mono
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

	if debug_print:
		print("PUSH | frames:", to_push, " room:", room, " samples:", sample_count)

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
		" buffer:", playback_buffer_sec)
