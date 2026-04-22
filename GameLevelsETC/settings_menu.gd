extends CanvasLayer

@onready var main_page = $MainPage
@onready var sound_page = $Sound
@onready var controls_page = $Controls


@onready var sound_button = $MainPage/Sound
@onready var controls_button = $MainPage/Controls
@onready var main_back_button = $MainPage/BackButton

@onready var music_slider = $Sound/MusicSlider
@onready var sfx_slider = $Sound/SFXSlider
@onready var soundscape_slider = $Sound/SoundScapeSlider
@onready var sound_back_button = $Sound/BackButton

@onready var actions_container = $Controls/VBoxContainer/ScrollContainer/ActionsContainer
@onready var controls_back_button = $Controls/VBoxContainer/BackButton

var opened_from: String = ""
var waiting_for_action: String = ""

var rebind_actions := {
	"Interact": "interact",
	"Quit / Back": "quit",
	"Free Fly": "freefly",
	"Sprint": "sprint",
	"Drop Item": "drop",
	"Use / Attack": "use-attack",
	"Toggle Flashlight": "toggle_flashlight",
	"Voice Chat": "voice",
	"Begin / Start": "begin"
}

func _ready() -> void:
	hide()
	show_main_page()

	sound_button.pressed.connect(_on_sound_button_pressed)
	controls_button.pressed.connect(_on_controls_button_pressed)
	main_back_button.pressed.connect(_on_main_back_pressed)

	sound_back_button.pressed.connect(_on_sound_back_pressed)
	controls_back_button.pressed.connect(_on_controls_back_pressed)

	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	soundscape_slider.value_changed.connect(_on_soundscape_slider_changed)

	load_bus_volumes_into_sliders()
	build_controls_menu()

func open_from(source: String) -> void:
	opened_from = source
	show()
	show_main_page()

func close_menu() -> void:
	waiting_for_action = ""
	hide()

func show_main_page() -> void:
	main_page.show()
	sound_page.hide()
	controls_page.hide()

func show_sound_page() -> void:
	main_page.hide()
	sound_page.show()
	controls_page.hide()

func show_controls_page() -> void:
	main_page.hide()
	sound_page.hide()
	controls_page.show()
	refresh_controls_menu()

func _on_sound_button_pressed() -> void:
	show_sound_page()

func _on_controls_button_pressed() -> void:
	show_controls_page()

func _on_main_back_pressed() -> void:
	close_menu()

func _on_sound_back_pressed() -> void:
	show_main_page()

func _on_controls_back_pressed() -> void:
	waiting_for_action = ""
	show_main_page()

# =========================
# AUDIO
# =========================

func load_bus_volumes_into_sliders() -> void:
	music_slider.value = db_to_slider(get_bus_volume_db_safe("Music"))
	sfx_slider.value = db_to_slider(get_bus_volume_db_safe("SFX"))
	soundscape_slider.value = db_to_slider(get_bus_volume_db_safe("SoundScape"))

func _on_music_slider_changed(value: float) -> void:
	set_bus_volume_from_slider("Music", value)

func _on_sfx_slider_changed(value: float) -> void:
	set_bus_volume_from_slider("SFX", value)

func _on_soundscape_slider_changed(value: float) -> void:
	set_bus_volume_from_slider("SoundScape", value)

func set_bus_volume_from_slider(bus_name: String, slider_value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		push_warning("Bus not found: " + bus_name)
		return

	var db := linear_to_db(max(slider_value, 0.0001))
	if slider_value <= 0.0:
		db = -80.0

	AudioServer.set_bus_volume_db(bus_index, db)

func get_bus_volume_db_safe(bus_name: String) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		push_warning("Bus not found: " + bus_name)
		return 0.0
	return AudioServer.get_bus_volume_db(bus_index)

func db_to_slider(db: float) -> float:
	if db <= -80.0:
		return 0.0
	return db_to_linear(db)

# =========================
# CONTROLS
# =========================

func build_controls_menu() -> void:
	# Clear old rows
	for child in actions_container.get_children():
		child.queue_free()

	# Load your font once
	var font = load("res://addons/Font/GimletDisplay-Regular-Testing.otf")
	var font_size = 28

	for display_name in rebind_actions.keys():
		var action_name = rebind_actions[display_name]

		# Whole row
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, 60)

		# Action name label
		var action_label := Label.new()
		action_label.text = display_name
		action_label.custom_minimum_size = Vector2(190, 60)
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action_label.add_theme_font_override("font", font)
		action_label.add_theme_font_size_override("font_size", font_size)

		# Rebind button
		var key_button := Button.new()
		key_button.name = action_name
		key_button.text = get_action_display_text(action_name)
		key_button.custom_minimum_size = Vector2(260, 60)
		key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_button.add_theme_font_override("font", font)
		key_button.add_theme_font_size_override("font_size", font_size)
		key_button.pressed.connect(_on_rebind_button_pressed.bind(action_name))

		row.add_child(action_label)
		row.add_child(key_button)
		actions_container.add_child(row)

func refresh_controls_menu() -> void:
	for row in actions_container.get_children():
		for child in row.get_children():
			if child is Button:
				child.text = get_action_display_text(child.name)

func _on_rebind_button_pressed(action_name: String) -> void:
	waiting_for_action = action_name

	for row in actions_container.get_children():
		for child in row.get_children():
			if child is Button:
				if child.name == action_name:
					child.text = "Press any key..."
				else:
					child.text = get_action_display_text(child.name)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if waiting_for_action != "":
			if event.keycode == KEY_ESCAPE:
				waiting_for_action = ""
				refresh_controls_menu()
				get_viewport().set_input_as_handled()
				return

			rebind_action(waiting_for_action, event)
			waiting_for_action = ""
			refresh_controls_menu()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_ESCAPE:
			if controls_page.visible:
				_on_controls_back_pressed()
			elif sound_page.visible:
				_on_sound_back_pressed()
			elif main_page.visible:
				_on_main_back_pressed()

			get_viewport().set_input_as_handled()

func rebind_action(action_name: String, event: InputEventKey) -> void:
	var old_events = InputMap.action_get_events(action_name)

	for old_event in old_events:
		if old_event is InputEventKey:
			InputMap.action_erase_event(action_name, old_event)

	InputMap.action_add_event(action_name, event)

func get_action_display_text(action_name: String) -> String:
	var events = InputMap.action_get_events(action_name)

	for event in events:
		if event is InputEventKey:
			return event.as_text_physical_keycode()

	return "Unassigned"
