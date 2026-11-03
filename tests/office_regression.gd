extends SceneTree

# Run with: Godot --headless --path . --script res://tests/office_regression.gd
var failures: Array[String] = []
var checks := 0
var office: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func settle(frames: int = 3) -> void:
	for i in range(frames):
		await physics_frame
		await process_frame

func check_desk_ownership() -> void:
	# Off-map fixtures avoid disturbing the live office's reservations and paths.
	var desks: Array[FurnitureItem] = []
	var chairs: Array[FurnitureItem] = []
	var people: Array[OfficeWorker] = []
	for index in range(2):
		var desk: FurnitureItem = office.place_furniture_item("desk_plain", Vector3(30 + index * 4, 0, 30), 0, false)
		var chair: FurnitureItem = office.place_furniture_item("chair_desk", desk.global_position + Vector3(0, 0, 1), 0, false)
		var person := OfficeWorker.new()
		person.set_physics_process(false)
		office.workers_container.add_child(person)
		person.assigned_chair = chair
		person.assigned_desk = desk
		chair.owner_worker = person
		desk.owner_worker = person
		desks.append(desk)
		chairs.append(chair)
		people.append(person)
	office._reconcile_desk_assignments()
	check(desks[0].owner_worker == people[0] and desks[1].owner_worker == people[1], "Each existing chair keeps its own desk claim")
	chairs[0].global_position = desks[1].global_position + Vector3(0, 0, 0.7)
	office._reconcile_desk_assignments()
	check(desks[1].owner_worker == people[1] and people[1].assigned_desk == desks[1], "Moving an owned chair cannot steal another worker's desk")
	check(people[0].assigned_desk != desks[1], "Displaced worker does not share an occupied desk")
	chairs[0].global_position = desks[0].global_position + Vector3(0, 0, 1)
	office._reconcile_desk_assignments()
	check(people[0].assigned_desk == desks[0] and chairs[0].desk_number == desks[0].desk_number, "Restored pairing updates the worker's desk and chair badge")
	desks[0].set_preview_mode(true)
	check(office._find_nearby_desk(desks[0].global_position, people[0]) == null, "Preview desks cannot be assigned")
	desks[0].set_preview_mode(false)
	desks[0].queue_free()
	check(office._find_nearby_desk(chairs[0].global_position, people[0]) == null, "Deleted desks cannot be reassigned before the frame ends")
	for item in desks + chairs + people:
		item.queue_free()
	await settle()
	office._reconcile_desk_assignments()

