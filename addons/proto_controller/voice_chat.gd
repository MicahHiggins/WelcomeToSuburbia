# res://voice_chat.gd
extends Node
class_name VoiceChat

@export var enable_voice: bool = true

# TOGGLE TALK (press V on/off)
@export var toggle_to_talk: bool = true
@export var ptt_action: StringName = &"voice" # bind to V in InputMap

# PERF
@export var send_rate_hz: float = 20.0
@export var max_compressed_bytes: int = 8192

# --- PROXIMITY (AudioStreamPlayer3D base settings) ---
@export var hear_radius: float = 80.0
@export var unit_size: float = 1.0
@export var base_volume_db: float = -2.0
@export var playback_buffer_sec: float = 0.28

# --- EXTRA PROXIMITY CURVE ---
@export var use_extra_distance_gain: bool = true
@export var near_boost_db: float = 7.0
@export var far_cut_db: float = -10.0
@export var gain_curve_pow: float = 2.2
@export var gain_update_hz: float = 10.0

# --- DISTANCE FX ---
@export var fx_start_m: float = 40.0
@export var fx_full_m: float = 80.0

@export var kid_pitch_near: float = 1.06
@export var kid_pitch_far: float = 1.00

@export var lowpass_near_hz: float = 11000.0
@export var lowpass_far_hz: float = 2200.0
@export var far_flutter_hz: float = 2.0
@export var far_flutter_amt: float = 0.010

@export var softclip_start: float = 0.00
@export var softclip_full: float = 0.18

# --- DIRECTIONALITY (works on all builds) ---
@export var force_point_source: bool = true # sets spread=0 if available
@export var directional_cone_enabled: bool = true
@export var cone_angle_deg: float = 130.0          # smaller = more directional
@export var cone_outside_atten_db: float = -10.0   # how quiet when behind/outside cone

# script is on Head, VoicePlayer3D is a child under Head
@export var voice_player_path: NodePath = NodePath("VoicePlayer3D")

# UI (small icon bottom)
@export var show_talk_icon: bool = true
@export var icon_anchor: Vector2 = Vector2(12.0, -14.0)
@export var icon_size: float = 18.0
@export var icon_color_off: Color = Color(1, 1, 1, 0.35)
@export var icon_color_on: Color = Color(1, 1, 1, 0.90)
@export var icon_outline_color: Color = Color(0, 0, 0, 0.75)
@export var icon_outline_px: int = 3

@export var debug_print: bool = false
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
var _listener_cam: Camera3D = null

# toggle state
var _talk_toggle_on: bool = false
var _toggle_prev_pressed: bool = false

# UI
var _ui_layer: CanvasLayer = null
var _icon_label: Label = null

func _enter_tree() -> void:
	_inherit_authority_from_owner()

func _ready() -> void:
	_steam = _get_steam_singleton()
	_steam_ok = _init_steam_voice()

	_voice_player = get_node_or_null(voice_player_path) as AudioStreamPlayer3D
	if _voice_player == null:
		push_error("VoiceChat: missing AudioStreamPlayer3D at " + str(voice_player_path))
		return

	_apply_voice_player_defaults()

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _sample_rate
	gen.buffer_length = playback_buffer_sec
	_voice_player.stream = gen
	_voice_player.play()

	_playback = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback

	if _is_local_authority_player() and show_talk_icon:
		_build_talk_icon_ui()
		_update_talk_icon()

	set_process(true)

func _apply_voice_player_defaults() -> void:
	_voice_player.max_distance = hear_radius
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice_player.unit_size = unit_size
	_voice_player.bus = &"voicechat"
	_voice_player.volume_db = base_volume_db
	_voice_player.stream_paused = false

	# tighter point-source = stronger left/right
	if force_point_source and ("spread" in _voice_player):
		_voice_player.spread = 0.0

	if "attenuation_filter_cutoff_hz" in _voice_player:
		_voice_player.attenuation_filter_cutoff_hz = lowpass_near_hz
	if "attenuation_filter_db" in _voice_player:
		_voice_player.attenuation_filter_db = -6.0

