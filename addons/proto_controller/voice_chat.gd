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
var _registered: bool = false
var _last_registered_peer_id: int = -1

func _enter_tree() -> void:
	_inherit_authority_from_owner()

func _ready() -> void:
	_steam = _get_steam_singleton()
	_steam_ok = _init_steam_voice()

	_voice_player = get_node_or_null(voice_player_path) as AudioStreamPlayer3D
	if _voice_player == null:
		push_error("VoiceChat: missing AudioStreamPlayer3D at " + str(voice_player_path))
		return

	# 3D attenuation / proximity
	_voice_player.max_distance = hear_radius
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_player.unit_size = unit_size
	_voice_player.bus = &"Master"
	_voice_player.volume_db = 0.0
	_voice_player.stream_paused = false

	# generator stream for decoded PCM
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = _sample_rate
	gen.buffer_length = playback_buffer_sec
	_voice_player.stream = gen
	_voice_player.play()

	_playback = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback

	set_process(true)

	_try_register_with_voicenet(true)

	if debug_print:
		print("VoiceChat ready | node_auth:", int(get_multiplayer_authority()),
			" local_uid:", (_local_uid()),
			" local_auth:", _is_local_authority_player(),
			" steam_ok:", _steam_ok,
			" sr:", _sample_rate,
			" playback:", _playback != null)

func _exit_tree() -> void:
	_unregister_from_voicenet()

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		return

	# keep authority synced (some spawners set authority after instancing)
	_inherit_authority_from_owner()

	_try_register_with_voicenet(false)
	_run_steam_callbacks_safe()

	# ONLY local authority captures + sends
	if _is_local_authority_player():
		_capture_and_send_voice()

	_dbg_t += dt
	if debug_print and _dbg_t >= debug_interval_sec:
		_dbg_t = 0.0
		_debug_tick()

# =========================
#   REGISTER WITH VoiceNet
# =========================
func _has_voicenet_autoload() -> bool:
	return get_tree() != null and get_tree().root != null and get_tree().root.has_node("VoiceNet")

func _try_register_with_voicenet(force: bool) -> void:
	if not _has_voicenet_autoload():
		return

	var owner_player: Node = _find_owner_player_node()
	if owner_player == null:
		return

	var my_peer_id: int = int(owner_player.get_multiplayer_authority())
	if my_peer_id <= 0:
		return

	# Re-register if authority changed (common during multiplayer spawn setup)
	if _registered and my_peer_id == _last_registered_peer_id and not force:
		return

	# If we were registered under an old id, unregister first
	if _registered and _last_registered_peer_id != my_peer_id:
		_unregister_from_voicenet()

	# Call autoload directly (no typeof checks; avoids Variant typing issues)
	VoiceNet.register_voice_target(my_peer_id, self)
	_registered = true
	_last_registered_peer_id = my_peer_id

	if debug_print:
		print("VoiceChat | registered with VoiceNet as peer:", my_peer_id, " node_auth:", int(get_multiplayer_authority()))

func _unregister_from_voicenet() -> void:
	if not _registered:
		return
	if not _has_voicenet_autoload():
		_registered = false
		_last_registered_peer_id = -1
		return

	var pid: int = _last_registered_peer_id
	if pid <= 0:
		_registered = false
		_last_registered_peer_id = -1
		return

	VoiceNet.unregister_voice_target(pid, self)
	_registered = false
	_last_registered_peer_id = -1

	if debug_print:
		print("VoiceChat | unregistered from VoiceNet peer:", pid)

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

func _local_uid() -> int:
	if multiplayer.has_multiplayer_peer():
		return int(multiplayer.get_unique_id())
	return -1

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
	push_error("Steam engine singleton not found.")
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
	if not _is_local_authority_player():
		return

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
		print("SEND | uid:", _local_uid(), " auth:", int(get_multiplayer_authority()), " bytes:", compressed.size(), " recording:", _recording)

	if compressed.is_empty():
		return

	if _has_voicenet_autoload():
		VoiceNet.send_voice(compressed)

func _read_compressed_voice() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	if _steam == null:
		return out
	if not _steam.has_method("getVoice"):
		return out

	var want: int = max_compressed_bytes

	# optional avail; can be -1 on some builds
	if _steam.has_method("getAvailableVoice"):
		var avail: int = int(_steam.call("getAvailableVoice"))
		if avail > 0:
			want = mini(avail, max_compressed_bytes)

	var res: Variant = _steam.call("getVoice", want)
	return _extract_voice_buffer(res)

func _extract_voice_buffer(res: Variant) -> PackedByteArray:
	# Dictionary form
	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary

		if d.has("buffer") and d["buffer"] is PackedByteArray:
			var bb: PackedByteArray = d["buffer"] as PackedByteArray
			var w: int = 0
			if d.has("written"):
				w = int(d["written"])
			if w > 0 and w <= bb.size():
				return bb.slice(0, w)
			return bb

		if d.has("data") and d["data"] is PackedByteArray:
			return d["data"] as PackedByteArray

	# Array form
	if typeof(res) == TYPE_ARRAY:
		var a: Array = res as Array
		if a.size() >= 2 and a[1] is PackedByteArray:
			var bb2: PackedByteArray = a[1] as PackedByteArray
			if a.size() >= 3:
				var w2: int = int(a[2])
				if w2 > 0 and w2 <= bb2.size():
					return bb2.slice(0, w2)
			return bb2

	# Raw bytes form
	if res is PackedByteArray:
		return res as PackedByteArray

	return PackedByteArray()

# =========================
#   RECEIVE (called by VoiceNet)
# =========================
func _voice_receive_compressed(sender_id: int, compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return
	if _steam == null or not _steam.has_method("decompressVoice"):
		return
	if _playback == null:
		return

	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)
	var pcm: PackedByteArray = _extract_pcm_bytes(res)

	if debug_print:
		print("RECV->PLAY | local_uid:", _local_uid(), " node_auth:", int(get_multiplayer_authority()),
			" from:", sender_id, " pcm:", pcm.size())

	if pcm.is_empty():
		return

	_push_pcm_to_playback(_playback, pcm)

func _extract_pcm_bytes(res: Variant) -> PackedByteArray:
	# Dictionary form
	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary

		if d.has("buffer") and d["buffer"] is PackedByteArray:
			var bb: PackedByteArray = d["buffer"] as PackedByteArray
			var w: int = 0
			if d.has("written"):
				w = int(d["written"])
			if w > 0 and w <= bb.size():
				return bb.slice(0, w)
			return bb

		if d.has("data") and d["data"] is PackedByteArray:
			return d["data"] as PackedByteArray

	# Array form
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

	# Raw bytes form
	if res is PackedByteArray:
		return res as PackedByteArray

	return PackedByteArray()

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
#   DEBUG
# =========================
func _debug_tick() -> void:
	var mp_on: bool = multiplayer.has_multiplayer_peer()
	var uid: int = _local_uid()

	var ptt_ok: bool = (not push_to_talk) or InputMap.has_action(ptt_action)
	var ptt_pressed: bool = false
	if push_to_talk and ptt_ok:
		ptt_pressed = Input.is_action_pressed(ptt_action)

	print("VOICE DBG | mp:", mp_on,
		" node_auth:", int(get_multiplayer_authority()),
		" local_uid:", uid,
		" local_auth:", _is_local_authority_player(),
		" registered:", _registered,
		" reg_peer:", _last_registered_peer_id,
		" ptt:", ptt_pressed,
		" recording:", _recording,
		" sr:", _sample_rate,
		" buffer:", playback_buffer_sec)
