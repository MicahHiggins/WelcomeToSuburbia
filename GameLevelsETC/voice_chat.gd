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

# put VoicePlayer3D under Head so it follows the head
@export var voice_player_path: NodePath = NodePath("../Head/VoicePlayer3D")

var _steam: Object
var _steam_ok: bool = false
var _sample_rate: int = 48000

var _recording: bool = false
var _last_send_t: float = 0.0

var _voice_player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	_steam = _get_steam_singleton()
	_steam_ok = _init_steam_voice()

	_voice_player = get_node_or_null(voice_player_path) as AudioStreamPlayer3D
	if _voice_player == null:
		push_error("VoiceChat: missing VoicePlayer3D at voice_player_path: " + str(voice_player_path))
		return

	# set up 3D proximity
	_voice_player.max_distance = hear_radius
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_player.unit_size = unit_size

	# set up generator playback (for decoded PCM)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _sample_rate
	gen.buffer_length = playback_buffer_sec
	_voice_player.stream = gen
	_voice_player.play()

	_playback = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback

	# IMPORTANT:
	# only the local authority player captures + sends voice
	set_process(_is_local_authority_player())

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		return

	_run_steam_callbacks_safe()
	_capture_and_send_voice()

# =========================
#   AUTHORITY HELPERS
# =========================
func _is_local_authority_player() -> bool:
	# if no multiplayer, allow capture (singleplayer test)
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()

# =========================
#        STEAM SETUP
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
#     RECORD / SEND VOICE
# =========================
func _wants_talk() -> bool:
	if not enable_voice:
		return false
	if not _steam_ok:
		return false

	if push_to_talk:
		# don't hard-error if the action is missing
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
	if compressed.is_empty():
		return

	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_voice_packet", compressed)

func _read_compressed_voice() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	if _steam == null:
		return out

	if _steam.has_method("getAvailableVoice"):
		var avail: int = int(_steam.call("getAvailableVoice"))
		if avail <= 0:
			return out
		var want: int = mini(avail, max_compressed_bytes)
		if _steam.has_method("getVoice"):
			var res: Variant = _steam.call("getVoice", want)
			return _extract_voice_buffer(res)

	if _steam.has_method("getVoice"):
		var res2: Variant = _steam.call("getVoice", max_compressed_bytes)
		return _extract_voice_buffer(res2)

	return out

func _extract_voice_buffer(res: Variant) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()

	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary
		if d.has("buffer") and d["buffer"] is PackedByteArray:
			var bb: PackedByteArray = d["buffer"]
			if d.has("written"):
				var w: int = int(d["written"])
				if w > 0 and w <= bb.size():
					return bb.slice(0, w)
			return bb
		if d.has("data") and d["data"] is PackedByteArray:
			return d["data"]

	if res is PackedByteArray:
		return res as PackedByteArray

	if typeof(res) == TYPE_ARRAY:
		var a: Array = res as Array
		if a.size() >= 2 and a[1] is PackedByteArray:
			return a[1] as PackedByteArray

	return out

# =========================
#      RECEIVE / PLAY
# =========================
@rpc("any_peer", "call_local", "unreliable")
func _rpc_voice_packet(compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return

	# this node belongs to the speaking player.
	# don't play your own voice locally.
	if _is_local_authority_player():
		return

	_play_compressed_local(compressed)

func _play_compressed_local(compressed: PackedByteArray) -> void:
	if _steam == null:
		return
	if not _steam.has_method("decompressVoice"):
		return
	if _playback == null:
		return

	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)
	var pcm: PackedByteArray = _extract_pcm_bytes(res)
	if pcm.is_empty():
		return

	_push_pcm_to_playback(_playback, pcm)

func _extract_pcm_bytes(res: Variant) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()

	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary
		if d.has("buffer") and d["buffer"] is PackedByteArray:
			var bb: PackedByteArray = d["buffer"]
			if d.has("written"):
				var w: int = int(d["written"])
				if w > 0 and w <= bb.size():
					return bb.slice(0, w)
			return bb
		if d.has("data") and d["data"] is PackedByteArray:
			return d["data"]

	if res is PackedByteArray:
		return res as PackedByteArray

	if typeof(res) == TYPE_ARRAY:
		var a: Array = res as Array
		if a.size() >= 2 and a[1] is PackedByteArray:
			return a[1] as PackedByteArray

	return out

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