func _process(dt: float) -> void:
	if not enable_voice:
		_stop_recording_if_needed()
		if _is_local_authority_player():
			_talk_toggle_on = false
			_update_talk_icon()
		return

	_run_steam_callbacks_safe()

	if _listener_cam == null or not is_instance_valid(_listener_cam):
		_listener_cam = get_viewport().get_camera_3d()

	if _is_local_authority_player():
		_update_toggle_state()
		_capture_and_send_voice()
	else:
		_gain_t += dt
		var step: float = 1.0 / maxf(gain_update_hz, 1.0)
		if _gain_t >= step:
			_gain_t = 0.0
			if use_extra_distance_gain:
				_apply_extra_distance_gain()
			_apply_distance_fx()

	_dbg_t += dt
	if debug_print and _dbg_t >= debug_interval_sec:
		_dbg_t = 0.0
		_debug_tick()

# =========================
#   TOGGLE INPUT
# =========================
func _update_toggle_state() -> void:
	if not toggle_to_talk:
		return
	if not InputMap.has_action(ptt_action):
		return

	var pressed: bool = Input.is_action_pressed(ptt_action)
	if pressed and not _toggle_prev_pressed:
		_talk_toggle_on = not _talk_toggle_on
		_update_talk_icon()
	_toggle_prev_pressed = pressed

func _wants_talk() -> bool:
	if not enable_voice:
		return false
	if not _steam_ok:
		return false
	if not InputMap.has_action(ptt_action):
		return false
	return _talk_toggle_on

# =========================
#   UI ICON
# =========================
func _build_talk_icon_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "VoiceUI"
	_ui_layer.layer = 900
	add_child(_ui_layer)

	_icon_label = Label.new()
	_icon_label.name = "VoiceIcon"
	_icon_label.text = "🎙"
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_label.anchor_left = 0.0
	_icon_label.anchor_top = 1.0
	_icon_label.anchor_right = 0.0
	_icon_label.anchor_bottom = 1.0
	_icon_label.position = Vector2(icon_anchor.x, icon_anchor.y)
	_icon_label.add_theme_color_override("font_color", icon_color_off)
	_icon_label.add_theme_color_override("font_outline_color", icon_outline_color)
	_icon_label.add_theme_constant_override("outline_size", icon_outline_px)
	_icon_label.add_theme_font_size_override("font_size", int(icon_size))
	_ui_layer.add_child(_icon_label)

func _update_talk_icon() -> void:
	if _icon_label == null:
		return
	var c := icon_color_on if _talk_toggle_on else icon_color_off
	_icon_label.add_theme_color_override("font_color", c)

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
	if compressed.is_empty():
		return

	if multiplayer.has_multiplayer_peer():
		var speaker_auth: int = int(get_multiplayer_authority())
		rpc("_rpc_voice_packet", speaker_auth, compressed)

func _read_compressed_voice() -> PackedByteArray:
	var out := PackedByteArray()
	if _steam == null:
		return out

	if _steam.has_method("getVoice"):
		var res: Variant = _steam.call("getVoice", max_compressed_bytes)
		if typeof(res) == TYPE_DICTIONARY:
			var d: Dictionary = res as Dictionary
			var bb: PackedByteArray = (d.get("buffer", PackedByteArray()) as PackedByteArray)
			var w: int = int(d.get("written", 0))
			if w > 0 and w <= bb.size():
				return bb.slice(0, w)
			return bb
		if res is PackedByteArray:
			return res as PackedByteArray

	return out

# =========================
#   RECEIVE / PLAY (ROUTED)
# =========================
@rpc("any_peer", "call_local", "unreliable")
func _rpc_voice_packet(speaker_auth: int, compressed: PackedByteArray) -> void:
	if compressed.is_empty():
		return
	if _is_local_authority_player():
		return

	# only the speaker's own VoiceChat node should play it
	if int(get_multiplayer_authority()) != int(speaker_auth):
		return

	_play_compressed_local(compressed)

