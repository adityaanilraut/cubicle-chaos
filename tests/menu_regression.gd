extends SceneTree

# Run with: Godot --headless --path . --script res://tests/menu_regression.gd
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

func frames(count := 4) -> void:
	for index in range(count):
		await process_frame

func press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func _run() -> void:
	# Restore the exact pre-existing settings file, including unknown settings.
	var had_settings := FileAccess.file_exists(SETTINGS_PATH)
	var saved_settings := FileAccess.get_file_as_bytes(SETTINGS_PATH) if had_settings else PackedByteArray()
	office = load("res://scenes/main.tscn").instantiate()
	root.add_child(office)
	await create_timer(0.8, true).timeout
	var menu = office.game_menu
	menu.set_setting("simulation_speed", 0)
	var routines := office.get_node("OfficeRoutines")
	menu.set_setting("max_outings", 3)
	menu.set_setting("stand_gap_seconds", 0.75)
	check(routines.max_outings == 3 and is_equal_approx(routines.stand_gap_seconds, 0.75), "Settings separately control concurrent breaks and stand-up spacing")
	menu.set_setting("max_outings", 99)
	menu.set_setting("stand_gap_seconds", 0.0)
	check(routines.max_outings == 4 and is_equal_approx(routines.stand_gap_seconds, 0.5), "Routine settings clamp to supported limits")
	menu.set_setting("max_outings", 2)
	menu.set_setting("stand_gap_seconds", 1.25)
	check(menu.menu_state == &"title" and paused, "Startup opens the title menu with simulation paused")
	check(is_instance_valid(office.player), "Title screen has a fully initialized office behind it")
	var worker: OfficeWorker = office.workers_container.get_child(0)
	var position_before := worker.global_position
	var timer_before := worker.state_timer
	await frames(12)
	check(worker.global_position.is_equal_approx(position_before) and worker.state_timer == timer_before, "NPC movement and routine timers stay frozen behind the title")
	menu.start_game()
	check(menu.menu_state == &"playing" and not paused, "Start enters the game and resumes the simulation")
	await create_timer(0.15, true).timeout
	check(worker.state_timer != timer_before or worker.state != OfficeWorker.State.IDLE, "NPC routines run after starting")
	await press_key(KEY_ESCAPE)
	check(menu.menu_state == &"paused" and paused, "Escape input opens pause and stops the game")
	position_before = worker.global_position
	timer_before = worker.state_timer
	var player_before: Vector3 = office.player.global_position
	await frames(12)
	check(worker.global_position.is_equal_approx(position_before) and worker.state_timer == timer_before and office.player.global_position.is_equal_approx(player_before), "Paused player and NPC simulation stay frozen")
	await press_key(KEY_P)
	check(menu.menu_state == &"playing" and not paused, "P input resumes the paused game")
	await press_key(KEY_P)
	check(menu.menu_state == &"paused" and paused, "P input pauses a running game")
	menu.show_settings()
	check(menu.menu_state == &"settings" and paused, "Settings keep the simulation paused")
	menu.set_setting("show_labels", false)
	check(not office.show_worker_labels and not worker.status_label.visible, "Worker label setting applies to the office")
	menu.set_setting("show_labels", true)
	menu.set_setting("lighting", 2)
	check(office.light_preset_idx == 2, "Lighting setting applies to scene lighting")
	menu.set_setting("camera_zoom", 18.0)
	check(is_equal_approx(office.iso_camera.target_zoom, 18.0), "Camera zoom setting applies")
	menu.set_setting("shadows", false)
	check(not office.sun_light.shadow_enabled, "Shadow setting applies")
	menu.set_setting("interaction_hints", false)
	check(FileAccess.file_exists(SETTINGS_PATH), "Settings are persisted to disk")
	var persisted := ConfigFile.new()
	check(persisted.load(SETTINGS_PATH) == OK and persisted.get_value("preferences", "lighting") == 2 and persisted.get_value("preferences", "interaction_hints") == false and persisted.get_value("preferences", "camera_zoom") == 18.0, "Saved settings preserve the applied preferences")
	menu.set_setting("camera_zoom", 1000.0)
	check(is_equal_approx(office.iso_camera.target_zoom, IsometricCamera.MAX_ZOOM), "Settings clamp camera distance to a usable range")
	office.iso_camera.target_zoom = 16.0
	menu.set_setting("show_labels", true)
	check(is_equal_approx(office.iso_camera.target_zoom, 16.0), "Changing another preference preserves the current camera distance")
	await press_key(KEY_ESCAPE)
	check(menu.menu_state == &"paused" and paused, "Escape closes settings and returns to the pause menu")
	await press_key(KEY_ESCAPE)
	check(menu.menu_state == &"playing" and not paused, "Escape resumes the existing office")
	office.start_placing_catalog_item("chair_desk")
	await press_key(KEY_ESCAPE)
	check(office.edit_mode == office.EditMode.SELECT and menu.menu_state == &"playing" and not paused, "Escape cancels furniture placement before opening pause")
	await press_key(KEY_ESCAPE)
	check(menu.menu_state == &"paused" and paused, "A subsequent Escape pauses after editor cancellation")
	await press_key(KEY_P)
	check(menu.menu_state == &"playing" and not paused, "P resumes after cancelling an editor operation")
	menu.return_to_title()
	check(menu.menu_state == &"title" and paused, "Return to title pauses the existing office")
	menu.show_settings()
	await press_key(KEY_ESCAPE)
	check(menu.menu_state == &"title" and paused, "Escape returns title settings to title without starting the game")
	paused = false
	office.queue_free()
	await frames(2)
	if had_settings:
		var restored := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		restored.store_buffer(saved_settings)
		restored.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	Engine.time_scale = 1.0
	print("MENU CHECKS: ", checks - failures.size(), "/", checks, " passed")
	quit(0 if failures.is_empty() else 1)
