extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer
var worker: OfficeWorker
var origin := Vector3(0.5, 0, 4.0)
var capture := false

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func settle(frames := 3) -> void:
	for i in range(frames):
		await physics_frame
		await process_frame

func reset_fighters(distance := 0.95) -> void:
	for actor in [player, worker]:
		actor.set_physics_process(false)
		actor.combat.phase = OfficeCombat.Phase.READY
		actor.combat.phase_time = 0.0
		actor.combat.cooldown = 0.0
		actor.combat.invulnerable = 0.0
		actor.combat.health = 100.0
		actor.combat.balance = 100.0
		actor.combat.target = null
		actor.combat.strike_target = null
		actor.combat.knockback = Vector3.ZERO
		actor._enter_idle(100.0)
	player.busy = 0.0
	player.seated = false
	player.global_position = origin
	player.rotation.y = 0.0
	worker.global_position = origin + Vector3(0, 0, distance)
	worker.rotation.y = PI

func snapshot(file: String) -> void:
	if not capture:
		return
	player._update_nearby()
	worker._update_label()
	player.status_label.text = "YOU • " + player.combat.status().to_upper()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/office-combat-" + file + ".png")

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	player = office.player
	worker = office.workers_container.get_child(1)
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person._enter_idle(100.0)
		person.nav_agent.avoidance_enabled = false
	player.nav_agent.avoidance_enabled = false
	reset_fighters()
	office.iso_camera.target_zoom = 7.0
	office.iso_camera.focus_on(origin + Vector3(0, 0, 0.5))
	await settle(10)

	check(player.try_attack("punch"), "J action can start a punch")
	check(worker.combat.health == 100.0, "Punch has a windup, not instant damage")
	player.combat.tick(0.17)
	check(worker.combat.health == 100.0, "No damage before the punch contact frame")
	player.combat.tick(0.03)
	check(worker.combat.health == 82.0 and player.combat.last_attack_hit, "Punch lands at contact frame")
	check(worker.combat.target == player, "Hit coworker targets the attacker for retaliation")
	check(worker.combat.phase == OfficeCombat.Phase.STAGGER, "Punch causes a stagger")
	check(not player.try_attack("kick"), "Attack cannot bypass the current strike/cooldown")
	check(get_nodes_in_group("combat_impacts").size() == 1, "Punch generates a contact object")
	await settle()
	await snapshot("punch")
	player.combat.tick(0.1)
	check(worker.combat.health == 82.0, "A strike damages only once")
	await create_timer(0.5).timeout
	check(get_nodes_in_group("combat_impacts").is_empty(), "Contact objects clean themselves up")

	reset_fighters(1.45)
	await settle()
	player.try_attack("punch")
	player.combat.tick(0.2)
	check(worker.combat.health == 100.0, "Punch misses outside its shorter reach")
	reset_fighters(1.45)
	await settle()
	player.try_attack("kick")
	player.combat.tick(0.33)
	check(worker.combat.health == 70.0, "Kick reaches farther and deals more damage")
	var effect := get_nodes_in_group("combat_impacts").back() as CombatImpact
	check(effect.kind == "kick" and effect.name == "KickContact", "Kick generates its distinct blue contact object")
	await settle()
	await snapshot("kick")

	reset_fighters()
	await settle()
	player.try_attack("punch")
	worker.global_position += Vector3(0, 0, 2.0)
	player.combat.tick(0.2)
	check(worker.combat.health == 100.0, "Walking out of reach during windup dodges the punch")
	reset_fighters()
	await settle()
	player.try_attack("punch")
	worker.global_position = origin - Vector3(0, 0, 0.95)
	player.combat.tick(0.2)
	check(worker.combat.health == 100.0, "A strike cannot hit someone who moved behind the attacker")

	# At close range the target's body can overlap the strike arc even if its
	# center moves outside it during the windup.
	for attack in ["punch", "kick"]:
		reset_fighters(0.55)
		await settle()
		check(player.try_attack(attack), "Close-range %s starts" % attack)
		worker.global_position = origin + Vector3(0.45, 0, 0.10)
		await settle()
		player.combat.tick(0.33 if attack == "kick" else 0.2)
		check(worker.combat.health < 100.0, "Close-range %s hits the body at the edge of the arc" % attack)

	reset_fighters(0.55)
	worker.global_position = origin + Vector3(0.45, 0, 0.10)
	await settle()
	check(player.combat.find_target(1.2, true) == worker, "Close-range targeting uses the same body-aware strike arc")
	for attack in ["punch", "kick"]:
		reset_fighters(2.0)
		await settle()
		player.try_attack(attack)
		player.combat.tick(0.32 if attack == "kick" else 0.19)
		check(worker.combat.health == 100.0, "A %s can miss initially during its active pose" % attack)
		worker.global_position = origin + Vector3(0, 0, 0.9)
		await settle()
		player.combat.tick(0.02)
		check(worker.combat.health < 100.0, "A %s hits a target entering during its active pose" % attack)
		var remaining_health := worker.combat.health
		player.combat.tick(0.02)
		check(worker.combat.health == remaining_health, "The active %s cannot hit twice" % attack)

	reset_fighters(2.0)
	await settle()
	player.try_attack("punch")
	worker.global_position = origin + Vector3(0, 0, 0.95)
	await settle()
	player.combat.tick(0.2)
	check(worker.combat.health == 82.0, "A person entering reach during windup can be struck")

	reset_fighters()
	await settle()
	var impacts_before := get_nodes_in_group("combat_impacts").size()
	check(worker.combat.receive_prop_hit(10.0, 10.0, Vector3.FORWARD, player), "A prop can hit a standing worker")
	check(get_nodes_in_group("combat_impacts").size() == impacts_before + 1, "A successful prop hit shows contact feedback")
	check(not worker.combat.receive_prop_hit(10.0, 10.0, Vector3.FORWARD, player), "Protection prevents repeated prop damage")
	check(get_nodes_in_group("combat_impacts").size() == impacts_before + 1, "A protected prop hit does not show a false impact")

	reset_fighters()
	await settle()
	player.try_attack("punch")
	player.combat.tick(0.45)
	check(player.combat.request_fight("kick"), "A late attack input is buffered")
	player.combat.tick(0.4)
	check(player.combat.phase == OfficeCombat.Phase.ATTACK and player.combat.move_id == "front_kick", "A buffered attack survives a long recovery frame")

	reset_fighters()
	await settle()
	player.try_attack("punch")
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 0.10)
	collider.shape = box
	wall.add_child(collider)
	office.add_child(wall)
	wall.global_position = origin + Vector3(0, 1.0, 0.45)
	await settle()
	player.combat.tick(0.2)
	check(worker.combat.health == 100.0, "An obstruction at contact time blocks damage")
	check(player.combat.find_target(1.65) == null, "Cannot select an opponent through a wall")
	wall.queue_free()
	await settle()

	reset_fighters()
	await settle()
	player.try_attack("punch")
	worker.queue_free()
	await settle()
	player.combat.tick(0.2)
	check(not player.combat.last_attack_hit, "Removing a target during windup safely cancels contact")
	worker = office.workers_container.get_child(0)

	reset_fighters(1.4)
	await settle()
	for i in range(2):
		player.try_attack("kick")
		player.combat.tick(0.33)
		if i == 0:
			worker.combat.tick(0.4)
			player.combat.tick(0.75)
			worker.global_position = origin + Vector3(0, 0, 1.4)
	check(worker.combat.is_down(), "Repeated kicks knock an NPC down")
	check(not worker.combat.start_attack("punch"), "A fallen character cannot attack")
	var health_before := worker.combat.health
	check(not worker.combat.receive_hit(player, "kick") and worker.combat.health == health_before, "Fallen characters cannot be repeatedly damaged")
	worker.combat.tick(0.4)
	await settle()
	await snapshot("fall")
	worker.combat.tick(OfficeCombat.FALL_TIME)
	check(worker.combat.phase == OfficeCombat.Phase.GETTING_UP, "NPC automatically starts getting up")
	worker.combat.tick(OfficeCombat.GET_UP_TIME + 0.01)
	check(not worker.combat.is_down() and worker.combat.balance == 100.0, "Recovery restores NPC balance and control")
	check(not worker.combat.receive_hit(player, "punch"), "Recovery grants brief protection")

	# Exercise live retaliation, including navigating into reach and timed attacks.
	reset_fighters()
	await settle()
	player.try_attack("punch")
	player.combat.tick(0.2)
	player.global_position = origin - Vector3(0, 0, 1.0)
	worker.set_physics_process(true)
	player.set_physics_process(true)
	var retaliated := false
	for frame in range(300):
		await physics_frame
		if player.combat.health < 100.0:
			retaliated = true
			break
	check(retaliated, "NPC pursues the attacker and lands a counterattack")
	player.set_physics_process(false)
	worker.set_physics_process(false)
	worker.combat.target = player
	player.global_position = worker.global_position + Vector3(0, 0, 9)
	worker.combat.phase = OfficeCombat.Phase.READY
	worker.combat.tick(0.1)
	check(worker.combat.target == null, "Retreating far enough ends NPC pursuit")

	reset_fighters()
	await settle()
	player.combat.receive_hit(worker, "kick")
	player.combat.tick(0.4)
	player.combat.receive_hit(worker, "kick")
	check(player.combat.is_down(), "Player can also be knocked down")
	check(not player.try_attack("punch") and not player.try_grab_furniture(), "Knockdown blocks player actions")
	player.combat.tick(OfficeCombat.FALL_TIME)
	player.combat.tick(OfficeCombat.GET_UP_TIME + 0.01)
	check(not player.combat.is_busy() and player.combat.invulnerable > 0, "Player gets up with protection and regains control")
	player.combat.tick(5.0)
	check(player.combat.health > 60.0, "Health recovers after combat quiets down")

	reset_fighters()
	var cup := Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	check(not player.try_attack("punch"), "Must free hands before attacking")
	player.cup_in_hand = true
	player.busy = 1.0
	player.combat.receive_hit(worker, "punch")
	check(player.carried_cup == null and cup.is_in_group("player_interactable"), "An incoming hit drops the held cup safely")
	check(player.busy == 0.0 and not player.cup_in_hand, "An incoming hit interrupts the interaction")
	cup.queue_free()

	reset_fighters()
	cup = Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	player._pick_up_cup(cup)
	player.combat.receive_hit(worker, "punch")
	await create_timer(1.4).timeout
	check(not player.cup_in_hand and cup.is_in_group("player_interactable"), "Cancelled pickup cannot reattach the cup after a hit")
	cup.queue_free()

	reset_fighters()
	cup = Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	player.cup_in_hand = true
	player._drop_cup()
	await create_timer(1.1).timeout
	player.combat.receive_hit(worker, "punch")
	await create_timer(0.5).timeout
	check(cup.is_in_group("player_interactable") and is_zero_approx(cup.global_position.y), "Hit during cup lowering leaves it on the floor and collectible")
	cup.queue_free()

	reset_fighters()
	var chair: FurnitureItem = worker.assigned_chair
	worker.target_chair = chair
	worker._enter_working()
	worker.combat.receive_hit(player, "punch")
	check(not worker.is_seated and worker.state == OfficeWorker.State.IDLE, "Hitting a seated NPC interrupts work before retaliation")
	await settle()
	check(not worker.collision_shape.disabled, "Interrupted sitting restores the NPC collider")

	print("COMBAT CHECKS: ", checks - failures.size(), "/", checks, " passed")
	check(get_nodes_in_group("combat_impacts").is_empty(), "No contact objects remain at the end of the test")
	root.remove_child(office)
	office.queue_free()
	await settle(4)
	# Give the audio server a moment to release stopped playback handles.
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
