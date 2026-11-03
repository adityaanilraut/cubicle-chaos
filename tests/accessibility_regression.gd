extends SceneTree

# Accessibility: remappable keys, UI scale, high-contrast highlight,
# scroll zoom, and the module split that keeps office_main/player/worker lean.
var failures: Array[String] = []
var checks := 0
var office: Node3D
const SETTINGS_PATH := "user://office_settings.cfg"

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func frames(count := 3) -> void:
	for index in range(count):
		await process_frame

func wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event

func _run() -> void:
	var had_settings := FileAccess.file_exists(SETTINGS_PATH)
	var saved_settings := FileAccess.get_file_as_bytes(SETTINGS_PATH) if had_settings else PackedByteArray()

	# Split modules exist as their own classes.
	check(OfficeEnvironment != null and OfficeDesks != null and OfficeEditorUi != null, "office_main delegates to environment/desks/editor modules")
	check(PlayerCup != null and WorkerSocial != null, "player/worker delegate cup and social logic to modules")

	# Default bindings match the documented controls.
	OfficeInput.reset_bindings()
	check(OfficeInput.key_for("interact") == KEY_F, "Interact defaults to F")
	check(OfficeInput.key_for("prop") == KEY_T, "Prop defaults to T")
	check(OfficeInput.key_for("fight") == KEY_J, "Fight defaults to J")
	check(OfficeInput.matches(key_event(KEY_F), "interact"), "Default interact key matches")
	check(not OfficeInput.matches(key_event(KEY_U), "interact"), "Unbound key does not match")

	# Remapping takes effect and sanitising rejects reserved/unknown keys.
	OfficeInput.apply_bindings({"interact": KEY_U, "pause": KEY_ESCAPE, "bogus": KEY_Z})
	check(OfficeInput.key_for("interact") == KEY_U, "Remapped interact key applies")
	check(OfficeInput.matches(key_event(KEY_U), "interact"), "Remapped key matches its action")
	check(not OfficeInput.action_ids().has("pause"), "Pause/Esc is not a remappable action")
	OfficeInput.reset_bindings()
	check(OfficeInput.key_for("interact") == KEY_F, "Reset restores default bindings")

	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	var menu = office.game_menu
	var player = office.player

	# Scroll wheel zooms both ways and clamps (wheel already handled by the
	# camera; this pins the behaviour so it cannot regress).
	var camera = office.iso_camera
	camera.target_zoom = 16.0
	camera._unhandled_input(wheel(MOUSE_BUTTON_WHEEL_DOWN))
	check(camera.target_zoom > 16.0, "Scroll down zooms out")
	var zoomed_out: float = camera.target_zoom
	camera._unhandled_input(wheel(MOUSE_BUTTON_WHEEL_UP))
	check(camera.target_zoom < zoomed_out, "Scroll up zooms in")
	camera.target_zoom = IsometricCamera.MIN_ZOOM
	camera._unhandled_input(wheel(MOUSE_BUTTON_WHEEL_UP))
	check(is_equal_approx(camera.target_zoom, IsometricCamera.MIN_ZOOM), "Zoom clamps at the minimum")
	camera.target_zoom = IsometricCamera.MAX_ZOOM
	camera._unhandled_input(wheel(MOUSE_BUTTON_WHEEL_DOWN))
	check(is_equal_approx(camera.target_zoom, IsometricCamera.MAX_ZOOM), "Zoom clamps at the maximum")

	# UI scale applies to the window and clamps.
	menu.set_setting("ui_scale", 1.25)
	check(is_equal_approx(root.content_scale_factor, 1.25), "UI scale applies to the window")
	menu.set_setting("ui_scale", 99.0)
	check(is_equal_approx(float(menu.settings["ui_scale"]), 1.5), "UI scale clamps to the supported maximum")
	menu.set_setting("ui_scale", 1.0)
	check(is_equal_approx(root.content_scale_factor, 1.0), "UI scale restores to 100%")

	# High-contrast highlight recolours and thickens the interaction outline.
	var focus = player.interaction_focus
	check(not focus.high_contrast, "High contrast starts off")
	menu.set_setting("high_contrast", true)
	check(focus.high_contrast, "High-contrast setting reaches the interaction highlight")
	check(focus.highlight_color() != Color.WHITE, "High contrast uses a non-white highlight")
	check(focus.outline_expand() > 0.018, "High contrast thickens the outline")
	menu.set_setting("high_contrast", false)
	check(not focus.high_contrast and focus.highlight_color() == Color.WHITE, "Turning high contrast off restores the white highlight")

	# The Settings capture flow: pick a row, press a key, it rebinds.
	menu.show_settings()
	check(menu._binding_buttons.has("interact"), "Settings lists a remap row for interact")
	menu._capturing_action = "interact"
	menu._input(key_event(KEY_U))
	check(OfficeInput.key_for("interact") == KEY_U, "Pressing a key while capturing rebinds the action")
	menu._capturing_action = "interact"
	menu._input(key_event(KEY_ESCAPE))
	check(OfficeInput.key_for("interact") == KEY_U, "Esc cancels capture without changing the binding")
	menu.set_setting("bindings", {})

	# Remapping through Settings persists and drives matching.
	menu.set_setting("bindings", {"interact": KEY_U})
	check(OfficeInput.key_for("interact") == KEY_U, "Settings remap applies immediately")
	var persisted := ConfigFile.new()
	check(persisted.load(SETTINGS_PATH) == OK and int(persisted.get_value("preferences", "bindings", {}).get("interact", 0)) == KEY_U, "Remapped binding persists to disk")
	# Context circles advertise the remapped key.
	player._update_nearby()
	for action in player.get_context_actions():
		if action.id == "interact":
			check(action.key == OfficeInput.key_name("interact"), "Action circles show the remapped key")
	menu.set_setting("bindings", {})
	OfficeInput.reset_bindings()

	# Restore the pre-existing settings file exactly.
	if had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(saved_settings)
		file.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	root.content_scale_factor = 1.0

	print("ACCESSIBILITY CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
