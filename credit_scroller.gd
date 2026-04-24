extends CanvasLayer
class_name CreditsScroller

@export var auto_start: bool = false

# timing
@export var title_hold_sec: float = 1.25
@export var start_delay_sec: float = 0.35
@export var scroll_speed_px_per_sec: float = 55.0
@export var end_hold_sec: float = 2.0

# content
@export var big_thanks_text: String = "THANK YOU FOR PLAYING!"

# paste your real credits here (BBCode supported)
@export_multiline var credits_bbcode: String = "[center][b]CREDITS[/b][/center]\n\n[center]CREDITS\nCREDITS\nCREDITS\nCREDITS\nCREDITS\nCREDITS\nCREDITS\nCREDITS\nCREDITS\nCREDITS\n[/center]\n"

# visuals
@export var bg_alpha: float = 0.90
@export var force_top_layer: int = 20000
@export var block_input_while_playing: bool = true

@export var side_padding_px: int = 120
@export var credits_top_padding_px: int = 200
@export var credits_bottom_padding_px: int = 1400

# font sizes
@export var title_font_size: int = 84
@export var credits_font_size: int = 36
@export var credits_bold_font_size: int = 44

var _playing := false

var _bg: ColorRect
var _title_layer: Control
var _title_label: Label

var _scroll: ScrollContainer
var _margin: MarginContainer
var _vbox: VBoxContainer
var _top_spacer: Control
var _credits_rich: RichTextLabel
var _bottom_spacer: Control

func _ready() -> void:
	layer = force_top_layer
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_ui()
	_apply_layout()

	if auto_start:
		call_deferred("play")

func _build_ui() -> void:
	if _bg != null and is_instance_valid(_bg):
		return

	_bg = ColorRect.new()
	_bg.name = "BG"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0, 0, 0, clampf(bg_alpha, 0.0, 1.0))
	_bg.mouse_filter = (Control.MOUSE_FILTER_STOP if block_input_while_playing else Control.MOUSE_FILTER_IGNORE)
	add_child(_bg)

	_title_layer = Control.new()
	_title_layer.name = "TitleLayer"
	_title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_layer)

	_title_label = Label.new()
	_title_label.name = "BigThanks"
	_title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(_title_label)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = (Control.MOUSE_FILTER_STOP if block_input_while_playing else Control.MOUSE_FILTER_IGNORE)
	add_child(_scroll)

	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_margin)

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_vbox.add_theme_constant_override("separation", 24)
	_margin.add_child(_vbox)

	_top_spacer = Control.new()
	_top_spacer.name = "TopSpacer"
	_top_spacer.custom_minimum_size = Vector2(0, credits_top_padding_px)
	_vbox.add_child(_top_spacer)

	_credits_rich = RichTextLabel.new()
	_credits_rich.name = "CreditsText"
	_credits_rich.bbcode_enabled = true
	_credits_rich.fit_content = true
	_credits_rich.scroll_active = false
	_credits_rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_credits_rich.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_credits_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_credits_rich)

	_bottom_spacer = Control.new()
	_bottom_spacer.name = "BottomSpacer"
	_bottom_spacer.custom_minimum_size = Vector2(0, credits_bottom_padding_px)
	_vbox.add_child(_bottom_spacer)

	_title_layer.visible = false
	_scroll.visible = false

func _apply_layout() -> void:
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	_credits_rich.add_theme_font_size_override("normal_font_size", credits_font_size)
	_credits_rich.add_theme_font_size_override("bold_font_size", credits_bold_font_size)

func _force_to_viewport_root() -> void:
	var root := get_tree().root
	if root != null and get_parent() != root:
		reparent(root)
	layer = force_top_layer

func _sync_width_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var w := int(vp.size.x)

	_margin.add_theme_constant_override("margin_left", side_padding_px)
	_margin.add_theme_constant_override("margin_right", side_padding_px)
	_margin.add_theme_constant_override("margin_top", 0)
	_margin.add_theme_constant_override("margin_bottom", 0)

	_margin.custom_minimum_size.x = w
	_vbox.custom_minimum_size.x = max(0, w - side_padding_px * 2)
	_credits_rich.custom_minimum_size.x = max(0, w - side_padding_px * 2)

func _set_credits_text() -> void:
	_top_spacer.custom_minimum_size.y = credits_top_padding_px
	_bottom_spacer.custom_minimum_size.y = credits_bottom_padding_px

	_credits_rich.clear()
	_credits_rich.append_text(credits_bbcode)

func play() -> void:
	if _playing:
		return

	_playing = true
	_force_to_viewport_root()
	visible = true

	_title_label.text = big_thanks_text
	_title_layer.visible = true
	_scroll.visible = false

	await get_tree().process_frame

	if title_hold_sec > 0.0:
		await get_tree().create_timer(title_hold_sec).timeout

	_title_layer.visible = false
	_scroll.visible = true

	_set_credits_text()

	# let layout settle, then lock widths so it doesn't collapse to a thin line
	await get_tree().process_frame
	_sync_width_to_viewport()
	await get_tree().process_frame
	_sync_width_to_viewport()

	_scroll.scroll_vertical = 0

	if start_delay_sec > 0.0:
		await get_tree().create_timer(start_delay_sec).timeout

	while _playing:
		await get_tree().process_frame
		var dt := get_process_delta_time()

		var sb := _scroll.get_v_scroll_bar()
		var max_scroll := int(max(0.0, sb.max_value - sb.page))
		if max_scroll <= 0:
			break

		_scroll.scroll_vertical += int(scroll_speed_px_per_sec * dt)
		if _scroll.scroll_vertical >= max_scroll:
			break

	if end_hold_sec > 0.0:
		await get_tree().create_timer(end_hold_sec).timeout

	hide_credits()

func hide_credits() -> void:
	visible = false
	_playing = false
