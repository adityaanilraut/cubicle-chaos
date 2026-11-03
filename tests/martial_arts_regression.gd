extends SceneTree

var checks := 0
var failures: Array[String] = []
var office: Node3D
var player: OfficePlayer
var opponent: OfficeWorker
var origin := Vector3(0.5, 0, 4.0)
var contact_poses := {}

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

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func reset_fighters(distance := 0.95) -> void:
	for effect in get_nodes_in_group("combat_impacts"): effect.queue_free()
	for actor in [player, opponent]:
		actor.set_physics_process(false)
		actor.combat.phase = OfficeCombat.Phase.READY
		actor.combat.phase_time = 0.0
		actor.combat.cooldown = 0.0
		actor.combat.invulnerable = 0.0
		actor.combat.health = 100.0
		actor.combat.balance = 100.0
		actor.combat.target = null
		actor.combat.strike_target = null
		actor.combat.combo_step = 0
		actor.combat.combo_window = 0.0
		actor.combat.buffered_fight = 0.0
		actor.combat.stance_time = 0.0
		actor.combat.knockback = Vector3.ZERO
		actor._enter_idle(100.0)
	player.busy = 0.0
	player.global_position = origin
	player.rotation.y = 0.0
	opponent.global_position = origin + Vector3(0, 0, distance)
	opponent.rotation.y = PI

func joint_positions() -> Dictionary:
	var skeleton := player.combat.pose.get_skeleton()
	var local: Array[Transform3D] = player.combat.pose._last_pose
	var global: Array[Transform3D] = []
	var result := {}
	for bone in range(local.size()):
		var parent := skeleton.get_bone_parent(bone)
		var transform := global[parent] * local[bone] if parent >= 0 else local[bone]
		global.append(transform)
		result[String(skeleton.get_bone_name(bone)).trim_prefix("office_")] = transform.origin
	return result

