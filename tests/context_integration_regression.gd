extends SceneTree

var checks := 0
var failures: Array[String] = []
var office: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func frames(count := 3) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	Engine.time_scale = 1.0
	var player: OfficePlayer = office.player
	var speaker: OfficeWorker = office.workers_container.get_child(2)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker.nav_agent.avoidance_enabled = false
		worker._enter_idle(1000.0)
		worker.global_position = Vector3(-11, 0, 8)
	player.nav_agent.avoidance_enabled = false
	player.global_position = Vector3(2, 0, 4)
	speaker.global_position = player.global_position + Vector3(0, 0, 0.9)
	await frames()
	check(player.dialogue.open(speaker), "A reachable coworker can start a dialogue")
	var before := player.global_position
	var yaw: float = office.iso_camera.target_yaw_deg
	key(KEY_W, true)
	key(KEY_Q, true)
	await frames(8)
	key(KEY_W, false)
	key(KEY_Q, false)
	check(player.global_position.is_equal_approx(before), "Held movement cannot walk away during dialogue")
	check(is_equal_approx(office.iso_camera.target_yaw_deg, yaw), "Held camera keys do not move the view during dialogue")
	await tap(KEY_1)
	check(player.dialogue.current_topic == "greeting" and office.edit_mode == office.EditMode.SELECT, "Number keys leave automatic conversation unchanged and cannot build furniture")
	await tap(KEY_P)
	check(paused and player.dialogue.is_open and not player.dialogue.visible, "Pause hides dialogue while preserving its session")
	await tap(KEY_P)
	check(not paused and player.dialogue.visible and speaker.player_conversation_partner == player, "Resume restores the held conversation")
	await tap(KEY_ESCAPE)
	check(not player.dialogue.is_open and not paused, "First Escape closes dialogue without pausing")
	await tap(KEY_ESCAPE)
	check(paused, "Next Escape opens pause normally")
	await tap(KEY_P)
	speaker.global_position = Vector3(-11, 0, 8)

	var desk: FurnitureItem = office.place_furniture_item("desk_plain", Vector3(2, 0, 4), 0.0, false)
	player.global_position = desk.global_position + desk.get_forward_dir() * (desk.footprint_size.z * 0.5 + 0.45)
	await frames()
	check(player.equipment.perform("eq_report", desk), "Unassigned workstation starts useful work")
	await frames()
	await tap(KEY_P)
	var remaining: float = player.equipment.remaining
	await frames(12)
	check(paused and is_equal_approx(player.equipment.remaining, remaining), "Equipment progress freezes while paused")
	check(desk.reserved_by == player, "Paused activity keeps its equipment reservation")
	office.game_menu.show_settings()
	await frames()
	check(player.equipment.is_active() and is_equal_approx(player.equipment.remaining, remaining), "Settings preserve paused work without completing it")
	office.game_menu.close_settings()
	await tap(KEY_P)
	await frames(5)
	check(player.equipment.remaining < remaining, "Resuming continues equipment progress")
	await tap(KEY_ESCAPE)
	check(not paused and not player.equipment.is_active() and desk.reserved_by == null, "Escape cancels equipment before opening pause")
	check(int(player.equipment.stats.reports_ready) == 0, "Cancelled report awards no work")
	check(player.equipment.perform("eq_report", desk), "Equipment can be used again after cancelling")
	office.start_placing_catalog_item("chair_desk")
	check(not player.equipment.is_active() and desk.reserved_by == null, "Starting a build releases unfinished equipment safely")
	office.cancel_current_action()
	check(player.equipment.perform("eq_report", desk), "Finishing editor cancellation restores equipment access")
	office.game_menu.return_to_title()
	check(paused and not player.equipment.is_active() and desk.reserved_by == null, "Returning to title cancels work and releases reservations")
	office.game_menu.start_game()
	print("CONTEXT INTEGRATION CHECKS: ", checks - failures.size(), "/", checks, " passed")
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
