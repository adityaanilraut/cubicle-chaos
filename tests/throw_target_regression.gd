extends SceneTree

const ORIGIN := Vector3(35, 0, 35)
var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count := 4) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func barrier(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
	return body

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	player = office.player
	player.set_physics_process(false)
	player.global_position = ORIGIN
	player.rotation.y = PI * 0.5
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person.global_position = Vector3(-9, 0, 8)
	var floor_body := barrier(ORIGIN + Vector3(0, -0.2, 0), Vector3(20, 0.4, 20))
	var near: OfficeWorker = office.workers_container.get_child(0)
	var far: OfficeWorker = office.workers_container.get_child(1)
	var behind: OfficeWorker = office.workers_container.get_child(2)
	near._enter_idle(1000)
	far._enter_idle(1000)
	behind._enter_idle(1000)
	near.global_position = ORIGIN + Vector3(2.5, 0, 0.45)
	far.global_position = ORIGIN + Vector3(4, 0, -0.5)
	behind.global_position = ORIGIN + Vector3(-1, 0, 0)
	var prop: PhysicsProp = office.spawn_prop("book", ORIGIN + Vector3(0.65, 0.03, 0))
	prop.freeze = true
	await frames()
	check(player.prop_handling.pick_up(prop), "Can pick up an object before aiming")
	for i in range(25):
		player.prop_handling.tick(1.0 / 60.0)
		await frames(1)
	player.prop_handling.mouse_seen = false
	check(player.prop_handling.begin_charge(), "Keyboard throw begins")
	player.prop_handling.charge_time = 0.7
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == near, "Nearest person in front wins over a farther or behind person")
	check(player.prop_handling.aim_direction.dot((near.global_position - player.global_position).normalized()) > 0.999, "Throw direction points at the locked person")
	check(player.prop_handling.target_ring.visible and player.prop_handling.charge_label.text.contains(near.worker_name), "Aim shows a named target and visible ring")
	var block := barrier(ORIGIN + Vector3(1.4, 1, 0.3), Vector3(0.2, 2, 0.65))
	await frames()
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == near, "A wall does not change which person is nearest")
	check(player.prop_handling.landing.global_position.x < near.global_position.x - 0.5, "Trajectory preview still stops at the intervening wall")
	block.queue_free()
	await frames()
	# Point the mouse at the far person: the closer person in that direction
	# still wins, regardless of which body the cursor happens to cover.
	office.iso_camera.position = ORIGIN
	office.iso_camera.target_pos = ORIGIN
	office.iso_camera.set_process(false)
	var screen_point: Vector2 = office.iso_camera.camera.unproject_position(far.global_position + Vector3.UP * 1.0)
	player.mouse_controls.set_pointer(screen_point)
	player.prop_handling.charge_source = "mouse"
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == near, "Mouse aim also locks the nearest person in the aimed direction")
	player.prop_handling.mouse_seen = false
	player.prop_handling.charge_source = "keyboard"
	player.prop_handling.manual_aim_direction = Vector3.RIGHT
	near.global_position = ORIGIN + Vector3(-2, 0, 0)
	far.global_position = ORIGIN + Vector3(-4, 0, 0)
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == null and player.prop_handling.aim_direction.dot(Vector3.RIGHT) > 0.999, "No one in front leaves aim under player control")
	near.global_position = ORIGIN + Vector3(3, 0, 0)
	await frames()
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == near, "Aim reacquires someone who enters the aimed direction")
	player.prop_handling.charge_time = 1.16
	player.prop_handling.tick(0.0)
	var expected := player.prop_handling._launch_velocity(prop, prop.global_position, 1.0)
	var base := prop.launch_velocity(player.prop_handling.aim_direction, 1.0)
	check(is_equal_approx(Vector2(expected.x, expected.z).length(), Vector2(base.x, base.z).length()), "Lock retains normal mass and charge throw speed")
	check(player.prop_handling.release_throw(), "Releasing launches the locked throw")
	check(prop.linear_velocity.distance_to(expected) < 0.01 and not player.prop_handling.target_ring.visible, "Actual throw matches preview velocity and clears its marker")
	await frames(50)
	check(near.combat.health < 100.0, "A fully charged throw physically hits a nearby locked person")
	if is_instance_valid(prop): prop.queue_free()
	await frames()
	near.combat.reset()
	near.combat.health = 100.0
	near.combat.balance = 100.0
	near.global_position = ORIGIN + Vector3(3, 0, 0)
	near.is_seated = true
	near.collision_shape.disabled = true
	player.prop_handling.reset()
	player.global_position = ORIGIN
	player.rotation.y = PI * 0.5
	prop = office.spawn_prop("book", ORIGIN + Vector3(0.65, 0.03, 0))
	prop.freeze = true
	await frames()
	check(player.prop_handling.pick_up(prop), "Can prepare a throw at a seated coworker")
	for i in range(25):
		player.prop_handling.tick(1.0 / 60.0)
		await frames(1)
	check(player.prop_handling.begin_charge(), "Can aim at a seated coworker")
	player.prop_handling.charge_time = 0.7
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == near, "A seated coworker can be locked")
	check(player.prop_handling.landing.global_position.distance_to(near.global_position + Vector3.UP * 0.85) < 0.45, "Trajectory preview marks the seated person's hit area")
	check(player.prop_handling.release_throw(), "Seated-target throw releases")
	await frames(50)
	check(near.combat.health < 100.0, "A thrown prop physically reaches a seated coworker with disabled movement collision")
	if is_instance_valid(prop): prop.queue_free()
	await frames()
	near.combat.reset()
	near.combat.health = 100.0
	near.combat.balance = 100.0
	near._enter_idle(1000)
	near.global_position = ORIGIN + Vector3(3, 0, 0)
	player.prop_handling.reset()
	player.global_position = ORIGIN
	player.rotation.y = PI * 0.5
	prop = office.spawn_prop("book", ORIGIN + Vector3(0.65, 0.03, 0))
	prop.freeze = true
	await frames()
	check(player.prop_handling.pick_up(prop), "Can prepare a throw before a wall")
	for i in range(25):
		player.prop_handling.tick(1.0 / 60.0)
		await frames(1)
	block = barrier(ORIGIN + Vector3(1.6, 1, 0), Vector3(0.2, 2, 2))
	await frames()
	check(player.prop_handling.begin_charge(), "Can lock a person beyond a wall")
	player.prop_handling.charge_time = 0.7
	player.prop_handling.tick(0.0)
	check(player.prop_handling.locked_person == near, "The nearest person remains locked behind a wall")
	check(player.prop_handling.release_throw(), "Throw releases from its safe held position")
	await frames(40)
	check(is_equal_approx(near.combat.health, 100.0), "A wall physically prevents damage to the locked person")
	if is_instance_valid(prop): prop.queue_free()
	block.queue_free()
	floor_body.queue_free()
	office.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("THROW TARGET CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
