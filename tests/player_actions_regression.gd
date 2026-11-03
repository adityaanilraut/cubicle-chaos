extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer
var equipment: OfficeEquipment
var fixture: FurnitureItem
var origin := Vector3(2, 0, 5)

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func frames(count := 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func place(id: String, yaw := 0.0) -> void:
	equipment.cancel()
	if is_instance_valid(fixture): fixture.queue_free()
	player.global_position = origin
	player.busy = 0
	await frames()
	fixture = office.place_furniture_item(id, origin - Vector3(0, 0, 1.4), yaw, false)
	player.global_position = fixture.get_interact_world_pos()
	await frames()
	player._update_nearby()

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	office.iso_camera.target_yaw_deg = 35
	office.iso_camera.target_zoom = 5.5
	office.iso_camera.focus_on(player.global_position + Vector3.UP * 0.6)
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/previews/action-" + label + ".png"))

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	player = office.player
	equipment = player.equipment
	player.nav_agent.avoidance_enabled = false
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker.nav_agent.avoidance_enabled = false
		worker._enter_idle(100)
		worker.global_position = Vector3(-11, 0, 8)

	# Real input must change both speed and the animation state, including release.
	office.iso_camera.target_yaw_deg = 0
	player.global_position = Vector3(-9, 0, 9)
	key(KEY_S, true)
	await frames(12)
	check(not player.running and is_equal_approx(player.velocity.length(), OfficePlayer.WALK_SPEED), "WASD retains normal walking speed")
	key(KEY_SHIFT, true)
	await frames(12)
	check(player.running and is_equal_approx(player.velocity.length(), OfficePlayer.RUN_SPEED), "Holding Shift runs faster with real movement input")
	check(String(player.state_playback.get_current_node()) == "run", "Running uses its own blended animation state")
	player.set_physics_process(false)
	# Check the baked poses, not just the names of the animation states.
	var rig := OfficeCharacter.create_rig()
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var library := AssetCatalog.get_worker_animation_library()
	PlayerAnimations._sample_source(skeleton, library.get_animation("run"), 0.40)
	var left_foot := skeleton.find_bone("office_LeftFoot")
	var right_foot := skeleton.find_bone("office_RightFoot")
	check(PlayerAnimations._pose(skeleton, left_foot).origin.y > 0.35 and PlayerAnimations._pose(skeleton, right_foot).origin.y < 0.13, "Run cycle lifts one knee while the other foot contacts the floor")
	PlayerAnimations._sample_source(skeleton, library.get_animation("run"), 0.10)
	check(PlayerAnimations._pose(skeleton, right_foot).origin.y > 0.35 and PlayerAnimations._pose(skeleton, left_foot).origin.y < 0.13, "Run cycle alternates its supporting leg")
	var run_clip := library.get_animation("run")
	var lowest_foot := INF
	var widest_elbow := 0.0
	for i in range(61):
		PlayerAnimations._sample_source(skeleton, run_clip, float(i) / 60.0 * run_clip.length)
		for side in ["Left", "Right"]:
			lowest_foot = minf(lowest_foot, PlayerAnimations._pose(skeleton, skeleton.find_bone("office_" + side + "Foot")).origin.y)
			widest_elbow = maxf(widest_elbow, absf(PlayerAnimations._pose(skeleton, skeleton.find_bone("office_" + side + "ForeArm")).origin.x))
	check(lowest_foot >= 0.08, "Running feet stay above the floor throughout the entire stride")
	check(widest_elbow < 0.35, "Running elbows swing beside the torso instead of sticking sideways")
	for track in range(run_clip.get_track_count()):
		var first = run_clip.track_get_key_value(track, 0)
		var last = run_clip.track_get_key_value(track, run_clip.track_get_key_count(track) - 1)
		check(first.is_equal_approx(last), "Run loop joins without a pose jump on track %d" % track)
	PlayerAnimations._sample_source(skeleton, library.get_animation("shower"), 0.18)
	check(PlayerAnimations._pose(skeleton, skeleton.find_bone("office_LeftHand")).origin.y > 1.7, "Showering raises a hand to scrub the hair")
	PlayerAnimations._sample_source(skeleton, library.get_animation("toilet_idle"), 0.5)
	check(skeleton.get_bone_pose_position(0).y < 0.6, "Toilet idle retains a seated pelvis instead of standing")
	rig.free()
	await capture("running")
	player.set_physics_process(true)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(3, 3, 0.15)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	office.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 1.5, 0.65)
	await frames(30)
	check(not player.running and String(player.state_playback.get_current_node()) == "idle", "Running into a wall stops the run animation when the body cannot move")
	wall.queue_free()
	await frames(2)
	key(KEY_S, true)
	key(KEY_SHIFT, false)
	await frames(20)
	check(not player.running and String(player.state_playback.get_current_node()) == "walk", "Releasing Shift returns to walking")
	var cup := Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	key(KEY_SHIFT, true)
	await frames(3)
	check(not player.running, "Carrying a cup keeps walking speed")
	player.carried_cup = null
	cup.queue_free()
	key(KEY_S, false)
	await frames(20)
	check(not player.running and String(player.state_playback.get_current_node()) == "idle", "Shift alone does not animate a stationary run")
	key(KEY_SHIFT, false)
	player.set_physics_process(false)

	for id in ["toilet", "shower", "bathroom_vanity"]:
		await place(id)
		var action := String(fixture.equipment_actions()[0])
		var start := player.global_position
		check(player.nearby == fixture, id + " is discoverable as nearby equipment")
		check(not equipment.get_actions(fixture).is_empty(), id + " exposes a usable F action")
		fixture.reserved_by = office.workers_container.get_child(0)
		check(equipment.get_actions(fixture).is_empty(), id + " respects another user's reservation")
		fixture.reserved_by = null
		player.perform_context_action(action, fixture)
		check(equipment.is_active() and fixture.reserved_by == player, id + " context action reserves the fixture")
		check(fixture.is_in_use() and not player.collision_shape.disabled, id + " keeps world collision while in use")
		equipment.tick(3.0)
		await frames(20)
		check(player.global_position.distance_to(BathroomActivity.use_position(fixture)) < 0.01, id + " moves the character to its use position")
		check(player.get_collision_exceptions().has(fixture), id + " ignores only its own fixture collider")
		var expected_anim := {"toilet": "toilet_idle", "shower": "shower", "bathroom_vanity": "wash_hands"}
		check(String(player.state_playback.get_current_node()) == expected_anim[id], id + " uses its activity animation")
		if id != "toilet" and equipment.bathroom != null:
			check(equipment.bathroom.effects.visible and equipment.bathroom.drops.size() >= 16, id + " has visible animated running water")
			var drop := equipment.bathroom.drops[0]
			var before := drop.position
			equipment.tick(0.1)
			check(not drop.position.is_equal_approx(before), id + " water droplets move with activity time")
		await capture(id)
		var before_pause := equipment.remaining
		var position_before_pause := player.global_position
		office.game_menu.pause_game()
		player.set_physics_process(true)
		await create_timer(0.05, true).timeout
		check(is_equal_approx(equipment.remaining, before_pause) and player.global_position.is_equal_approx(position_before_pause), id + " progress and movement freeze on pause")
		player.set_physics_process(false)
		office.game_menu.start_game()
		equipment.tick(equipment.remaining + 0.1)
		check(not equipment.is_active() and equipment.bathroom == null and fixture.reserved_by == null, id + " completion releases effects and reservation")
		check(player.global_position.is_equal_approx(start) and not player.get_collision_exceptions().has(fixture), id + " completion returns outside and restores fixture collision")
		check(not equipment.perform(action, fixture), id + " cooldown prevents immediate repetition")
		equipment.cooldowns.clear()
		check(equipment.perform(action, fixture), id + " can start again after cooldown")
		equipment.tick(1.0)
		player.perform_context_action("cancel_activity", fixture)
		check(not equipment.is_active() and player.global_position.is_equal_approx(start) and fixture.reserved_by == null, id + " F/circle cancellation returns safely outside")
	check(equipment.stats.toilet_breaks == 1 and equipment.stats.showers_taken == 1 and equipment.stats.hands_washed == 1, "Only completed bathroom activities count")

	await place("shower", PI * 0.5)
	key(KEY_F, true)
	await frames()
	key(KEY_F, false)
	check(equipment.is_active(), "Real F input starts the rotated shower from its front entrance")
	equipment.tick(2)
	check(player.global_position.distance_to(BathroomActivity.use_position(fixture)) < 0.01, "Rotated shower places the player inside")
	player.interrupt_for_combat()
	check(not equipment.is_active() and fixture.reserved_by == null and not player.get_collision_exceptions().has(fixture), "Combat interrupts bathroom use and restores collision")
	player.busy = 0
	player.global_position = fixture.global_position - fixture.get_forward_dir()
	check(not equipment.perform("eq_shower", fixture), "Cannot enter a shower through its back")
	player.global_position = fixture.get_interact_world_pos()
	var prop: PhysicsProp = office.spawn_prop("book", origin)
	prop.pick_up(player)
	player.held_prop = prop
	check(not equipment.perform("eq_shower", fixture), "Held props prevent bathroom activities")
	player.held_prop = null
	prop.queue_free()
	await frames()
	check(equipment.perform("eq_shower", fixture), "Can restart before target deletion")
	equipment.tick(2)
	fixture.queue_free()
	equipment.tick(0.1)
	check(not equipment.is_active() and equipment.bathroom == null, "Deleting the fixture cancels safely and cleans up water")
	await frames()

	# Default bathroom layouts must expose the same actions as editor fixtures.
	var default_shower: FurnitureItem
	for node in office.furniture_container.get_children():
		if node is FurnitureItem and node.item_id in ["toilet", "shower", "bathroom_vanity"]:
			player.global_position = node.get_interact_world_pos()
			await frames()
			check(not equipment.get_actions(node).is_empty(), "Default " + node.item_id + " can be used from its front")
			if node.item_id == "shower": default_shower = node

	# Preserve the player's existing save while exercising mid-shower save/load.
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	player.global_position = default_shower.get_interact_world_pos()
	await frames()
	check(equipment.perform("eq_shower", default_shower), "Can shower in the default furnished bathroom")
	var entry := player.global_position
	equipment.tick(2)
	check(OfficeSave.save_game(office), "Can save during bathroom use")
	var saved := ConfigFile.new()
	saved.load(OfficeSave.SAVE_PATH)
	check((saved.get_value("player", "position") as Vector3).is_equal_approx(entry), "Mid-shower saves store the reachable entrance")
	check(OfficeSave.load_game(office) and not equipment.is_active() and equipment.bathroom == null and player.global_position.is_equal_approx(entry), "Loading exits the activity and restores the player outside the fixture")
	if had_save:
		var file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))

	print("Player actions regression: %d checks, %d failures" % [checks, failures.size()])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
