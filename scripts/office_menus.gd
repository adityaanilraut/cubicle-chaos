class_name OfficeMenus
extends CanvasLayer

const SETTINGS_PATH := "user://office_settings.cfg"
const DEFAULT_SETTINGS := {
	"lighting": 0, "theme": 0, "show_labels": true, "interaction_hints": true,
	"floor_color": "", "floor_pattern": 0, "floor_texture": 0,
	"shadows": true, "camera_zoom": 12.0, "simulation_speed": 0,
	"max_outings": 2, "stand_gap_seconds": 1.25, "sound": true,
	"ui_scale": 1.0, "high_contrast": false, "bindings": {}
}

var office: Node3D
var menu_state: StringName = &"title"
var settings_return_state: StringName = &"title"
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var has_started := false
var pause_on_focus_loss := true
var overlay: Control
var content: VBoxContainer
var menu_panel: PanelContainer
var iris: ColorRect
var iris_material: ShaderMaterial
var transitioning := false
var _first_button: Button
var save_status: Label
var _capturing_action := ""
var _binding_buttons: Dictionary = {}
var _intro_checked := false
var _replay_intro := false

func setup(p_office: Node3D, open_title := true) -> void:
	office = p_office
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_build_overlay()
	if open_title:
		return_to_title()
	else:
		start_game()

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	iris = ColorRect.new()
	iris.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float radius = 0.0; void fragment() { vec2 p = (UV - vec2(0.5)) / SCREEN_PIXEL_SIZE; float outside = step(radius, length(p)); COLOR = vec4(0.055, 0.085, 0.12, outside); }"
	iris_material = ShaderMaterial.new()
	iris_material.shader = shader
	iris.material = iris_material
	overlay.add_child(iris)
	var panel := PanelContainer.new()
	menu_panel = panel
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.20
	panel.anchor_right = 0.80
	panel.anchor_top = 0.075
	panel.anchor_bottom = 0.925
	var style := StyleBoxFlat.new()
	style.bg_color = Color("141e2c")
	style.border_color = Color("4b5562")
	style.set_border_width_all(1)
	style.border_width_top = 4
	style.set_corner_radius_all(18)
	style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

func _clear_content() -> void:
	_capturing_action = ""
	_binding_buttons.clear()
	for node in content.get_children():
		content.remove_child(node)
		node.queue_free()
	_first_button = null
	save_status = null

