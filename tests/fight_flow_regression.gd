extends SceneTree

var checks := 0
var failures: Array[String] = []
var office: Node3D
var player: OfficePlayer
var opponent: OfficeWorker
var bystander: OfficeWorker
var origin := Vector3(0.5, 0, 4.0)

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func frames(count := 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func knock_down() -> void:
	opponent.combat.invulnerable = 0.0
	opponent.combat.balance = 1.0
	opponent.combat.receive_hit(player, "front_kick")
	opponent.combat.tick(OfficeCombat.FALL_TIME + 0.01)
	# A recent get-up may still own the shared stand-up spacing. Wait for the
	# real routine lane before expecting a second recovery to finish.
	for i in range(300):
		opponent.combat.tick(1.0 / 60.0)
		await physics_frame
		if not opponent.combat.is_down(): break

func feet() -> Array[Vector3]:
	var skeleton := player.combat.pose.get_skeleton()
	var local := player.combat.pose._last_pose
	var global: Array[Transform3D] = []
	for bone in range(local.size()):
		var parent := skeleton.get_bone_parent(bone)
		global.append(global[parent] * local[bone] if parent >= 0 else local[bone])
	return [global[skeleton.find_bone("office_LeftFoot")].origin, global[skeleton.find_bone("office_RightFoot")].origin]

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	player._update_combat_hint()
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	root.get_texture().get_image().save_png("res://build/previews/fight-" + label + ".png")

func run_checks() -> void:
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	Engine.time_scale = 1.0
	player = office.player
	player.set_physics_process(false)
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person._enter_idle(1000.0)
		person.nav_agent.avoidance_enabled = false
		person.global_position = Vector3(-11, 0, 8)
	opponent = office.workers_container.get_child(0)
	bystander = office.workers_container.get_child(1)
	player.global_position = origin
	player.rotation.y = 0.0
	opponent.global_position = origin + Vector3(0, 0, 1.0)
	await frames()
	check(player.try_attack("cross"), "First strike starts the duel")
	check(player.combat.target == opponent, "First strike acquires a persistent opponent lock")
	player.combat.tick(0.20)
	player.combat.tick(0.50)
	bystander.global_position = origin + Vector3(0.55, 0, 0.5)
	opponent.global_position = origin + Vector3(0, 0, 2.5)
	await frames()
	check(player.combat.find_target(1.65) == null, "Closer bystander cannot replace the out-of-reach locked opponent")
	player.try_attack("light")
	check(player.combat.strike_target == opponent, "Next strike stays on the same opponent even beyond reach")
	player.combat.tick(0.50)
	check(bystander.combat.health == 100.0, "Whiff does not damage the bystander")
	player.mouse_controls.aiming = true
	player.mouse_controls.aim_point = bystander.global_position
	player.rotation.y = PI * 0.5
	player.combat.face_locked_target(1.0)
	check(absf(player.rotation.y) < 0.01, "Locked facing takes priority over cursor aim")
	player.mouse_controls.aiming = false
	bystander.global_position = Vector3(-11, 0, 8)
	opponent.global_position = origin + Vector3(0, 0, 1.0)
	await frames()
	player.velocity = Vector3.RIGHT * 2.8
	await frames(20)
	var sideways := feet()
	check(sideways[0].y >= 0.08 and sideways[1].y >= 0.08, "Circling feet stay above the floor")
	check(sideways[0].x > 0.04 and sideways[1].x < -0.04, "Circling keeps the feet apart")
	player.velocity = Vector3.FORWARD * 2.8
	await frames(20)
	var backwards := feet()
	check(backwards[0].y >= 0.08 and backwards[1].y >= 0.08, "Backpedalling feet stay grounded without changing target facing")
	player.velocity = Vector3.ZERO

	# Hold a real strike pose for the visual preview and sample its motion ribbon.
	opponent.social_speech.say("")
	office.iso_camera.target_zoom = 5.2
	office.iso_camera.focus_on(origin + Vector3(0, 0.8, 0.5))
	office.iso_camera.target_pos.y = 0.8
	office.iso_camera.position = office.iso_camera.target_pos
	office.iso_camera.camera.size = 5.2
	player.combat.cooldown = 0.0
	player.try_attack("hook")
	for i in range(8):
		player.combat.phase_time = 0.10 + float(i) * 0.02
		await process_frame
	check(not player.combat.trail.points.is_empty(), "Strike ribbon follows the rendered hand")
	await capture("locked-hook")
	player.combat.reset()
	player.combat.target = opponent
	opponent.combat.reset()
	opponent.global_position = origin + Vector3(0, 0, 1.0)
	await frames()
	opponent.combat.balance = 1.0
	opponent.combat.receive_hit(player, "front_kick")
	check(opponent.combat.player_knockdowns == 1, "First player knockdown is counted")
	player._update_combat_hint()
	check(player.combat.target == opponent and player.combat_target_marker.visible, "Lock and ring remain on the fallen opponent")
	check("gets up fighting" in player.combat_hint.text, "Recovery warning explains the coming counterattack")
	opponent.combat.tick(OfficeCombat.FALL_TIME + 0.01)
	opponent.combat.tick(OfficeCombat.GET_UP_TIME + 0.01)
	check(opponent.combat.target == player and opponent.combat.revenge_pending, "First recovery remembers the aggressor and queues retaliation")
	check(not opponent.combat.receive_hit(player, "jab"), "Recovery protection prevents immediate interruption")
	# The large manual recovery step includes knockback, so restore reachable
	# positions before exercising the live counterattack.
	opponent.global_position = origin + Vector3(0, 0, 1.0)
	opponent.rotation.y = PI
	await frames()
	var before := player.combat.health
	for i in range(160):
		opponent.combat.tick(1.0 / 60.0)
		player.combat.tick(1.0 / 60.0)
		await physics_frame
		if player.combat.health < before: break
	check(player.combat.health < before, "Opponent actually lands a hit after the first get-up")
	check(not opponent.combat.revenge_pending, "Successful counterattack clears the pending revenge")
	await capture("counterattack")
	player.combat.reset()
	player.global_position = origin
	opponent.combat.phase = OfficeCombat.Phase.READY
	opponent.global_position = origin + Vector3(0, 0, 1.0)
	await knock_down()
	check(opponent.combat.player_knockdowns == 2 and opponent.combat.phase == OfficeCombat.Phase.FLEEING, "Second recovery starts escape instead of another fight")
	check(not opponent.combat.has_fighting_pose() and opponent.combat.target == null, "Escape releases guard and retaliation")
	check(not opponent.combat.receive_hit(player, "front_kick"), "A retreating coworker cannot be trapped in another knockdown")
	check(player.combat.find_target(OfficeCombat.KICK_REACH) == null, "Retreating coworker is excluded from target selection")
	check(player.anim_player.has_animation("office/flee"), "Panicked run clip is available")
	opponent.global_position = origin + Vector3(0, 0, 1.0)
	for i in range(15):
		opponent.combat.tick(1.0 / 60.0)
		await physics_frame
	await capture("leaving")
	bystander.combat.player_knockdowns = 1
	bystander.combat.target = player
	bystander.combat.anger_time = 20.0
	bystander.combat.revenge_pending = true
	var worker_count: int = office.workers_container.get_child_count()
	check(OfficeSave.save_game(office), "Fight outcomes save with the shift")
	player.combat.buffered_fight = 0.25
	check(OfficeSave.load_game(office), "Fight outcomes load with the shift")
	check(player.combat.phase == OfficeCombat.Phase.READY and player.combat.target == null and player.combat.buffered_fight == 0.0, "Loading clears stale player locks and buffered strikes")
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		if person.combat.player_knockdowns == 2: opponent = person
		if person.combat.player_knockdowns == 1: bystander = person
	check(opponent.combat.phase == OfficeCombat.Phase.FLEEING, "Load resumes second-knockdown departure")
	check(bystander.combat.target == player and bystander.combat.revenge_pending, "Load preserves first-knockdown retaliation")
	# Exercise the actual furnished office: the worker must pass security and
	# the entrance, disappear outside, and release their desk ownership.
	var chair := opponent.assigned_chair
	var crossed_security := false
	var crossed_entrance := false
	for i in range(2400):
		if not is_instance_valid(opponent): break
		opponent.combat.tick(1.0 / 60.0)
		crossed_security = crossed_security or opponent.global_position.x > 13.2
		crossed_entrance = crossed_entrance or opponent.global_position.x > 20.0
		await physics_frame
	check(crossed_security and crossed_entrance, "Escape navigates through security and the real office entrance")
	if is_instance_valid(opponent): print("ESCAPE STALLED AT ", opponent.global_position, " next ", opponent.nav_agent.get_next_path_position())
	check(not is_instance_valid(opponent), "Worker leaves the office after reaching the exterior landing")
	check(not is_instance_valid(chair) or not is_instance_valid(chair.owner_worker), "Departed worker releases workstation ownership")
	check(OfficeSave.save_game(office), "Shift saves after the departure")
	var config := ConfigFile.new()
	config.load(OfficeSave.SAVE_PATH)
	check(int(config.get_value("workers", "count", -1)) == worker_count - 1, "Departed worker is absent from the saved population")
	player.combat.reset()
	player.combat.target = bystander
	bystander.global_position = player.global_position + Vector3(0, 0, 8)
	player.combat.tick(0.01)
	check(player.combat.target == null, "Retreat beyond seven meters releases the lock")
	await frames(10)
	check(player.combat.trail.points.is_empty(), "Motion trails expire after a strike")
	if had_save:
		var file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))
	print("FIGHT FLOW CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	office.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