func capture(id: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	player._update_nearby()
	office.iso_camera.target_pos.y = 0.85
	opponent._update_label()
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/office-martial-" + id + ".png")

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	Engine.time_scale = 1.0
	player = office.player
	for actor in office.workers_container.get_children():
		actor.set_physics_process(false)
		actor.nav_agent.avoidance_enabled = false
		actor._enter_idle(1000.0)
		actor.global_position = Vector3(-11, 0, 8)
	opponent = office.workers_container.get_child(1)
	player.nav_agent.avoidance_enabled = false
	office.iso_camera.target_zoom = 5.2
	office.iso_camera.focus_on(origin + Vector3(0, 0, 0.5))
	office.iso_camera.target_pos.y = 0.85
	reset_fighters()
	await frames(20)

	# Real input: K starts a heavy kick, while J starts a light strike.
	key(KEY_K, true)
	await frames()
	key(KEY_K, false)
	check(player.combat.kind == "kick" and player.combat.move_id == "front_kick", "K starts a heavy kick")
	reset_fighters()
	key(KEY_J, true)
	await frames()
	key(KEY_J, false)
	check(player.combat.move_id == "jab" and player.combat.combo_step == 1, "J begins the light chain with a lead jab")
	player.combat.tick(0.7)
	await frames()
	check(player.combat.phase == OfficeCombat.Phase.READY and player.combat.combo_step == 1, "Releasing J finishes one move without auto-attacking")

	reset_fighters()
	player.set_physics_process(true)
	key(KEY_J, true)
	await create_timer(1.4).timeout
	key(KEY_J, false)
	check(player.combat.combo_step >= 2, "Holding J repeats and advances the strike sequence")
	player.set_physics_process(false)
	player.combat.tick(1.2)
	var chain_after_release := player.combat.combo_step
	player.combat.tick(0.5)
	check(player.combat.phase == OfficeCombat.Phase.READY and player.combat.combo_step == chain_after_release, "Releasing a held key stops additional strikes")

	# A single buffered input, interruption, and combo expiry.
	reset_fighters()
	player.try_attack()
	check(not player.try_attack("auto", true), "Early mashing does not queue extra attacks")
	player.combat.tick(0.30)
	check(player.try_attack("auto", true), "A late J tap can buffer the next move")
	player.combat.tick(0.17)
	check(player.combat.move_id == "cross" and player.combat.combo_step == 2, "Buffered tap chains at the end of recovery")
	player.combat.tick(0.50)
	player.try_attack("auto", true)
	player.combat.receive_hit(opponent, "jab")
	check(player.combat.buffered_fight == 0.0 and player.combat.combo_step == 0, "Taking a hit clears queued input and the chain")
	reset_fighters()
	player.try_attack()
	player.combat.tick(0.3)
	player.try_attack("auto", true)
	player.set_gameplay_visible(false)
	check(player.combat.buffered_fight == 0.0, "Hiding gameplay for a menu clears buffered strikes")
	player.set_gameplay_visible(true)
	player.combat.tick(3.0)
	player.try_attack()
	check(player.combat.move_id == "jab" and player.combat.combo_step == 1, "A break resets the sequence")

	# Entering a different context during cooldown cancels a queued strike.
	reset_fighters(3.0)
	player.try_attack()
	player.combat.tick(0.41)
	player.try_attack("auto", true)
	check(player.combat.buffered_fight > 0.0, "A cooldown tap is queued before changing activity")
	opponent.global_position = origin + Vector3(0, 0, 0.95)
	check(player.dialogue.open(opponent), "Dialogue can begin after the strike animation ends")
	player._physics_process(0.06)
	check(player.dialogue.is_open and player.combat.phase == OfficeCombat.Phase.READY and player.combat.buffered_fight == 0.0, "Starting dialogue cancels a queued strike without interrupting the conversation")
	player.dialogue.close()

	reset_fighters(1.52)
	await frames()
	player.try_attack()
	check(player.combat.kind == "kick", "One button selects a kick outside punching range")
	player.combat.tick(float(player.combat.current_move().contact) + 0.01)
	check(player.combat.last_attack_hit, "Automatic long-range kick can land")

	# Exercise the complete automatic sequence in free space.
	reset_fighters()
	opponent.global_position = Vector3(-11, 0, 8)
	var seen: Array[String] = []
	for index in range(CombatMoves.SEQUENCE.size()):
		check(player.try_attack(), "Automatic move %d starts" % index)
		seen.append(player.combat.move_id)
		player.combat.tick(float(player.combat.current_move().cooldown) + 0.01)
	check(seen == CombatMoves.SEQUENCE, "One button reaches all five punches and five kicks")
	check(player.combat.has_fighting_pose(), "A martial arts stance remains between attacks")
	player.combat.tick(3.0)
	check(not player.combat.has_fighting_pose(), "Fighting pose relaxes after the fight")

	# Every variant must preserve windup, one-time contact, dodging and real poses.
	for id in CombatMoves.SEQUENCE:
		reset_fighters()
		await frames()
		check(player.try_attack(id), id + ": can begin")
		var move := player.combat.current_move()
		await frames(14)
		player.combat.tick(float(move.contact) - 0.01)
		check(opponent.combat.health == 100.0, id + ": no damage during windup")
		player.combat.tick(0.02)
		check(player.combat.last_attack_hit and opponent.combat.health < 100.0, id + ": makes contact")
		var health := opponent.combat.health
		player.combat.tick(0.03)
		check(opponent.combat.health == health, id + ": only damages once")
		await frames()
		check(not player.combat.pose._last_pose.is_empty(), id + ": produces a skeleton pose")
		contact_poses[id] = joint_positions()
		await capture(id)
		reset_fighters()
		player.try_attack(id)
		opponent.global_position += Vector3(0, 0, 3)
		player.combat.tick(float(move.contact) + 0.01)
		check(not player.combat.last_attack_hit, id + ": moving away dodges contact")

	check(contact_poses.jab.LeftHand.distance_to(contact_poses.cross.LeftHand) > 0.15, "Jab and reverse punch use different striking hands")
	check(contact_poses.uppercut.RightHand.y > contact_poses.cross.RightHand.y + 0.10, "Uppercut rises above the reverse punch path")
	check(contact_poses.front_kick.RightFoot.y > contact_poses.sweep.LeftFoot.y + 0.35, "Sweep stays visibly lower than a front kick")
	check(contact_poses.side_kick.LeftFoot.y > contact_poses.side_kick.RightFoot.y + 0.30, "Side kick lifts the left leg and keeps a supporting foot")
	check(contact_poses.roundhouse.RightFoot.y > 0.65, "Roundhouse reaches a high striking pose")

	reset_fighters()
	player.try_attack("palm")
	player.combat.tick(0.65)
	check(player.combat.stance_style == "Kung fu", "Tiger palm flows into kung fu guard")
	await frames(10)
	var kung_fu_pose := joint_positions()
	await capture("kung-fu-guard")
	reset_fighters()
	player.try_attack("cross")
	player.combat.tick(0.7)
	check(player.combat.stance_style == "Karate", "Reverse punch flows into karate stance")
	await frames(10)
	var karate_pose := joint_positions()
	check(kung_fu_pose.LeftHand.distance_to(karate_pose.LeftHand) > 0.10, "Kung fu and karate guards have distinct visible poses")
	await capture("karate-guard")
	player.seated = true
	check(not player.combat.has_fighting_pose(), "Lingering stance does not override seated interactions")
	player.seated = false

	print("MARTIAL ARTS CHECKS: ", checks - failures.size(), "/", checks, " passed")
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
