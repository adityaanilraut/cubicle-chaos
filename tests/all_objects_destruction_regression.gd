extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
const ARENA := Vector3(32, 0, 32)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func settle(count := 4) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func make_item(id: String, offset := Vector3.ZERO) -> FurnitureItem:
	return office.place_furniture_item(id, ARENA + offset, 0, false)

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for npc in office.workers_container.get_children(): npc.set_physics_process(false)
	var worker: OfficeWorker = office.workers_container.get_child(0)
	# An occupied chair must release immediately, even while someone else owns
	# the shared stand-up lane. It cannot wait on an animation to a freed seat.
	var chair := make_item("chair_desk")
	worker.target_chair = chair
	worker.assigned_chair = chair
	chair.owner_worker = worker
	chair.reserved_by = worker
	worker.global_position = chair.get_seat_world_pos()
	worker._enter_working()
	worker.routines.standing_worker = office.workers_container.get_child(1)
	check(chair.take_damage(1000), "An occupied office chair can break")
	check(not worker.is_seated and worker.target_chair == null and worker.assigned_chair == null and not worker._forced_stand_pending, "Destroyed chair releases its worker without waiting for the stand lane")
	await settle()
	check(not is_instance_valid(chair) and not worker.collision_shape.disabled, "Destroyed chair disappears and worker collision is restored")
	worker.routines.standing_worker = null
	# Destroying a desk should invalidate its owner even though that assignment
	# is cleared during notification, and the chair itself is still valid.
	chair = make_item("chair_desk", Vector3(4, 0, 0))
	var desk := make_item("desk_pc", Vector3(4, 0, 1.1))
	worker.assigned_chair = chair
	worker.assigned_desk = desk
	worker.target_chair = chair
	chair.owner_worker = worker
	chair.reserved_by = worker
	desk.owner_worker = worker
	worker.global_position = chair.get_seat_world_pos()
	worker._enter_working()
	check(desk.take_damage(1000) and worker.assigned_desk == null, "Occupied workstation breaks and clears its desk ownership")
	check(worker.state != OfficeWorker.State.WORKING or worker._forced_stand_pending, "Desk loss interrupts the worker's work routine")
	chair.take_damage(1000)
	await settle()
	# Player seats can break while seated or midway through standing.
	for standing in [false, true]:
		chair = make_item("chair_desk", Vector3(8, 0, 0))
		player.global_position = chair.get_seat_world_pos()
		player.seated = true
		player.standing_up = standing
		player.busy = 1.0
		player.sitting_chair = chair
		player.collision_shape.disabled = true
		chair.reserved_by = player
		check(chair.take_damage(1000), "Player's occupied chair can break")
		await settle()
		check(not player.seated and not player.standing_up and player.sitting_chair == null and player.busy == 0 and not player.collision_shape.disabled, "Player recovers safely from a destroyed seat")
	chair = make_item("lounge_sofa", Vector3(8, 0, 4))
	player.equipment.active_item = chair
	player.equipment.active_action = "eq_relax"
	player.equipment._seated_for_relax = true
	player.sitting_chair = chair
	player.seated = true
	player.global_position = chair.get_seat_world_pos()
	player.collision_shape.disabled = true
	chair.reserved_by = player
	check(chair.take_damage(1000), "Lounge seating can break during a rest activity")
	await settle()
	check(not player.equipment.is_active() and not player.seated and not player.collision_shape.disabled, "Destroyed lounge cancels rest and releases the player")
	# Destruction cancels an active equipment transaction without rewards.
	var printer := make_item("printer_station", Vector3(12, 0, 0))
	player.equipment.active_item = printer
	player.equipment.active_action = "eq_print"
	player.equipment.remaining = 0.01
	printer.reserved_by = player
	var printed: int = player.equipment.stats.pages_printed
	check(printer.take_damage(1000), "In-use equipment can break")
	check(not player.equipment.is_active() and player.equipment.active_item == null and player.equipment.stats.pages_printed == printed, "Destroyed equipment cancels immediately without awarding work")
	await settle()
	var shower := make_item("shower", Vector3(12, 0, 4))
	player.global_position = shower.get_interact_world_pos()
	var entry := player.global_position
	player.equipment.active_item = shower
	player.equipment.active_action = "eq_shower"
	shower.reserved_by = player
	player.equipment.bathroom = BathroomActivity.new()
	player.equipment.bathroom.begin(player, shower, "eq_shower")
	check(shower.take_damage(1000), "Bathroom fixtures can break while in use")
	check(not player.equipment.is_active() and player.equipment.bathroom == null and player.global_position.is_equal_approx(entry), "Destroyed bathroom fixture clears water effects and restores the player's entry position")
	await settle()
	# A table supporting the player's cup must not leave it floating.
	var table := make_item("conference_table", Vector3(16, 0, 0))
	var cup := Node3D.new()
	office.add_child(cup)
	cup.global_position = table.global_position + Vector3.UP
	player._resting_cup = cup
	player._cup_support = table
	check(table.take_damage(1000), "Conference tables can break")
	check(player._cup_support == null and is_zero_approx(cup.global_position.y), "Cup falls to floor when its table breaks")
	cup.free()
	player._resting_cup = null
	await settle()
	# Furniture being pushed is also destructible and releases the grip.
	var box := make_item("storage_boxes", Vector3(20, 0, 0))
	player.grabbed_furniture = box
	box.being_moved_by = player
	player.add_collision_exception_with(box)
	check(box.take_damage(1000), "Furniture can break while being moved")
	check(player.grabbed_furniture == null and not player.grip_modifier.active, "Destroyed furniture releases the player's grip")
	await settle()
	# Real physics contacts can destroy newly breakable workstations and chairs.
	for id in ["desk_pc", "chair_desk"]:
		var target := make_item(id, Vector3(0, 0, 12))
		var projectile: PhysicsProp = office.spawn_prop("speaker", target.global_position + Vector3(0, 0.5, -1.5))
		projectile.gravity_scale = 0
		projectile.linear_velocity = Vector3(0, 0, 12)
		projectile.impact.reset(projectile.linear_velocity)
		await settle(24)
		check(not is_instance_valid(target) or target.is_queued_for_deletion(), "An actual thrown prop destroys " + id)
		if is_instance_valid(projectile): projectile.queue_free()
		await settle()
	# A damaged workstation survives save/load while a destroyed one stays gone.
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	desk = make_item("desk_plain", Vector3(24, 0, 0))
	desk.take_damage(desk.max_health * 0.4)
	var saved_health := desk.health
	var destroyed := make_item("desk_plain", Vector3(27, 0, 0))
	destroyed.take_damage(1000)
	check(OfficeSave.save_game(office) and OfficeSave.load_game(office), "Shift with damaged and destroyed desks saves and loads")
	var found_damaged := false
	var found_destroyed := false
	for item in office.furniture_container.get_children():
		if not item is FurnitureItem: continue
		if item.global_position.is_equal_approx(ARENA + Vector3(24, 0, 0)):
			found_damaged = is_equal_approx(item.health, saved_health) and item.destructible.damage_state == "damaged"
		if item.global_position.is_equal_approx(ARENA + Vector3(27, 0, 0)): found_destroyed = true
	check(found_damaged and not found_destroyed, "Load preserves desk damage and does not respawn destroyed desks")
	if had_save:
		var file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))
	print("ALL OBJECT DESTRUCTION CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	office.queue_free()
	await settle()
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
