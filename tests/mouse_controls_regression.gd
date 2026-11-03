extends SceneTree

var office: Node3D
var player: OfficePlayer
var checks := 0
var failures: Array[String] = []
const ORIGIN := Vector3(-7, 0, 5)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func frames(count := 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func screen(point: Vector3) -> Vector2:
	return office.iso_camera.camera.unproject_position(point)

func motion(at: Vector2, relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	root.push_input(event, true)

func button(code: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = code
	event.pressed = pressed
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func pickup_book() -> PhysicsProp:
	player.mouse_controls.cancel()
	player.prop_handling.reset()
	var prop: PhysicsProp = office.spawn_prop("book", player.global_position + Vector3(0, 0.035, 0.65))
	prop.freeze = true
	await frames()
	var point := screen(prop.global_position + Vector3.UP * prop.footprint_size.y * 0.5)
	motion(point)
	await frames(1)
	button(MOUSE_BUTTON_LEFT, true, point)
	button(MOUSE_BUTTON_LEFT, false, point)
	await frames(25)
	return prop

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	player = office.player
	player.nav_agent.avoidance_enabled = false
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker.global_position = Vector3(11, 0, 8)
	for item in office.furniture_container.get_children(): item.queue_free()
	for prop in office.props_container.get_children(): prop.queue_free()
	office._request_navmesh_rebake()
	player.global_position = ORIGIN
	office.iso_camera.target_yaw_deg = 0
	office.iso_camera.target_zoom = 10
	await frames(60)
	var goal := ORIGIN + Vector3(0, 0, 2)
	var at := screen(goal)
	motion(at)
	button(MOUSE_BUTTON_LEFT, true, at)
	await frames(2)
	check(player.mouse_controls.moving and player.mouse_controls.dragging and player.mouse_controls.marker.visible, "Left press creates a visible navigation destination")
	button(MOUSE_BUTTON_LEFT, false, at)
	await frames(70)
	check(player.global_position.distance_to(goal) < 0.5 and not player.mouse_controls.moving, "A ground click walks to the destination and stops")

	# Use a real furniture obstruction and a rebaked map; click navigation must
	# take a route around the desk rather than walking into its collision box.
	player.global_position = ORIGIN
	var desk: FurnitureItem = office.place_furniture_item("desk_plain", ORIGIN + Vector3(0, 0, 1.5), 0, false)
	office._request_navmesh_rebake()
	await frames(40)
	goal = ORIGIN + Vector3(0, 0, 3)
	at = screen(goal)
	motion(at)
	button(MOUSE_BUTTON_LEFT, true, at)
	button(MOUSE_BUTTON_LEFT, false, at)
	var deviation := 0.0
	for i in range(140):
		await frames(1)
		deviation = maxf(deviation, absf(player.global_position.x - ORIGIN.x))
	check(player.global_position.distance_to(goal) < 0.6 and deviation > desk.footprint_size.x * 0.4, "Click movement navigates around blocking furniture")
	desk.queue_free()
	office._request_navmesh_rebake()
	await frames(40)
	goal = player.global_position + Vector3(0.05, 0, 0)
	at = screen(goal)
	motion(at)
	button(MOUSE_BUTTON_LEFT, true, at)
	await frames(5)
	check(player.mouse_controls.dragging and not player.mouse_controls.moving, "Reaching the cursor keeps a held steering gesture active")

	goal = player.global_position + Vector3(1.6, 0, 0)
	at = screen(goal)
	motion(at)
	await frames(12)
	check(player.mouse_controls.moving, "Moving the cursor after arrival resumes held steering")
	goal = ORIGIN + Vector3(-1.0, 0, 1.0)
	at = screen(goal)
	motion(at)
	await frames(10)
	check(Vector2(player.mouse_controls.destination.x - goal.x, player.mouse_controls.destination.z - goal.z).length() < 0.3, "Holding left mouse steers toward a changed cursor position")
	button(MOUSE_BUTTON_LEFT, false, at)
	key(KEY_D, true)
	await frames(3)
	check(not player.mouse_controls.moving and player.velocity.x > 0, "Keyboard movement immediately overrides a mouse destination")
	key(KEY_D, false)
	await frames()
	check(not player.mouse_controls.move_to(Vector3(100, 0, 100)), "Mouse movement rejects destinations outside the office")
	var old_yaw: float = office.iso_camera.target_yaw_deg
	at = screen(player.global_position + Vector3(3, 0, 0))
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(16)
	check(player.mouse_controls.aiming and player.mouse_controls.reticle.visible and player.global_basis.z.dot(Vector3.RIGHT) > 0.9, "Right hold aims and turns the character toward the cursor")
	check(is_equal_approx(old_yaw, office.iso_camera.target_yaw_deg) and not office.iso_camera._is_panning_drag, "Right aiming does not move or rotate the camera")
	key(KEY_S, true)
	await frames(5)
	check(player.velocity.z > 0 and player.global_basis.z.dot(Vector3.RIGHT) > 0.85, "Keyboard movement can strafe while mouse aim controls facing")
	key(KEY_S, false)
	button(MOUSE_BUTTON_RIGHT, false, at)
	await frames()
	check(not player.mouse_controls.aiming, "Releasing empty-hand aim clears its reticle")

	# The old floor-only projection missed a person when aiming at their chest.
	var target: OfficeWorker = office.workers_container.get_child(0)
	target._enter_idle(1000)
	target.collision_shape.disabled = false
	target.global_position = player.global_position + Vector3(3, 0, 0)
	await frames()
	for yaw in [0.0, 65.0, 140.0]:
		office.iso_camera.target_yaw_deg = yaw
		await frames(40)
		at = screen(target.global_position + Vector3.UP * 1.3)
		motion(at)
		button(MOUSE_BUTTON_RIGHT, true, at)
		await frames(16)
		check(player.global_basis.z.dot(Vector3.RIGHT) > 0.98, "Aiming at a coworker's chest faces the coworker at camera angle %.0f" % yaw)
		check(player.prop_handling.aim_direction.dot(Vector3.RIGHT) > 0.98, "Throw aim shares the visible character target at camera angle %.0f" % yaw)
		button(MOUSE_BUTTON_RIGHT, false, at)
	target.is_seated = true
	target.collision_shape.disabled = true
	target.play_anim("sitting_idle")
	await frames(30)
	var skeleton := target.rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var torso := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("office_Spine2")).origin)
	at = screen(torso)
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(16)
	check(player.global_basis.z.dot(Vector3.RIGHT) > 0.98, "Visible seated coworkers remain aimable with their movement collider disabled")
	button(MOUSE_BUTTON_RIGHT, false, at)
	target._enter_idle(1000)
	target.global_position = Vector3(11, 0, 8)
	office.iso_camera.target_yaw_deg = 0
	await frames(40)

	var prop := await pickup_book()
	check(player.held_prop == prop and prop.is_held(), "Clicking a reachable prop picks up the clicked object")
	target.global_position = player.global_position + Vector3(3, 0, 0)
	await frames()
	at = screen(target.global_position + Vector3.UP * 1.3)
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(20)
	check(player.prop_handling.aim_direction.dot(Vector3.RIGHT) > 0.98, "Charged throws target a coworker's body rather than the floor behind it")
	button(MOUSE_BUTTON_RIGHT, false, at)
	await frames(1)
	check(prop.linear_velocity.x > 2 and absf(prop.linear_velocity.z) < 0.2, "Releasing over a coworker's body preserves the correct throw direction")
	prop.queue_free()
	target.global_position = Vector3(11, 0, 8)
	await frames(20)
	prop = await pickup_book()
	at = screen(player.global_position + Vector3(3, 0, 0))
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(38)
	check(player.prop_handling.charge_source == "mouse" and player.prop_handling.charge_fraction() > 0.25 and player.prop_handling.preview.visible, "Right hold charges a carried prop with a trajectory")
	key(KEY_T, false)
	await frames(1)
	check(player.held_prop == prop and player.prop_handling.charging, "A keyboard release cannot release a mouse-owned charge")
	button(MOUSE_BUTTON_RIGHT, false, at)
	await frames(1)
	check(player.held_prop == null and prop.linear_velocity.x > 2, "Right release throws the prop toward the cursor")
	check(not player.prop_handling.preview.visible and not player.mouse_controls.aiming, "A mouse throw clears aim and preview state")
	prop.queue_free()
	await frames(20)

	prop = await pickup_book()
	at = screen(player.global_position + Vector3(2, 0, 0))
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(12)
	key(KEY_P, true)
	key(KEY_P, false)
	await frames()
	check(paused and not player.mouse_controls.is_active() and not player.prop_handling.charging, "Pause clears movement, aiming and pending mouse throws")
	button(MOUSE_BUTTON_RIGHT, false, at)
	key(KEY_P, true)
	key(KEY_P, false)
	await frames()
	check(player.held_prop == prop and not prop.owner_grace > 0, "Release during pause cannot fire after resume")
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(5)
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await frames()
	button(MOUSE_BUTTON_RIGHT, false, at)
	check(not paused and player.held_prop == prop and not player.mouse_controls.aiming, "Esc cancels mouse aim before pausing and releasing cannot throw")

	var layer := CanvasLayer.new()
	var ui := Button.new()
	ui.position = Vector2(20, 540)
	ui.size = Vector2(180, 60)
	ui.text = "Mouse test control"
	layer.layer = 20
	layer.add_child(ui)
	root.add_child(layer)
	await frames()
	at = screen(player.global_position + Vector3(2, 0, 0))
	motion(at)
	button(MOUSE_BUTTON_RIGHT, true, at)
	await frames(8)
	motion(Vector2(100, 570))
	await frames(3)
	button(MOUSE_BUTTON_RIGHT, false, Vector2(100, 570))
	await frames()
	check(player.held_prop == prop and not player.prop_handling.charging, "Releasing aim over UI cancels instead of throwing")
	button(MOUSE_BUTTON_LEFT, true, Vector2(100, 570))
	button(MOUSE_BUTTON_LEFT, false, Vector2(100, 570))
	await frames()
	check(not player.mouse_controls.moving, "Clicking UI cannot start walking")
	layer.queue_free()
	await frames()
	player.place_prop()
	await frames(20)
	prop.queue_free()
	player.mouse_controls.move_to(player.global_position + Vector3(1, 0, 0))
	office.set_editor_visible(true)
	check(not player.mouse_controls.is_active(), "Opening the furniture editor cancels mouse movement")
	at = screen(player.global_position + Vector3(2, 0, 0))
	motion(at)
	button(MOUSE_BUTTON_LEFT, true, at)
	button(MOUSE_BUTTON_LEFT, false, at)
	await frames()
	check(not player.mouse_controls.moving, "Editor clicks cannot move the character")
	office.set_editor_visible(false)

	at = Vector2(600, 450)
	motion(at)
	button(MOUSE_BUTTON_MIDDLE, true, at)
	await frames(1)
	check(office.iso_camera._is_panning_drag, "Middle mouse starts camera panning")
	motion(at + Vector2(60, 0), Vector2(60, 0))
	await frames(2)
	check(office.iso_camera.pan_offset.length() > 0.1, "Camera pan is preserved while following the character")
	button(MOUSE_BUTTON_MIDDLE, false, at)
	key(KEY_SHIFT, true)
	await frames(1)
	button(MOUSE_BUTTON_MIDDLE, true, at)
	await frames(1)
	var yaw: float = office.iso_camera.target_yaw_deg
	motion(at + Vector2(50, 0), Vector2(50, 0))
	await frames(2)
	check(office.iso_camera._is_rotating_drag and not is_equal_approx(office.iso_camera.target_yaw_deg, yaw), "Shift-middle drag rotates the camera")
	button(MOUSE_BUTTON_MIDDLE, false, at)
	key(KEY_SHIFT, false)
	await frames()
	check(not office.iso_camera._is_rotating_drag and not office.iso_camera._is_panning_drag, "Camera drags stop on release")
	var zoom: float = office.iso_camera.target_zoom
	button(MOUSE_BUTTON_WHEEL_UP, true, at)
	button(MOUSE_BUTTON_WHEEL_UP, false, at)
	await frames()
	check(office.iso_camera.target_zoom < zoom, "Mouse wheel still zooms")
	player.mouse_controls.move_to(player.global_position + Vector3(1, 0, 0))
	player.interrupt_for_combat()
	check(not player.mouse_controls.is_active(), "Combat interruption clears mouse navigation")
	print("MOUSE CONTROLS CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