func check_occupied_editor_guards() -> void:
	var worker: OfficeWorker = office.workers_container.get_child(0)
	worker.is_seated = true
	var occupied_chair: FurnitureItem = worker.assigned_chair
	var original := occupied_chair.global_transform
	office.select_furniture(occupied_chair)
	office.start_moving_selected()
	check(office.edit_mode == office.EditMode.SELECT and not occupied_chair.is_preview and occupied_chair.global_transform.is_equal_approx(original), "Editor cannot move a seated coworker's chair")
	office.rotate_active_or_selected()
	check(occupied_chair.global_transform.is_equal_approx(original), "Editor cannot rotate a seated coworker's chair")
	office.delete_selected_furniture()
	check(not occupied_chair.is_queued_for_deletion() and office.selected_furniture == occupied_chair, "Editor cannot delete a seated coworker's chair")
	var occupied_desk: FurnitureItem = worker.assigned_desk
	var desk_original := occupied_desk.global_transform
	office.select_furniture(occupied_desk)
	office.start_moving_selected()
	office.rotate_active_or_selected()
	office.delete_selected_furniture()
	check(office.edit_mode == office.EditMode.SELECT and not occupied_desk.is_preview and not occupied_desk.is_queued_for_deletion() and occupied_desk.global_transform.is_equal_approx(desk_original), "Occupied workstation desks also reject all editor changes")
	worker.is_seated = false
	var player_seat: FurnitureItem = office.place_furniture_item("chair_desk", Vector3(30, 0, 30), 0, false)
	var player_original := player_seat.global_transform
	office.player.seated = true
	office.player.sitting_chair = player_seat
	office.select_furniture(player_seat)
	office.start_moving_selected()
	check(office.edit_mode == office.EditMode.SELECT and not player_seat.is_preview and player_seat.global_transform.is_equal_approx(player_original), "Editor cannot move the player's occupied chair")
	office.rotate_active_or_selected()
	check(player_seat.global_transform.is_equal_approx(player_original), "Editor cannot rotate the player's occupied chair")
	office.delete_selected_furniture()
	check(not player_seat.is_queued_for_deletion() and office.player.seated and office.player.sitting_chair == player_seat, "Editor cannot delete or orphan the player's occupied chair")
	check(not office.placement_issue.is_empty(), "Blocked occupied-seat edits explain why the object cannot be changed")
	office.player.seated = false
	office.player.sitting_chair = null
	office.cancel_current_action()
	player_seat.queue_free()
	await settle()

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.6).timeout
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)
		worker.nav_agent.velocity = Vector3.ZERO
		worker.nav_agent.avoidance_enabled = false
	await settle()
	await check_desk_ownership()
	await check_occupied_editor_guards()

	var fixture: FurnitureItem = office.place_furniture_item("desk_plain", Vector3(1.8, 0, 4.0), 0.0, false)
	var probe := FurnitureItem.new()
	probe.setup("chair_desk")
	probe.set_preview_mode(true)
	office.add_child(probe)
	await settle()
	check(office.get_placement_issue(probe, Vector3(3.0, 0, 3.8), 0.0).is_empty(), "Empty floor accepts furniture")
	check(not office.get_placement_issue(probe, Vector3(office.FLOOR_BOUNDS.end.x, 0, 4.0), 0.0).is_empty(), "Whole footprint must stay within floor")
	check(office.get_placement_issue(probe, Vector3(1.8, 0, 4.0), 0.0).begins_with("Blocked by"), "Furniture overlap is rejected")
	check(office.get_placement_issue(probe, Vector3(-9, 0, -2), 0.0) == "Leave the doorway clear.", "Room doorway remains open")
	check(office.get_placement_issue(probe, Vector3(-5, 0, -8), 0.0) == "Blocked by a wall.", "Architecture collisions are rejected")
	check(not office.get_placement_issue(fixture, Vector3(office.FLOOR_BOUNDS.end.x - 0.4, 0, 4), PI * 0.25).is_empty(), "Rotated footprint respects boundaries")
	var rug: FurnitureItem = office.place_furniture_item("rug", fixture.global_position, 0.0, false)
	check(office.get_placement_issue(fixture, fixture.global_position, 0.0).is_empty(), "Rugs can sit beneath furniture")
	player.global_position = Vector3(3.0, 0, 3.8)
	check(office.get_placement_issue(probe, player.global_position, 0.0) == "Give people room to move.", "Placement cannot overlap the player")
	probe.queue_free()
	rug.queue_free()
	await settle()
	var rotation_blocker: FurnitureItem = office.place_furniture_item("chair_desk", fixture.global_position + Vector3(0, 0, 1.0), 0.0, false)
	office.select_furniture(fixture)
	office.rotate_active_or_selected()
	check(is_zero_approx(fixture.global_rotation.y), "Editor rejects rotation into a neighbouring object")
	check(not office.placement_issue.is_empty(), "Rejected rotation explains the obstruction")
	rotation_blocker.queue_free()
	await settle()
	fixture.room_tag = "regression_station"
	var reserving_worker: OfficeWorker = office.workers_container.get_child(0)
	reserving_worker.target_furniture = fixture
	reserving_worker._enter_walking(fixture.get_interact_world_pos())
	check(office.find_tagged_spot("regression_station", office.workers_container.get_child(1)) == null, "Coworkers avoid an already reserved interaction spot")
	reserving_worker._enter_idle(100.0)
	check(office.find_tagged_spot("regression_station", office.workers_container.get_child(1)) == fixture, "Cancelled routes release interaction spots")
	fixture.room_tag = ""

	# Moving an existing item can always be cancelled back to its exact transform.
	var original := fixture.global_transform
	office.select_furniture(fixture)
	office.start_moving_selected()
	office.cancel_current_action()
	check(fixture.global_transform.is_equal_approx(original), "Cancel restores original furniture transform")
	check(not fixture.is_preview and not fixture.collision_shape.disabled and fixture.is_in_group("nav_bake"), "Cancel restores collision and navigation geometry")
	await settle()

	# Grab by the surface, then exercise forward and backward movement.
	player.global_position = fixture.global_position + Vector3(0, 0, fixture.footprint_size.z * 0.5 + 0.42)
	await settle()
	check(player.try_grab_furniture(), "Player can grab reachable furniture")
	check(fixture.being_moved_by == player and player.grip_modifier.active, "Grab enables hand contact and reserves object")
	var start := fixture.global_position
	var offset := player.global_position - fixture.global_position
	for i in range(20):
		player._process_furniture_move(player.grab_axis, 1.0 / 60.0)
		await settle(1)
	check(fixture.global_position.distance_to(start) > 0.15, "Pushing translates furniture")
	check((player.global_position - fixture.global_position).is_equal_approx(offset), "Player and furniture move together")
	check(player.furniture_motion == "push", "Pushing selects the push animation")
	for i in range(20):
		player._process_furniture_move(-player.grab_axis, 1.0 / 60.0)
		await settle(1)
	check(fixture.global_position.distance_to(start) < 0.02, "Pulling reverses furniture movement")
	check(player.furniture_motion == "pull", "Pulling selects backward steps")
	player.release_furniture()
	check(fixture.being_moved_by == null and not player.grip_modifier.active, "Release restores furniture and character")
	check(not player.get_collision_exceptions().has(fixture), "Release removes temporary collision exception")
	check(office._nav_rebake_pending or office.nav_region.is_baking(), "Releasing furniture requests navigation refresh")

	# An obstacle must stop a large movement request without tunnelling.
	var blocker: FurnitureItem = office.place_furniture_item("desk_plain", fixture.global_position + Vector3(0, 0, -1.4), 0, false)
	await settle()
	check(player.try_grab_furniture(), "Furniture can be grabbed again")
	player._process_furniture_move(player.grab_axis, 3.0)
	check(office.get_placement_issue(fixture, fixture.global_position, fixture.global_rotation.y, player).is_empty(), "Push stops at obstacle without overlap")
	check(fixture.global_position.z > blocker.global_position.z + 0.5, "Large movement cannot tunnel through furniture")
	player.release_furniture()
	blocker.queue_free()

	# A cup occupies the player's hands and prevents furniture grabs.
	var cup := Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	check(not player.try_grab_furniture(), "Furniture requires both hands free")
	player.carried_cup = null
	cup.queue_free()
	fixture.queue_free()
	await settle()

	var library := AssetCatalog.get_worker_animation_library()
	for motion in ["grip", "push", "pull"]:
		check(library.has_animation(motion), "Animation exists: " + motion)

	# Exercise live pathfinding and detect sudden position jumps over a full routine.
	player.global_position = Vector3(3.0, 0, 8.0)
	var previous := {}
	var visited_work := {}
	for worker in office.workers_container.get_children():
		worker.nav_agent.avoidance_enabled = true
		worker.set_physics_process(true)
		worker._enter_idle(0.1)
		previous[worker] = worker.global_position
	office._request_navmesh_rebake()
	Engine.time_scale = 3.0
	var jumps := 0
	var total_travel := 0.0
	for frame in range(1000):
		await physics_frame
		for worker in office.workers_container.get_children():
			var distance: float = worker.global_position.distance_to(previous[worker])
			if distance > 0.65:
				jumps += 1
			total_travel += distance
			previous[worker] = worker.global_position
			if worker.state == OfficeWorker.State.WORKING:
				visited_work[worker] = true
	check(jumps == 0, "Workers never teleport during normal work/break routines")
	check(total_travel > 20.0, "Workers make progress across the office")
	check(visited_work.size() >= 4, "Workers reach their desks and work")

	# Trap a destination in solid furniture; finishing a partial path is not arrival.
	var worker: OfficeWorker = office.workers_container.get_child(0)
	worker._force_stand_and_idle()
	worker.is_seated = false
	worker.global_position = Vector3(1.8, 0, 4.0)
	var trap: FurnitureItem = office.place_furniture_item("desk_plain", Vector3(3.5, 0, 4.0), 0.0, true)
	await create_timer(0.5).timeout
	worker.walk_goal = OfficeWorker.WalkGoal.TO_STROLL
	worker._enter_walking(trap.global_position)
	var trap_start := worker.global_position
	await create_timer(0.3).timeout
	check(worker.global_position.distance_to(trap.global_position) > 0.6, "Unreachable destination does not teleport worker into obstacle")
	check(worker.global_position.distance_to(trap_start) < 0.6, "Unreachable path recovery stays local")
	Engine.time_scale = 1.0
	print("OFFICE CHECKS: ", checks - failures.size(), "/", checks, " passed; workers reached work: ", visited_work.size())
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
