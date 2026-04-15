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

@export var follow_camera_if_possible: bool = true

var _steam: Object
var _steam_ok: bool = false
var _sample_rate: int = 48000

var _recording: bool = false
var _last_send_t: float = 0.0

# peer_id(int) -> {"player": AudioStreamPlayer3D, "playback": AudioStreamGeneratorPlayback}
var _voice_out: Dictionary = {}

func _ready() -> void:
	_steam = _get_steam_singleton()
	_steam_ok = _init_steam_voice()
	set_process(true)

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		return

	_run_steam_callbacks_safe()
	_update_remote_voice_positions()
	_capture_and_send_voice()

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

	# prefer getAvailableVoice() -> int
	if _steam.has_method("getAvailableVoice"):
		var avail: int = int(_steam.call("getAvailableVoice"))
		if avail <= 0:
			return out
		var want: int = mini(avail, max_compressed_bytes)
		if _steam.has_method("getVoice"):
			var res: Variant = _steam.call("getVoice", want)
			return _extract_voice_buffer(res)

	# fallback: try getVoice() directly
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
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return

	_play_remote_packet(sender_id, compressed)

func _play_remote_packet(peer_id: int, compressed: PackedByteArray) -> void:
	if _steam == null:
		return
	if not _steam.has_method("decompressVoice"):
		return

	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)
	var pcm: PackedByteArray = _extract_pcm_bytes(res)
	if pcm.is_empty():
		return

	var pb: AudioStreamGeneratorPlayback = _ensure_voice_player(peer_id)
	if pb == null:
		return

	_push_pcm_to_playback(pb, pcm)

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

func _ensure_voice_player(peer_id: int) -> AudioStreamGeneratorPlayback:
	if _voice_out.has(peer_id):
		var d0: Dictionary = _voice_out[peer_id] as Dictionary
		if d0.has("playback") and d0["playback"] is AudioStreamGeneratorPlayback:
			return d0["playback"] as AudioStreamGeneratorPlayback

	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.name = "Voice_%s" % str(peer_id)
	p.max_distance = hear_radius
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = unit_size

	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = _sample_rate
	gen.buffer_length = playback_buffer_sec
	p.stream = gen

	add_child(p)
	p.play()

	var pb: AudioStreamGeneratorPlayback = p.get_stream_playback() as AudioStreamGeneratorPlayback
	_voice_out[peer_id] = {"player": p, "playback": pb}
	return pb

func _push_pcm_to_playback(pb: AudioStreamGeneratorPlayback, pcm: PackedByteArray) -> void:
	if pb == null:
		return

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
#   PROXIMITY POSITIONING
# =========================
func _update_remote_voice_positions() -> void:
	if _voice_out.is_empty():
		return

	for k in _voice_out.keys():
		var peer_id: int = int(k)
		var d: Dictionary = _voice_out[peer_id] as Dictionary
		var p: AudioStreamPlayer3D = d.get("player", null) as AudioStreamPlayer3D
		if p == null:
			continue

		var pl: Node3D = _find_player_node(peer_id)
		if pl == null:
			continue

		if follow_camera_if_possible:
			var cam: Camera3D = pl.find_child("Camera3D", true, false) as Camera3D
			if cam != null:
				p.global_position = cam.global_position
				continue

		p.global_position = pl.global_position

func _find_player_node(peer_id: int) -> Node3D:
	var players: Array = get_tree().get_nodes_in_group("player")
	for any_p in players:
		var pl: Node3D = any_p as Node3D
		if pl == null:
			continue
		if int(pl.get_multiplayer_authority()) == peer_id:
			return pl
	return null
