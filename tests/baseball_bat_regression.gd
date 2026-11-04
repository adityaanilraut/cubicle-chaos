extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer
var worker: OfficeWorker
var bat: PhysicsProp
var origin := Vector3(30, 0, 30)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func settle(frames := 3) -> void:
	for i in range(frames):
		await physics_frame
		await process_frame

func reset_fighters() -> void:
	for actor in [player, worker]:
		actor.combat.reset()
		actor.combat.health = 100.0
		actor.combat.balance = 100.0
		actor._enter_idle(100.0)
	player.busy = 0.0
	player.seated = false
	player.global_position = origin
	player.rotation.y = 0.0
	worker.global_position = origin + Vector3(0, 0, 1.30)
	worker.rotation.y = PI
	if is_instance_valid(bat) and player.held_prop == bat:
		bat.global_transform = BaseballBat.held_pose(player)

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	player = office.player
	player.set_physics_process(false)
	player.nav_agent.avoidance_enabled = false
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person.nav_agent.avoidance_enabled = false
	worker = office.workers_container.get_child(0)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(16, 0.3, 16)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	office.add_child(floor_body)
	floor_body.global_position = origin + Vector3(0, -0.15, 0)
	reset_fighters()
	check(office.props_container.get_children().any(func(p): return p is PhysicsProp and p.prop_id == "baseball_bat"), "A bat is available in the default office")
	bat = office.spawn_prop("baseball_bat", origin + Vector3(0, 0.04, 0.55))
	bat.freeze = true
	await settle()
	check(bat.prop_title == "Baseball bat" and is_equal_approx(bat.mass, 0.95), "Bat has its own title, mass and procedural model")
	check(bat.destructible.profile.material_id == "wood", "Bat breaks into wooden components")
	check(player.prop_handling.pick_up(bat), "The normal pickup action equips the bat")
	check(not player.try_attack("light"), "Pickup animation finishes before swinging")
	player.prop_handling.tick(0.4)
	check(player.combat.has_bat() and player.held_prop == bat, "Equipped bat remains held")
	check(player.get_context_actions().any(func(a): return a.id == "bat_heavy"), "Context controls expose the heavy smash")
	check(player.try_attack("light"), "Light attack starts a bat swing with occupied hands")
	check(player.held_prop == bat and player.combat.move_id == "bat_forehand", "Attacking retains the weapon and chooses the forehand")
	player.combat.tick(0.08)
	check(worker.combat.health == 100.0, "Bat windup causes no early damage")
	player.combat.tick(0.26)
	check(worker.combat.health < 100.0 and player.combat.last_attack_hit, "Swept barrel hits a standing NPC across a long frame")
	var health := worker.combat.health
	player.combat.tick(0.10)
	check(worker.combat.health == health, "The same swing cannot repeatedly damage an NPC")
	check(worker.combat.hit_motion.running and not worker.combat.hit_motion.freeze, "Bat contact enables the Jolt reaction body")
	check(worker.combat.hit_motion.last_impulse.length() >= 45.0 and worker.collision_layer == 0, "Momentum impulse replaces the character movement collider")
	paused = true
	var paused_position := worker.combat.hit_motion.global_position
	await create_timer(0.08, true).timeout
	check(worker.combat.hit_motion.global_position.is_equal_approx(paused_position), "Pause freezes physics-driven NPC motion")
	paused = false
	var before := worker.global_position
	for i in range(10):
		await settle(1)
		worker.combat.tick(1.0 / 60.0)
	check(worker.global_position.distance_to(before) > 0.04, "Jolt actually moves the NPC after impact")
	player.combat.tick(0.5)
	check(player.try_attack("light") and player.combat.move_id == "bat_backhand", "A chained light strike uses a different backhand animation")
	reset_fighters()
	await settle()
	check(player.try_attack("heavy") and player.combat.move_id == "bat_overhead", "Heavy attack selects the overhead animation")
	player.combat.tick(0.52)
	check(worker.combat.is_down(), "A clean heavy smash can knock an NPC down")
	check(worker.combat.hit_motion.running, "Knockdown remains driven by the physics engine")
	worker.combat.tick(OfficeCombat.FALL_TIME)
	worker.combat.tick(OfficeCombat.GET_UP_TIME + 0.01)
	check(not worker.combat.hit_motion.running and worker.collision_layer == 4, "Recovery restores the normal character collider")
	reset_fighters()
	await settle()
	player.try_attack("light")
	player.combat.tick(0.08)
	worker.global_position.z += 3.0
	await settle()
	player.combat.tick(0.34)
	check(worker.combat.health == 100.0, "Moving away during bat windup dodges the barrel")
	reset_fighters()
	worker.global_position = origin + Vector3(0, 0, 3)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 2.5, 0.10)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	office.add_child(wall)
	wall.global_position = origin + Vector3(0, 1.25, 0.72)
	worker.global_position.z = origin.z + 1.3
	await settle()
	player.try_attack("light")
	player.combat.tick(0.42)
	check(worker.combat.health == 100.0 and player.combat.bat_strike.blocked, "A thin wall blocks the swept bat and protects people behind it")
	wall.queue_free()
	await settle()
	reset_fighters()
	worker.global_position = origin + Vector3(0, 0, 3)
	var prop: PhysicsProp = office.spawn_prop("monitor", origin + Vector3(0, 0.04, 1.05))
	prop.freeze = true
	await settle()
	player.try_attack("heavy")
	player.combat.tick(0.62)
	check(prop.is_queued_for_deletion(), "An overhead smash destroys a loose object")
	check(not get_nodes_in_group("destruction_debris").is_empty(), "Breaking the object spawns physical debris")
	var effect: MaterialBurst
	for candidate in get_nodes_in_group("material_effects"):
		if is_instance_valid(candidate.flow): effect = candidate
	check(is_instance_valid(effect) and is_instance_valid(effect.shock_ring), "Destruction includes a burst pulse and directional debris plume")
	if is_instance_valid(effect):
		effect._process(0.06)
		check(effect.flow_started and effect.flow.emitting, "The delayed debris flow starts after the impact burst")
	await settle()
	reset_fighters()
	worker.global_position = origin + Vector3(0, 0, 3)
	var furniture: FurnitureItem = office.place_furniture_item("potted_plant", origin + Vector3(0, 0, 1.1), 0.0, false)
	furniture.health = 10.0
	await settle()
	player.try_attack("heavy")
	player.combat.tick(0.62)
	check(furniture.is_queued_for_deletion(), "The same bat sweep destroys furniture through its normal damage path")
	await settle()
	reset_fighters()
	worker.is_seated = true
	worker.collision_shape.set_deferred("disabled", true)
	await settle()
	player.try_attack("light")
	player.combat.tick(0.38)
	check(worker.combat.health < 100.0 and not worker.is_seated, "A bat also hits seated coworkers and interrupts sitting")
	reset_fighters()
	var block := StaticBody3D.new()
	var block_shape := CollisionShape3D.new()
	var block_box := BoxShape3D.new()
	block_box.size = Vector3(0.10, 2.5, 6)
	block_shape.shape = block_box
	block.add_child(block_shape)
	office.add_child(block)
	block.global_position = worker.global_position + Vector3(0.65, 1.25, 0)
	await settle()
	var wall_x := block.global_position.x
	worker.combat.receive_bat_hit(player, CombatMoves.get_move("bat_forehand"), Vector3(20, 0, 0), worker.global_position + Vector3.UP)
	for i in range(25):
		await settle(1)
		worker.combat.tick(1.0 / 60.0)
	check(worker.global_position.x <= wall_x - 0.20, "Physics knockback collides with walls instead of passing through")
	reset_fighters()
	check(not worker.combat.hit_motion.running and worker.collision_mask == 1, "Reset cancels transient physics and restores collision settings")
	check(player.combat.receive_prop_hit(5.0, 10.0, Vector3.RIGHT, worker), "An incoming hit interrupts the player")
	check(player.held_prop == bat and bat.is_held() and bat.freeze, "A hit does not force the bat out of the player's hands")
	player._physics_process(0.05)
	check(bat.global_transform.is_equal_approx(BaseballBat.held_pose(player)), "The bat follows the player through combat knockback")
	reset_fighters()
	var overlap := StaticBody3D.new()
	var overlap_shape := CollisionShape3D.new()
	var overlap_box := BoxShape3D.new()
	overlap_box.size = Vector3(0.3, 0.3, 0.3)
	overlap_shape.shape = overlap_box
	overlap.add_child(overlap_shape)
	office.add_child(overlap)
	overlap.global_position = bat.global_transform * Vector3(0, 0.5, 0)
	await settle()
	check(not bat.fits_transform(bat.global_transform, [player.get_rid()]), "The test obstruction overlaps the held bat")
	player.global_position += Vector3(2, 0, 0)
	check(player.prop_handling.follow_held() and bat.global_transform.is_equal_approx(BaseballBat.held_pose(player)), "An obstructed bat follows the player out of the obstacle")
	check(bat.fits_transform(bat.global_transform, [player.get_rid()]), "The bat clears the obstacle")
	overlap.queue_free()
	await settle()
	reset_fighters()
	# Placement is intentionally restricted to the office floor bounds.
	player.global_position = Vector3(19, 0, 18)
	bat.global_transform = BaseballBat.held_pose(player)
	await settle()
	check(player.prop_handling.place_gently() and player.held_prop == null and not bat.is_held(), "The player can deliberately put the bat down")
	player.prop_handling.reset()
	player.global_position = origin
	bat.global_position = origin + Vector3(0, 0.04, 0.55)
	bat.global_rotation = Vector3.ZERO
	bat.freeze = true
	await settle()
	check(player.prop_handling.pick_up(bat), "The bat can be picked up after putting it down")
	player.prop_handling.tick(0.4)
	check(player.prop_handling.release_throw(0.2) and player.held_prop == null, "The bat can also be thrown using the prop controls")
	check(not bat.freeze and bat.linear_velocity.length() > 0, "Released bat uses normal rigid body physics")
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	bat.health = 45.0
	bat.freeze = true
	var saved_rotation := bat.global_rotation
	check(OfficeSave.save_game(office) and OfficeSave.load_game(office), "A shift containing a bat saves and loads")
	var restored: PhysicsProp
	for item in office.props_container.get_children():
		if item is PhysicsProp and item.prop_id == "baseball_bat" and is_equal_approx(item.health, 45.0): restored = item
	check(is_instance_valid(restored) and restored.global_rotation.is_equal_approx(saved_rotation), "Save/load retains the bat model, damage and full orientation")
	if had_save:
		var file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))
	print("BASEBALL BAT CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	office.queue_free()
	await settle(4)
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
