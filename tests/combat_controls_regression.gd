extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for i in range(5):
		await physics_frame
		await process_frame

func run_checks() -> void:
	var office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker.global_position = Vector3(-11, 0, 8)
	var front: OfficeWorker = office.workers_container.get_child(0)
	var rear: OfficeWorker = office.workers_container.get_child(1)
	var origin := Vector3(35, 0, 35)
	player.global_position = origin
	player.rotation.y = 0
	front.global_position = origin + Vector3(0, 0, 1.1)
	rear.global_position = origin + Vector3(0, 0, -0.8)
	await settle()
	check(player.combat.find_target(1.65) == front, "Facing selects the person in front, not the closer person behind")
	player.mouse_controls.aiming = true
	player.mouse_controls.aim_point = rear.global_position
	check(player.combat.find_target(1.65) == rear, "Mouse aim selects a different visible person")
	player.mouse_controls.aiming = false
	player._update_combat_hint()
	check(player.combat_target_marker.visible and player.combat_hint.visible, "Target marker and combat information are visible")
	front.combat.phase = OfficeCombat.Phase.ATTACK
	front.combat.move_id = "front_kick"
	front.combat.phase_time = 0.1
	player._update_combat_hint()
	check("INCOMING FRONT KICK" in player.combat_hint.text, "Incoming attack windup is announced")
	front.combat.phase = OfficeCombat.Phase.READY
	OfficeInput.apply_bindings({"fight": KEY_U, "heavy_attack": KEY_I})
	player._update_combat_hint()
	check("U  Light" in player.combat_hint.text and "I  Heavy" in player.combat_hint.text, "Combat display uses remapped keys")
	OfficeInput.apply_bindings({"interact": KEY_K})
	check(OfficeInput.key_for("heavy_attack") != KEY_K and OfficeInput.key_for("interact") == KEY_K, "Existing saved K binding does not collide with the new heavy attack")
	OfficeInput.reset_bindings()
	check(player.try_attack("light"), "Light attack starts")
	check(player.combat.kind == "punch", "Light attack uses a hand strike")
	check(player.combat.strike_target == front, "The attack locks the displayed forward target")
	player.combat.tick(0.30)
	check(player.try_attack("heavy", true), "Heavy attack can be buffered during light attack recovery")
	player.combat.tick(0.17)
	check(player.combat.kind == "kick", "Buffered heavy input starts a kick")
	player.combat.phase = OfficeCombat.Phase.READY
	player.combat.cooldown = 0
	front.global_position = origin + Vector3(0, 0, 5)
	rear.global_position = origin + Vector3(0, 0, -5)
	var prop1: PhysicsProp = office.spawn_prop("book", origin + Vector3(0, 0.6, 0.8))
	var prop2: PhysicsProp = office.spawn_prop("book", origin + Vector3(0.5, 0.6, 0.9))
	prop1.freeze = true
	prop2.freeze = true
	await settle()
	var health1 := prop1.health
	var health2 := prop2.health
	player.combat.move_id = "cross"
	player.combat._hit_environment()
	check(prop1.health < health1 and prop2.health == health2, "A swing hits only the nearest visible prop")
	prop1.queue_free()
	prop2.queue_free()
	await settle()
	var prop3: PhysicsProp = office.spawn_prop("book", origin + Vector3(0, 0.6, 1.0))
	prop3.freeze = true
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.1)
	shape.shape = box
	wall.add_child(shape)
	office.add_child(wall)
	wall.global_position = origin + Vector3(0, 1, 0.5)
	await settle()
	var blocked_health := prop3.health
	player.combat._hit_environment()
	check(prop3.health == blocked_health, "A wall blocks damage to a prop behind it")
	prop3.queue_free()
	var plant: FurnitureItem = office.place_furniture_item("potted_plant", origin + Vector3(0, 0, 1.0), 0, false)
	await settle()
	var plant_health := plant.health
	player.combat._hit_environment()
	check(plant.health == plant_health, "A wall blocks damage to furniture behind it")
	wall.queue_free()
	await settle()
	player.combat._hit_environment()
	check(plant.health < plant_health, "Visible furniture can be hit")
	office.queue_free()
	await settle()
	print("COMBAT CONTROLS CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
