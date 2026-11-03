extends SceneTree

var office: Node3D
var player: OfficePlayer
var worker: OfficeWorker
var cup: Node3D
var checks := 0
var failures: Array[String] = []

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

func tap(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func has_action(id: String) -> bool:
	for action in player.get_context_actions():
		if action.id == id: return true
	return false

func hold_cup() -> void:
	player.busy = 0.0
	player.carried_cup = cup
	player.cup_in_hand = true
	player._resting_cup = null
	player._cup_support = null
	cup.remove_from_group("player_interactable")
	cup.global_position = player.global_position + Vector3.UP * 1.1

func snapshot(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	player.busy = 0.0
	player._update_nearby()
	office.iso_camera.target_zoom = 6.5
	office.iso_camera.focus_on(player.global_position)
	office.iso_camera.target_pos.y = 0.6
	await frames(15)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/office-seated-cup-" + name + ".png")

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	Engine.time_scale = 1.0
	player = office.player
	player.set_physics_process(false)
	player.nav_agent.avoidance_enabled = false
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person.nav_agent.avoidance_enabled = false
		person._enter_idle(100.0)
		person.global_position = Vector3(-11, 0, 8)
	worker = office.workers_container.get_child(1)
	var desk: FurnitureItem = office.place_furniture_item("desk_pc", Vector3(0.5, 0, 4.0), 0, false)
	var chair: FurnitureItem = office.place_furniture_item("chair_desk", desk.global_position + Vector3(0, 0, desk.footprint_size.z * 0.5 + 0.38), PI, false)
	worker.assigned_desk = desk
	worker.assigned_chair = chair
	worker.target_chair = chair
	desk.owner_worker = worker
	chair.owner_worker = worker
	chair.paired_desk = desk
	worker.global_position = chair.get_seat_world_pos()
	worker.rotation.y = PI
	worker._enter_working()
	player.global_position = desk.global_position - Vector3(0, 0, desk.footprint_size.z * 0.5 + 0.45)
	player.rotation.y = 0
	await frames()
	player._update_nearby()
	check(player._can_reach_interaction(worker), "Seated coworker is reachable across a real occupied desk")
	check(player.nearby == worker and has_action("interact"), "Occupied desk and chair leave the Talk action visible")
	await tap(KEY_F)
	check(player.dialogue.is_open and player.dialogue.speaker == worker, "F opens dialogue with the seated coworker")
	var work_time := worker.state_timer
	worker._physics_process(0.5)
	check(worker.is_seated and worker.state == OfficeWorker.State.WORKING and worker.state_timer == work_time, "Talking preserves sitting position and work progress")
	await snapshot("conversation")
	player.dialogue.close()
	player.busy = 0.0
	player._update_nearby()
	player.perform_context_action("interact", worker)
	check(player.dialogue.is_open, "Circular Talk action also reaches the seated coworker")
	player.dialogue.close()
	player.busy = 0.0

	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2.6, 0.12)
	collision.shape = box
	wall.add_child(collision)
	office.add_child(wall)
	wall.global_position = desk.global_position + Vector3(0, 1.3, 0)
	await frames()
	check(not player._can_reach_interaction(worker), "A real wall still blocks seated conversations")
	wall.queue_free()
	await frames()
	worker.global_position = Vector3(-11, 0, 8)
	worker.is_seated = false
	worker._enter_idle(100.0)
	desk.owner_worker = null
	chair.owner_worker = null
	chair.queue_free()
	desk.queue_free()
	await frames()

	cup = office.get_node("WaterCup")
	var table: FurnitureItem = office.place_furniture_item("coffee_table", Vector3(0.5, 0, 4), PI * 0.25, false)
	player.global_position = table.to_global(Vector3(0, 0, table.footprint_size.z * 0.5 + 0.4))
	player.rotation.y = table.rotation.y + PI
	hold_cup()
	await frames()
	player._update_nearby()
	var placement := player._find_cup_placement(table)
	check(not placement.is_empty() and placement.position.y > 0.2, "Rotated coffee table offers a reachable tabletop point")
	check(player.nearby == table and has_action("interact") and player.prompt.text.contains("Place cup"), "Holding a cup offers an explicit Place cup action")
	await tap(KEY_G)
	await create_timer(0.7).timeout
	check(player.carried_cup == null and cup.is_in_group("player_interactable"), "G places and releases the cup for pickup")
	check(absf(cup.global_position.y - placement.position.y) < 0.01, "Cup bottom rests on the tabletop instead of the floor")
	check(player.cup_filled == false, "Placement preserves the cup's water state")
	await snapshot("table")
	var local_spot := table.to_local(cup.global_position)
	table.global_position += Vector3(0.15, 0, 0)
	table.rotation.y += 0.35
	await frames()
	check(cup.global_position.distance_to(table.to_global(local_spot)) < 0.01, "Cup follows the supporting table's movement and rotation")
	player.busy = 0.0
	player._update_nearby()
	check(player.nearby == cup and has_action("interact"), "Tabletop cup wins focus over its supporting table")
	await tap(KEY_F)
	await create_timer(0.8).timeout
	check(player.carried_cup == cup and player.cup_in_hand, "F picks the cup back up from the table")
	player.busy = 0.0
	player.cup_filled = true
	player._update_nearby()
	player.perform_context_action("interact", table)
	await create_timer(0.7).timeout
	check(player.carried_cup == null and cup.global_position.y > 0.2 and player.cup_filled, "F places a filled cup without losing its contents")
	table.queue_free()
	await frames()
	check(is_instance_valid(cup) and cup.is_in_group("player_interactable") and is_zero_approx(cup.global_position.y), "Deleting the supporting table leaves the cup collectible on the floor")

	# Composite workstations must use the desk top and avoid their decorations.
	for id in ["desk_pc", "laptop_desk", "exec_desk", "conference_table", "round_table", "side_table", "kitchen_counter", "kitchen_bar"]:
		var item: FurnitureItem = office.place_furniture_item(id, Vector3(0.5, 0, 4), 0, false)
		player.global_position = item.global_position + Vector3(0, 0, item.footprint_size.z * 0.5 + 0.35)
		await frames()
		var spot := player._find_cup_placement(item)
		if id == "side_table":
			check(spot.is_empty(), "Cluttered side table refuses to overlap its radio and lamp")
		else:
			check(not spot.is_empty(), id + ": offers a free support surface beside decorations")
		item.queue_free()
		await frames()

	# Removing or moving the destination during the reach keeps the cup in hand.
	table = office.place_furniture_item("coffee_table", Vector3(0.5, 0, 4), 0, false)
	player.global_position = table.global_position + Vector3(0, 0, table.footprint_size.z * 0.5 + 0.4)
	hold_cup()
	await frames()
	player._drop_cup()
	table.global_position += Vector3(5, 0, 0)
	await create_timer(0.3).timeout
	check(player.carried_cup == cup and player.cup_in_hand, "Moving a table out of reach during placement safely keeps the cup in hand")
	table.queue_free()
	await frames()
	player.global_position = Vector3(0.5, 0, 4)
	player.busy = 0
	player._drop_cup()
	await create_timer(1.6).timeout
	check(player.carried_cup == null and cup.is_in_group("player_interactable") and is_zero_approx(cup.global_position.y), "G still puts the cup on the floor when no table is nearby")

	# A wall must prevent placement even when a table is within arm's reach.
	table = office.place_furniture_item("coffee_table", Vector3(0.5, 0, 4), 0, false)
	player.global_position = table.global_position + Vector3(0, 0, table.footprint_size.z * 0.5 + 0.4)
	hold_cup()
	wall = StaticBody3D.new()
	collision = CollisionShape3D.new()
	box = BoxShape3D.new()
	box.size = Vector3(3, 2.6, 0.10)
	collision.shape = box
	wall.add_child(collision)
	office.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 1.3, -0.20)
	await frames()
	check(player._find_cup_placement(table).is_empty(), "A wall blocks placing a cup through it onto a nearby table")
	wall.queue_free()
	await frames()
	player._drop_cup()
	await create_timer(0.3).timeout
	office.game_menu.pause_game()
	var paused_position := cup.global_position
	await create_timer(0.3).timeout
	check(cup.global_position.is_equal_approx(paused_position), "Pausing freezes an in-progress cup placement")
	office.game_menu.start_game()
	await create_timer(0.45).timeout
	check(cup.is_in_group("player_interactable") and cup.global_position.y > 0.2, "Resuming completes tabletop placement normally")

	hold_cup()
	player._drop_cup()
	await create_timer(0.3).timeout
	table.queue_free()
	await create_timer(0.5).timeout
	check(is_instance_valid(cup) and cup.is_in_group("player_interactable") and is_zero_approx(cup.global_position.y), "Deleting a table during the release leaves the cup collectible on the floor")

	print("SEATED / CUP CHECKS: ", checks - failures.size(), "/", checks, " passed")
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
