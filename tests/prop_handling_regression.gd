extends SceneTree

var office: Node3D
var player: OfficePlayer
var failures: Array[String] = []
var checks := 0
const ARENA := Vector3(35, 0, 35)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func settle(frames := 4) -> void:
	for i in range(frames):
		await physics_frame
		await process_frame

func advance(seconds: float) -> void:
	for i in range(ceili(seconds * 60)):
		player.prop_handling.tick(1.0 / 60)
		await settle(1)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	body.global_position = at
	return body

func clear_carry() -> void:
	if is_instance_valid(player.held_prop):
		player.held_prop.queue_free()
		player.held_prop = null
	player.prop_handling.reset()

func new_prop(id: String) -> PhysicsProp:
	clear_carry()
	player.global_position = ARENA
	player.rotation = Vector3.ZERO
	var prop: PhysicsProp = office.spawn_prop(id, ARENA + Vector3(0, 0.035, 0.65))
	prop.freeze = true
	return prop

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	player = office.player
	player.set_physics_process(false)
	for worker in office.workers_container.get_children(): worker.set_physics_process(false)
	var floor_body := wall(ARENA + Vector3(0, -0.2, 0), Vector3(18, 0.4, 18))
	var prop := new_prop("book")
	await settle()
	check(player.try_pickup_prop(), "Reachable book can be picked up")
	check(prop.is_held() and prop.freeze and prop.linear_velocity == Vector3.ZERO, "Held prop is reserved and motionless")
	check(not player.try_grab_furniture(), "Cannot grab furniture while carrying a prop")
	await advance(0.4)
	check(prop.global_position.y > 0.7, "Pickup lifts the object toward the chest")
	var skeleton := player.rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	player.prop_grip._process_modification()
	for side in ["Left", "Right"]:
		var hand := skeleton.find_bone("office_" + side + "Hand")
		var position := skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
		check(position.distance_to(prop.global_position + Vector3.UP * prop.footprint_size.y * 0.4) < 0.55, side + " hand reaches the carried object")
	key(KEY_T, true)
	await settle()
	check(player.prop_handling.charging and player.held_prop == prop, "T press begins charge without throwing")
	await advance(0.7)
	check(player.prop_handling.charge_fraction() > 0.4 and player.prop_handling.preview.visible, "Holding T raises charge and shows the arc")
	key(KEY_T, false)
	await settle()
	check(player.held_prop == null and not prop.freeze and prop.linear_velocity.length() > 5, "T release launches a charged throw")
	check(not player.prop_handling.preview.visible, "Throw hides trajectory")
	check(prop.owner_grace > 0 and player in prop.get_collision_exceptions(), "Release temporarily ignores the thrower")
	await settle(25)
	check(not player in prop.get_collision_exceptions(), "Thrower collision grace expires")
	prop.queue_free()

	prop = new_prop("book")
	await settle()
	player.try_pickup_prop()
	await advance(0.4)
	key(KEY_T, true)
	await settle(1)
	key(KEY_T, false)
	await settle(1)
	check(player.held_prop == null and prop.linear_velocity.length() > 1, "A quick T tap throws immediately on release")
	prop.queue_free()

	var light := new_prop("keyboard")
	var heavy: PhysicsProp = office.spawn_prop("speaker", ARENA + Vector3(3, 0.035, 0))
	heavy.freeze = true
	check(heavy.mass > light.mass and heavy.carry_speed_scale < light.carry_speed_scale, "Heavy objects have distinct mass and slower carrying")
	check(heavy.launch_velocity(Vector3.FORWARD).length() < light.launch_velocity(Vector3.FORWARD).length(), "Heavy objects travel more slowly for equal throw strength")
	check(light.launch_velocity(Vector3.FORWARD, 1).length() > light.launch_velocity(Vector3.FORWARD, 0).length(), "Charge increases launch strength")
	light.queue_free()
	heavy.queue_free()

	prop = new_prop("book")
	var blocker := wall(ARENA + Vector3(0, 0.9, 0.35), Vector3(2, 1.8, 0.12))
	await settle()
	check(not player.prop_handling.can_pick_up(prop) and not player.try_pickup_prop(), "Pickup cannot reach through a wall")
	blocker.queue_free()
	await settle()
	player.try_pickup_prop()
	await advance(0.4)
	blocker = wall(ARENA + Vector3(0, 1.0, 1.0), Vector3(2, 2, 0.12))
	await settle()
	check(not prop.can_move_to(ARENA + Vector3(0, 0.8, 1.5), 0, [player.get_rid()]), "Swept held volume cannot pass through a wall")
	player.prop_handling.begin_charge()
	await advance(0.3)
	office.game_menu.pause_game()
	check(not player.prop_handling.charging and not player.prop_handling.preview.visible, "Pausing cancels charge without releasing the object")
	office.game_menu.start_game()
	key(KEY_T, false)
	await settle()
	check(player.held_prop == prop, "A release arriving after pause does not throw")
	blocker.queue_free()
	await settle()
	check(player.prop_handling.begin_charge(), "Charge can start again after resume")
	key(KEY_ESCAPE, true)
	await settle()
	check(not player.prop_handling.charging and office.game_menu.menu_state == &"playing", "Esc cancels aim before pausing")
	player.prop_handling.set_aim_point(ARENA + Vector3(8, 0, 0))
	check(player.prop_handling.aim_direction.dot(Vector3.RIGHT) > 0.99, "World aim points at the requested mouse target")
	clear_carry()
	await settle()

	# A table outside the office isolates placement from the furnished layout.
	player.global_position = ARENA
	var table: FurnitureItem = office.place_furniture_item("desk_plain", ARENA + Vector3(0, 0, 1.15), 0.0, false)
	prop = new_prop("keyboard")
	prop.global_position = ARENA + Vector3(0.7, 0.035, 0)
	await settle()
	check(player.try_pickup_prop(), "Can pick up beside a table")
	await advance(0.4)
	var placement := player.prop_handling.find_placement()
	check(placement.get("support") == table, "Gentle placement prefers a reachable clear tabletop")
	check(player.place_prop(), "G placement releases onto the table")
	check(player.held_prop == null and prop.linear_velocity.is_zero_approx() and prop.angular_velocity.is_zero_approx(), "Gentle placement starts with no velocity or spin")
	await settle(15)
	check(prop.global_position.y > 0.3, "Placed prop rests above floor height")
	prop.queue_free()
	table.queue_free()
	await settle()

	# A nearby coworker and prop have different click targets, even though the
	# circles share one on-screen anchor. Neither action may steal the other.
	prop = new_prop("book")
	prop.global_position = ARENA + Vector3(0.65, 0.035, 0)
	var coworker: OfficeWorker = office.spawn_worker(ARENA + Vector3(0, 0, 1.2))
	coworker.set_physics_process(false)
	coworker._enter_idle(100)
	await settle()
	player._update_nearby()
	check(player.nearby == coworker and player.interaction_actions.action_ids.has("interact") and player.interaction_actions.action_ids.has("prop_pickup"), "Coworker and prop can both offer their own nearby actions")
	var pickup_index := player.interaction_actions.action_ids.find("prop_pickup")
	if pickup_index >= 0:
		player.interaction_actions.buttons[pickup_index].button_down.emit()
		player.interaction_actions.buttons[pickup_index].pressed.emit()
	check(player.held_prop == prop, "Prop circle picks up its own target when a coworker is also nearby")
	clear_carry()
	coworker.queue_free()
	await settle()

	prop = new_prop("book")
	await settle()
	player.try_pickup_prop()
	await advance(0.4)
	player.interrupt_for_combat()
	check(player.held_prop == null and not prop.is_held() and not prop.freeze, "Combat interruption drops the prop and clears carrying state")
	check(not player.prop_handling.charging, "Combat leaves no pending charge")
	prop.queue_free()
	clear_carry()
	floor_body.queue_free()
	print("PROP HANDLING CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