func _label(text: String, size := 16, color := Color("d9e0e9")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func _button(text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e1b66d") if primary else Color("253246")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color("15202d") if primary else Color("f5f7fa"))
	button.add_theme_color_override("font_hover_color", Color("15202d") if primary else Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color("15202d") if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("15202d") if primary else Color.WHITE)
	button.pressed.connect(func(): OfficeAudio.play_at(office.get_tree(), "click", Vector3.ZERO))
	button.pressed.connect(action)
	content.add_child(button)
	if _first_button == null:
		_first_button = button
	return button

func _set_state(next: StringName) -> void:
	menu_state = next
	var playing := next == &"playing"
	get_tree().paused = not playing
	overlay.visible = not playing
	office.hud.visible = playing
	if is_instance_valid(office.player) and office.player.has_method("set_gameplay_visible"):
		office.player.set_gameplay_visible(playing)
	# Mouse release can arrive while paused. Clear drag flags to prevent a jump on resume.
	office.iso_camera._is_panning_drag = false
	office.iso_camera._is_rotating_drag = false
	if not playing and _first_button != null:
		_first_button.grab_focus()
	elif playing:
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func _animate_iris(opening: bool) -> void:
	transitioning = true
	menu_panel.visible = false
	overlay.visible = true
	var max_radius := get_viewport().get_visible_rect().size.length()
	iris_material.set_shader_parameter("radius", 0.0 if opening else max_radius)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(value: float): iris_material.set_shader_parameter("radius", value), 0.0 if opening else max_radius, max_radius if opening else 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	transitioning = false
	if opening:
		overlay.visible = false
	else:
		menu_panel.visible = true
		if is_instance_valid(_first_button): _first_button.grab_focus()

func start_game() -> void:
	if transitioning or menu_state == &"playing": return
	has_started = true
	_set_state(&"playing")
	if _replay_intro:
		_replay_intro = false
		_intro_checked = true
		office.intro.start_intro()
	elif not _intro_checked:
		_intro_checked = true
		if office.start_in_menu:
			office.intro.start_if_new()
	# Resume immediately so input cannot be lost during a menu transition.
	menu_panel.visible = true
	transitioning = false

func pause_game() -> void:
	if menu_state != &"playing" or transitioning: return
	_show_pause_menu()

func _show_pause_menu() -> void:
	_clear_content()
	_label("SHIFT PAUSED", 40, Color.WHITE)
	_button("Continue level", start_game, true)
	_button("Settings", show_settings)
	_button("Return to level menu", return_to_title)
	iris_material.set_shader_parameter("radius", 0.0)
	menu_panel.visible = true
	_set_state(&"paused")

func return_to_title(animated := false) -> void:
	if transitioning: return
	var dialogue = office.player.get("dialogue")
	if dialogue != null: dialogue.close()
	var equipment = office.player.get("equipment")
	if equipment != null: equipment.cancel()
	office.cancel_current_action()
	office.player.release_furniture()
	_clear_content()
	_label("A LITTLE WORK. A LITTLE LIFE.", 14, Color("e1b66d"))
	_label("CUBICLE CHAOS", 56, Color.WHITE)
	_label("Your day, one small task at a time.", 20, Color("c5d3d7"))
	content.add_child(HSeparator.new())
	_button("Continue level %d" % office.levels.level if has_started else "Start level 1", start_game, true)
	_label("CHOOSE A LEVEL", 14, Color("e1b66d"))
	for level_number in range(1, 6):
		var button := _button("%02d   %s" % [level_number, LevelObjectives.NAMES[level_number - 1]], func():
			office.levels.set_level(level_number)
			start_game()
		)
		button.custom_minimum_size.y = 38
		button.disabled = level_number > office.levels.unlocked
	_button("Settings", show_settings)
	_button("Credits & licenses", show_credits)
	_button("Replay introduction", func():
		_replay_intro = true
		start_game()
	)
	_label("WASD to move  •  %s to interact  •  %s to pick up box  •  %s to place  •  Esc for menu" % [OfficeInput.key_name("interact"), OfficeInput.key_name("prop"), OfficeInput.key_name("place")], 14, Color("9caec3"))
	_set_state(&"title")
	if animated:
		_animate_iris(false)
	else:
		iris_material.set_shader_parameter("radius", 0.0)
		menu_panel.visible = true

func show_credits() -> void:
	if transitioning: return
	_clear_content()
	_label("CUBICLE CHAOS  /  CREDITS", 14, Color("e1b66d"))
	_label("Made with open tools and assets.", 30, Color.WHITE)
	var credits := TextEdit.new()
	credits.name = "LicenseText"
	credits.text = OfficeLicenses.text()
	credits.editable = false
	credits.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	credits.custom_minimum_size.y = 360
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits.add_theme_font_size_override("font_size", 14)
	content.add_child(credits)
	_button("Back", return_to_title, true)
	_set_state(&"credits")

func show_settings() -> void:
	if menu_state == &"settings":
		return
	settings_return_state = &"title" if menu_state == &"title" else &"paused"
	_clear_content()
	_label("CUBICLE CHAOS  /  PREFERENCES", 14, Color("e1b66d"))
	_label("Make yourself at home.", 34, Color.WHITE)
	_label("Changes apply immediately and are saved for your next visit.", 15)
	_option("Office theme (one floor colour everywhere)", "theme", OfficeTheme.theme_names())
	_option("Lighting", "lighting", ["Daylight", "Soft daylight", "Golden afternoon"])
	_toggle("Sound effects", "sound")
	_toggle("Coworker labels while editing", "show_labels")
	_toggle("Nearby action circles and white highlights", "interaction_hints")
	_toggle("Shadows", "shadows")
	_option("Simulation speed", "simulation_speed", ["1×  Everyday pace", "2×  Busy day", "3×  Fast forward"])
	_number_option("Coworkers on break at once", "max_outings", 1.0, 4.0, 1.0)
	_number_option("Gap between stand-ups (seconds)", "stand_gap_seconds", 0.5, 3.0, 0.25)
	_label("Camera distance", 16)
	var zoom := HSlider.new()
	zoom.min_value = IsometricCamera.MIN_ZOOM
	zoom.max_value = IsometricCamera.MAX_ZOOM
	zoom.step = 0.5
	zoom.value = office.iso_camera.target_zoom
	zoom.custom_minimum_size.y = 28
	zoom.value_changed.connect(func(value: float): set_setting("camera_zoom", value))
	content.add_child(zoom)
	content.add_child(HSeparator.new())
	_label("ACCESSIBILITY", 14, Color("e1b66d"))
	_label("Interface size", 16)
	var ui_scale := HSlider.new()
	ui_scale.min_value = 0.8
	ui_scale.max_value = 1.5
	ui_scale.step = 0.05
	ui_scale.value = float(settings["ui_scale"])
	ui_scale.custom_minimum_size.y = 28
	ui_scale.value_changed.connect(func(value: float): set_setting("ui_scale", snappedf(value, 0.05)))
	content.add_child(ui_scale)
	_toggle("High-contrast highlights (yellow, thicker outlines)", "high_contrast")
	_label("Controls — select a key, then press the new key. Esc cancels. Movement, Run, Pause, zoom and save/load keys stay fixed.", 13, Color("9caec3"))
	_binding_buttons.clear()
	for action_id in OfficeInput.action_ids():
		_binding_row(action_id)
	var reset_keys := _button("Reset controls to defaults", func(): set_setting("bindings", {}))
	reset_keys.custom_minimum_size.y = 36
	_button("Back", close_settings, true)
	var reset := _button("Restore defaults", restore_defaults)
	reset.custom_minimum_size.y = 36
	save_status = _label("Esc to go back  •  Your shift stays paused", 13, Color("9caec3"))
	_set_state(&"settings")

func _option(title: String, key: String, values: Array) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	for text in values:
		option.add_item(text)
	option.selected = int(settings[key])
	option.item_selected.connect(func(index: int): set_setting(key, index))
	row.add_child(option)
	content.add_child(row)

func _toggle(title: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = bool(settings[key])
	check.toggled.connect(func(value: bool): set_setting(key, value))
	content.add_child(check)

func _number_option(title: String, key: String, minimum: float, maximum: float, increment: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = increment
	if key == "stand_gap_seconds":
		number.step = 0.01
		number.custom_arrow_step = increment
	number.value = float(settings[key])
	if key == "max_outings":
		number.tooltip_text = "Allow at least 2 for coworkers to take a conversation break together. They still stand up one at a time."
	number.custom_minimum_size.x = 110
	number.value_changed.connect(func(value: float): set_setting(key, int(value) if key == "max_outings" else value))
	row.add_child(number)
	content.add_child(row)

func _binding_row(action_id: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = OfficeInput.label_for(action_id)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := Button.new()
	button.text = OfficeInput.key_name(action_id)
	button.custom_minimum_size = Vector2(150, 36)
	button.pressed.connect(func():
		if _binding_buttons.has(_capturing_action):
			_binding_buttons[_capturing_action].text = OfficeInput.key_name(_capturing_action)
		_capturing_action = action_id
		button.text = "Press a key…"
		button.grab_focus()
	)
	row.add_child(button)
	content.add_child(row)
	_binding_buttons[action_id] = button

func _capture_binding(keycode: int) -> void:
	var action_id := _capturing_action
	_capturing_action = ""
	if OfficeInput.is_reserved(keycode):
		if _binding_buttons.has(action_id):
			_binding_buttons[action_id].text = OfficeInput.key_name(action_id)
		if keycode != KEY_ESCAPE and is_instance_valid(save_status):
			save_status.text = "That key is reserved for a fixed control. Choose another key."
		return
	var updated: Dictionary = OfficeInput.sanitized(settings.get("bindings", {}))
	# Swap with whichever action currently owns the key, so keys stay unique.
	for other in OfficeInput.action_ids():
		if other != action_id and int(updated.get(other, OfficeInput.default_key(other))) == keycode:
			updated[other] = int(updated.get(action_id, OfficeInput.default_key(action_id)))
	updated[action_id] = keycode
	set_setting("bindings", updated)
	if menu_state == &"settings":
		var previous := settings_return_state
		menu_state = previous
		show_settings()

func close_settings() -> void:
	if settings_return_state == &"title":
		return_to_title()
	else:
		_show_pause_menu()

func restore_defaults() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	_apply_settings()
	_save_settings()
	var previous := settings_return_state
	menu_state = previous
	show_settings()

func set_setting(key: String, value: Variant) -> void:
	if not DEFAULT_SETTINGS.has(key):
		return
	if key != "camera_zoom":
		settings["camera_zoom"] = office.iso_camera.target_zoom
	settings[key] = value
	_validate_settings()
	_apply_settings()
	if key == "bindings":
		for action_id in _binding_buttons:
			if is_instance_valid(_binding_buttons[action_id]):
				_binding_buttons[action_id].text = OfficeInput.key_name(action_id)
	_save_settings()

func _validate_settings() -> void:
	settings["lighting"] = clampi(int(settings["lighting"]), 0, 2)
	settings["theme"] = clampi(int(settings.get("theme", 0)), 0, OfficeTheme.THEMES.size() - 1)
	settings["floor_pattern"] = clampi(int(settings["floor_pattern"]), 0, OfficeFloor.PATTERNS.size() - 1)
	settings["floor_texture"] = clampi(int(settings["floor_texture"]), 0, OfficeFloor.TEXTURES.size() - 1)
	if not Color.html_is_valid(String(settings["floor_color"])):
		settings["floor_color"] = ""
	settings["simulation_speed"] = clampi(int(settings["simulation_speed"]), 0, 2)
	settings["camera_zoom"] = clampf(float(settings["camera_zoom"]), IsometricCamera.MIN_ZOOM, IsometricCamera.MAX_ZOOM)
	settings["max_outings"] = clampi(int(settings["max_outings"]), 1, 4)
	settings["stand_gap_seconds"] = clampf(float(settings["stand_gap_seconds"]), 0.5, 3.0)
	settings["ui_scale"] = clampf(float(settings.get("ui_scale", 1.0)), 0.8, 1.5)
	var raw_bindings: Variant = settings.get("bindings", {})
	settings["bindings"] = OfficeInput.sanitized(raw_bindings if raw_bindings is Dictionary else {})
	for key in ["show_labels", "interaction_hints", "shadows", "sound", "high_contrast"]:
		settings[key] = bool(settings[key])

func _apply_settings() -> void:
	office._apply_theme(int(settings.get("theme", 0)))
	office._apply_floor_style(String(settings["floor_color"]), int(settings["floor_pattern"]), int(settings["floor_texture"]))
	office._apply_lighting_preset(int(settings["lighting"]))
	office.show_worker_labels = bool(settings["show_labels"])
	for worker in office.workers_container.get_children():
		worker.status_label.visible = office.editor_visible and office.show_worker_labels
	office.sun_light.shadow_enabled = bool(settings["shadows"])
	office.iso_camera.target_zoom = float(settings["camera_zoom"])
	office.sim_speed_idx = int(settings["simulation_speed"])
	Engine.time_scale = office.SIM_SPEEDS[office.sim_speed_idx]
	var routines := office.get_node_or_null("OfficeRoutines")
	if routines != null:
		routines.max_outings = int(settings["max_outings"])
		routines.stand_gap_seconds = float(settings["stand_gap_seconds"])
	OfficeInput.apply_bindings(settings["bindings"])
	get_tree().root.content_scale_factor = float(settings["ui_scale"])
	if office.player.has_method("set_interaction_hints_enabled"):
		office.player.set_interaction_hints_enabled(bool(settings["interaction_hints"]))
	if office.player.has_method("set_high_contrast_enabled"):
		office.player.set_high_contrast_enabled(bool(settings["high_contrast"]))
	if is_instance_valid(office.audio):
		office.audio.enabled = bool(settings["sound"])

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		for key in DEFAULT_SETTINGS:
			var stored: Variant = config.get_value("preferences", key, DEFAULT_SETTINGS[key])
			if typeof(stored) == typeof(DEFAULT_SETTINGS[key]) or (key == "camera_zoom" and stored is int):
				settings[key] = stored
	_validate_settings()
	_apply_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings:
		config.set_value("preferences", key, settings[key])
	if config.save(SETTINGS_PATH) != OK and is_instance_valid(save_status):
		save_status.text = "Settings applied. Could not save them on this device."

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _capturing_action != "":
		get_viewport().set_input_as_handled()
		_capture_binding(event.keycode if event.keycode != KEY_NONE else event.physical_keycode)
		return
	if menu_state == &"playing" and event.keycode == KEY_F5:
		office.save_shift()
		get_viewport().set_input_as_handled()
		return
	if menu_state == &"playing" and event.keycode == KEY_F9:
		office.load_shift()
		get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_ESCAPE and event.keycode != KEY_P:
		return
	get_viewport().set_input_as_handled()
	if menu_state == &"playing" and event.keycode == KEY_ESCAPE:
		if office.player.dialogue.is_open:
			office.player.dialogue.close()
			return
		if office.edit_mode != office.EditMode.SELECT:
			office.cancel_current_action()
			return
		if office.player.prop_handling.charging:
			office.player.prop_handling.cancel_charge()
			return
		if is_instance_valid(office.player.grabbed_furniture):
			office.player.release_furniture()
			return
		if office.player.equipment.is_active():
			office.player.equipment.cancel()
			return
	match menu_state:
		&"playing":
			pause_game()
		&"paused":
			start_game()
		&"settings":
			close_settings()
		&"credits":
			return_to_title()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and is_instance_valid(office) and menu_state == &"playing":
		pause_game()

func _exit_tree() -> void:
	if is_instance_valid(office):
		get_tree().paused = false
	Engine.time_scale = 1.0
