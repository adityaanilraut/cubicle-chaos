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

func crosses_chair(path: PackedVector3Array, chair: FurnitureItem) -> bool:
	# Sample the actual route against the footprint with a worker's body clearance.
	var half := chair.footprint_size * 0.5 + Vector3(0.24, 0, 0.24)
	for index in range(1, path.size()):
		var start := chair.to_local(path[index - 1])
		var end := chair.to_local(path[index])
		var steps := maxi(1, ceili(start.distance_to(end) / 0.04))
		for step in range(steps + 1):
			var point := start.lerp(end, float(step) / steps)
			if absf(point.x) < half.x and absf(point.z) < half.z:
				return true
	return false

func check_blocking(actor: OfficeWorker, chair: FurnitureItem, description: String) -> void:
	actor.global_position = chair.to_global(Vector3(-2, 0, 0))
	actor.collision_shape.disabled = false
	await frames()
	for index in range(75):
		await physics_frame
		actor.velocity = chair.global_basis.x * 3.0
		actor.move_and_slide()
	var local := chair.to_local(actor.global_position)
	check(local.x < -chair.footprint_size.x * 0.5, description)
	actor.velocity = Vector3.ZERO
	actor.global_position = Vector3(36, 0, 36)

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	player.nav_agent.avoidance_enabled = false
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person._enter_idle(1000.0)
		person.nav_agent.avoidance_enabled = false
		person.global_position = Vector3(-11, 0, 8)
	var occupant: OfficeWorker = office.workers_container.get_child(0)
	var walker: OfficeWorker = office.workers_container.get_child(1)

	# An isolated floor uses the real office's bake settings without aisle clutter.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.2, 12)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.add_to_group("nav_bake")
	office.add_child(floor_body)
	floor_body.global_position = Vector3(30, -0.1, 30)
	var chair: FurnitureItem = office.place_furniture_item("chair_desk", Vector3(30, 0, 30), 0, false)
	for yaw in [0.0, PI * 0.5, PI * 1.25]:
		chair.rotation.y = yaw
		office._request_navmesh_rebake()
		await frames()
		while office.nav_region.is_baking() or office._nav_rebake_pending:
			await frames()
		await frames()
		var nav_map: RID = office.nav_region.get_navigation_map()
		var start := NavigationServer3D.map_get_closest_point(nav_map, chair.to_global(Vector3(-2, 0, 0)))
		var end := NavigationServer3D.map_get_closest_point(nav_map, chair.to_global(Vector3(2, 0, 0)))
		var path := NavigationServer3D.map_get_path(nav_map, start, end, true)
		check(path.size() >= 2 and not crosses_chair(path, chair), "Routes go around a chair at rotation %.2f" % yaw)
		await check_blocking(player, chair, "Player cannot walk through an empty rotated chair")
		occupant.target_chair = chair
		occupant.global_position = chair.get_seat_world_pos()
		occupant._enter_working()
		await check_blocking(player, chair, "Player cannot walk through an occupied rotated chair")
		await check_blocking(walker, chair, "Coworker cannot walk through an occupied rotated chair")

		# Follow the real navigation to the approach point, then sit and stand.
		occupant.is_seated = false
		occupant.global_position = chair.to_global(Vector3(2, 0, -2))
		occupant._start_walking_to_chair(chair)
		occupant.set_physics_process(true)
		for index in range(600):
			await physics_frame
			if occupant.state == OfficeWorker.State.WORKING:
				break
		occupant.set_physics_process(false)
		check(occupant.state == OfficeWorker.State.WORKING and occupant.is_seated, "Worker reaches and sits on a solid rotated chair")
		occupant._begin_standing()
		occupant._idle_after_standing = true
		occupant.set_physics_process(true)
		for index in range(240):
			await physics_frame
			if not occupant.is_seated:
				break
		occupant.set_physics_process(false)
		check(not occupant.is_seated and not occupant.collision_shape.disabled, "Worker stands and restores collision")
		var exit_point := chair.to_local(occupant.global_position)
		check(exit_point.z > chair.footprint_size.z * 0.5 + 0.24, "Worker stands in front of the chair instead of behind the backrest")
		occupant.nav_agent.avoidance_enabled = false
		occupant.global_position = Vector3(-11, 0, 8)

	chair.owner_worker = null
	chair.reserved_by = null
	player.global_position = chair.get_chair_approach_pos()
	player.nearby = chair
	player.busy = 0.0
	player.interact()
	await frames()
	check(player.seated and player.sitting_chair == chair, "Player can sit on a solid chair")
	player.busy = 0.0
	player.interact()
	await frames()
	check(player.standing_up and player.seated and player.collision_shape.disabled and player.global_position.is_equal_approx(chair.get_seat_world_pos()), "Standing starts at the seat without teleporting or restoring collision inside the chair")
	var last_position := player.global_position
	var largest_step := 0.0
	for i in range(240):
		if not player.standing_up: break
		player._physics_process(1.0 / 60.0)
		largest_step = maxf(largest_step, last_position.distance_to(player.global_position))
		last_position = player.global_position
		await frames(1)
	check(not player.seated and not player.standing_up and not player.collision_shape.disabled and player.global_position.is_equal_approx(chair.get_chair_approach_pos()), "Player finishes standing in front with collision restored")
	check(largest_step < 0.08 and chair.reserved_by == null and player.sitting_chair == null, "Standing moves smoothly and releases the seat only after the transition")

	# A real desk blocks the front of a workstation; stand beside it instead.
	var desk: FurnitureItem = office.place_furniture_item("desk_plain", chair.to_global(Vector3(0, 0, chair.footprint_size.z * 0.5 + 0.6)), chair.rotation.y, false)
	player.global_position = chair.get_seat_world_pos()
	player.seated = true
	player.sitting_chair = chair
	player.collision_shape.disabled = true
	chair.reserved_by = player
	await frames()
	check(player.stand_from_chair(), "A desk in front still allows standing through a clear side")
	var side_exit := chair.to_local(player._stand_destination)
	check(absf(side_exit.x) > chair.footprint_size.x * 0.5 + 0.24 and side_exit.z >= -0.01, "Blocked front selects a side rather than the back of the chair")
	for i in range(240):
		if not player.standing_up: break
		player._physics_process(1.0 / 60.0)
		await frames(1)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.collision_shape.shape
	query.transform = player.collision_shape.global_transform
	query.transform.origin.y += 0.02
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	check(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Standing beside a desk ends clear of all furniture colliders")
	desk.queue_free()
	await frames()
	player.global_position = chair.get_seat_world_pos()
	player.seated = true
	player.sitting_chair = chair
	player.collision_shape.disabled = true
	chair.reserved_by = player
	var blockers: Array[Node3D] = []
	for offset in [Vector3(0, 0, chair.footprint_size.z * 0.5 + 0.45), Vector3(chair.footprint_size.x * 0.5 + 0.45, 0, 0), Vector3(-chair.footprint_size.x * 0.5 - 0.45, 0, 0)]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var obstacle := BoxShape3D.new()
		obstacle.size = Vector3(0.35, 2.0, 0.35)
		shape.shape = obstacle
		body.add_child(shape)
		office.add_child(body)
		body.global_position = chair.to_global(offset) + Vector3.UP
		blockers.append(body)
	await frames()
	check(not player.stand_from_chair() and player.seated and not player.standing_up and chair.reserved_by == player, "Fully blocked exits keep the player seated rather than spawning inside a blocker or behind the chair")
	for body in blockers: body.queue_free()
	print("CHAIR CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