func _play_compressed_local(compressed: PackedByteArray) -> void:
	if _steam == null or not _steam.has_method("decompressVoice"):
		return
	if _playback == null:
		return

	var res: Variant = _steam.call("decompressVoice", compressed, _sample_rate)

	var pcm: PackedByteArray = PackedByteArray()
	var sz: int = 0

	if typeof(res) == TYPE_DICTIONARY:
		var d: Dictionary = res as Dictionary
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
	var sc: float = _current_softclip_amount()

	if pb.has_method("push_buffer"):
		var frames := PackedVector2Array()
		frames.resize(to_push)

		var idx: int = 0
		for i in range(to_push):
			var lo: int = int(pcm[idx])
			var hi: int = int(pcm[idx + 1])
			var s16: int = (hi << 8) | lo
			if s16 >= 32768:
				s16 -= 65536

			var f: float = float(s16) / 32768.0
			if sc > 0.0001:
				f = _softclip(f, sc)

			frames[i] = Vector2(f, f)
			idx += 2

		pb.call("push_buffer", frames)
		return

	var idx2: int = 0
	for i2 in range(to_push):
		var lo2: int = int(pcm[idx2])
		var hi2: int = int(pcm[idx2 + 1])
		var s162: int = (hi2 << 8) | lo2
		if s162 >= 32768:
			s162 -= 65536
		var f2: float = float(s162) / 32768.0
		if sc > 0.0001:
			f2 = _softclip(f2, sc)
		pb.push_frame(Vector2(f2, f2))
		idx2 += 2

func _softclip(x: float, amt: float) -> float:
	var k := 1.0 + amt * 6.0
	return tanh(x * k) / tanh(k)

# =========================
#   EXTRA DISTANCE GAIN + DISTANCE FX + DIRECTION CONE
# =========================
func _distance_to_listener() -> float:
	if _listener_cam == null or _voice_player == null:
		return 0.0
	return _listener_cam.global_position.distance_to(_voice_player.global_position)

func _fx_t() -> float:
	var d := _distance_to_listener()
	if d <= fx_start_m:
		return 0.0
	return clampf((d - fx_start_m) / maxf(0.001, (fx_full_m - fx_start_m)), 0.0, 1.0)

func _cone_atten_db() -> float:
	if not directional_cone_enabled:
		return 0.0
	if _listener_cam == null or _voice_player == null:
		return 0.0

	var to_listener: Vector3 = (_listener_cam.global_position - _voice_player.global_position)
	if to_listener.length() < 0.001:
		return 0.0
	to_listener = to_listener.normalized()

	var speaker_forward: Vector3 = (-_voice_player.global_transform.basis.z).normalized()

	var dotv: float = clampf(speaker_forward.dot(to_listener), -1.0, 1.0)
	var ang_deg: float = rad_to_deg(acos(dotv))

	var half: float = clampf(cone_angle_deg * 0.5, 5.0, 180.0)
	if ang_deg <= half:
		return 0.0

	var t: float = clampf((ang_deg - half) / maxf(0.001, (180.0 - half)), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t) # smoothstep
	return lerp(0.0, cone_outside_atten_db, t)

func _apply_extra_distance_gain() -> void:
	if _voice_player == null or _listener_cam == null:
		return

	var maxd: float = maxf(_voice_player.max_distance, 0.001)
	var d: float = _distance_to_listener()
	var t: float = clampf(d / maxd, 0.0, 1.0)

	var shaped: float = pow(t, gain_curve_pow)
	var extra_db: float = lerp(near_boost_db, far_cut_db, shaped)

	extra_db += _cone_atten_db()

	_voice_player.volume_db = base_volume_db + extra_db

func _apply_distance_fx() -> void:
	if _voice_player == null:
		return

	var t := _fx_t()

	var kid_pitch := lerp(kid_pitch_near, kid_pitch_far, t)
	var flutter := 0.0
	if t > 0.001:
		flutter = sin(Time.get_ticks_msec() * 0.001 * TAU * far_flutter_hz) * (far_flutter_amt * t)

	_voice_player.pitch_scale = maxf(0.01, kid_pitch + flutter)

	var lp := lerp(lowpass_near_hz, lowpass_far_hz, t)
	if "attenuation_filter_cutoff_hz" in _voice_player:
		_voice_player.attenuation_filter_cutoff_hz = lp

func _current_softclip_amount() -> float:
	var t := _fx_t()
	return lerp(softclip_start, softclip_full, t)

# =========================
#   DEBUG
# =========================
func _debug_tick() -> void:
	print("VOICE DBG | local_auth:", _is_local_authority_player(),
		" talk_on:", _talk_toggle_on,
		" recording:", _recording,
		" auth:", int(get_multiplayer_authority()),
		" cone_db:", _cone_atten_db(),
		" fx_t:", _fx_t())
