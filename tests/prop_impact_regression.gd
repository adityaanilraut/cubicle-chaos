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

func launch(id: String, offset := Vector3.ZERO, speed := 6.0) -> PhysicsProp:
	var prop: PhysicsProp = office.spawn_prop(id, ARENA + offset + Vector3(0, 0.5, -1.0))
	prop.gravity_scale = 0
	prop.angular_velocity = Vector3.ZERO
	prop.linear_velocity = Vector3(0, 0, speed)
	prop.impact.reset(prop.linear_velocity)
	prop.impact.thrower = weakref(player)
	return prop

func clean_props() -> void:
	for prop in office.props_container.get_children():
		if prop is PhysicsProp: prop.queue_free()

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	player = office.player
	player.set_physics_process(false)
	player.global_position = ARENA + Vector3(0, 0, -4)
	for worker in office.workers_container.get_children(): worker.set_physics_process(false)
	clean_props()
	await settle()
	var light: PhysicsProp = office.spawn_prop("book", ARENA)
	var heavy: PhysicsProp = office.spawn_prop("speaker", ARENA + Vector3(3, 0, 0))
	light.freeze = true
	heavy.freeze = true
	check(heavy.impact.damage_for(6) > light.impact.damage_for(6), "Equal-speed heavy objects cause more damage")
	check(light.impact.damage_for(8) > light.impact.damage_for(4), "Faster contact causes more damage")
	check(light.impact.damage_for(1.9) == 0, "Settling contacts below threshold cause no damage")
	check(light.impact.damage_for(6, 2) < light.impact.damage_for(6, 0.75), "Material resistance reduces impact damage")
	check(heavy.impact.damage_for(100) <= 95, "Extreme impacts have a damage cap")
	check(heavy.impact.damage_for(6, 1, light.mass) < heavy.impact.damage_for(6), "Two dynamic props use reduced mass")
	clean_props()
	await settle()

	var plant: FurnitureItem = office.place_furniture_item("potted_plant", ARENA + Vector3(0, 0, 1), 0, false)
	var original := plant.health
	light = launch("book")
	await settle(27)
	check(is_instance_valid(plant) and plant.health < original, "Actual rigid-body collision damages furniture")
	check(is_instance_valid(light) and light.health < light.max_health and light.impact.impact_count >= 1, "Projectile records incoming contact and takes its own damage")
	if is_instance_valid(light):
		var count := light.impact.impact_count
		await settle(5)
		check(light.impact.impact_count == count, "A contact manifold does not apply duplicate damage")
	plant.queue_free()
	clean_props()
	await settle()
	plant = office.place_furniture_item("potted_plant", ARENA + Vector3(0, 0, 1), 0, false)
	heavy = launch("speaker")
	await settle(27)
	check(not is_instance_valid(plant) or plant.is_queued_for_deletion(), "A heavy impact can shatter ceramic furniture")
	clean_props()
	await settle()

	var worker: OfficeWorker = office.spawn_worker(ARENA + Vector3(0, 0, 1))
	worker.set_physics_process(false)
	worker._enter_idle(100)
	light = launch("book", Vector3.ZERO, 6)
	await settle(27)
	check(worker.combat.health < 100 and worker.combat.balance < 100, "Actual thrown contact reduces worker health and balance")
	check(worker.combat.phase == OfficeCombat.Phase.STAGGER, "Moderate thrown contact staggers a worker")
	check(worker.combat.target == player, "Worker knows who threw the prop")
	var health := worker.combat.health
	check(not worker.combat.receive_prop_hit(20, 20, Vector3.FORWARD, player) and worker.combat.health == health, "Hit protection prevents repeated damage during stagger")
	worker.queue_free()
	clean_props()
	await settle()
	worker = office.spawn_worker(ARENA + Vector3(0, 0, 1))
	worker.set_physics_process(false)
	worker._enter_idle(100)
	heavy = launch("speaker", Vector3.ZERO, 8)
	await settle(22)
	check(worker.combat.is_down(), "A heavy fast prop knocks a worker down")
	check(not worker.combat.receive_prop_hit(50, 100, Vector3.FORWARD, player), "Fallen workers are protected from repeated prop hits")
	worker.queue_free()
	clean_props()
	await settle()

	light = launch("book", Vector3.ZERO, 6)
	var oncoming: PhysicsProp = office.spawn_prop("box", ARENA + Vector3(0, 0.5, 1))
	var original_oncoming_health := oncoming.health
	var single_speed_damage := light.impact.damage_for(6, oncoming.destructible.profile.resistance, oncoming.mass)
	oncoming.gravity_scale = 0
	oncoming.linear_velocity = Vector3(0, 0, -6)
	oncoming.impact.reset(oncoming.linear_velocity)
	await settle(18)
	check(not is_instance_valid(oncoming) or original_oncoming_health - oncoming.health > single_speed_damage * 2.5, "Actual head-on props use their combined closing speed")
	check(not is_instance_valid(light) or light.health < light.max_health, "A head-on collision also damages the source prop")
	clean_props()
	await settle()

	# Equal velocity is not an impact; head-on travel is. Test the actual contact
	# queue as well as the analytic scaling above.
	light = office.spawn_prop("book", ARENA)
	light.freeze = true
	var target: PhysicsProp = office.spawn_prop("box", ARENA + Vector3(2, 0, 0))
	target.freeze = true
	check(not light.impact.queue_contact(target, 0, Vector3.RIGHT, ARENA), "No contact damage when relative closing speed is zero")
	check(light.impact.queue_contact(target, 5, Vector3.RIGHT, ARENA), "Eligible contact queues once")
	check(not light.impact.queue_contact(target, 5, Vector3.RIGHT, ARENA), "Same pair cannot queue twice")
	check(not target.impact.queue_contact(light, 5, Vector3.LEFT, ARENA), "Opposite body's contact cannot double-apply the pair")
	var target_health := target.health
	await settle()
	check(target.health < target_health, "Queued prop-to-prop impact applies damage")
	light.impact.cooldowns.clear()
	light.pick_up(player)
	check(not light.impact.queue_contact(target, 7, Vector3.RIGHT, ARENA), "Held bodies cannot deal collision damage")
	light.drop_gently(ARENA, player)
	check(not light.impact.queue_contact(target, 7, Vector3.RIGHT, ARENA), "Gentle placement has a short settling grace")
	light.impact.reset(Vector3.ZERO)
	check(not light.impact.queue_contact(player, 7, Vector3.RIGHT, ARENA), "Release grace prevents an immediate self-hit")
	target.queue_free()
	await settle()
	# Freed weak targets and repeated breaks must be harmless.
	var doomed: PhysicsProp = office.spawn_prop("box", ARENA + Vector3(2, 0, 0))
	doomed.freeze = true
	light.impact.queue_contact(doomed, 5, Vector3.RIGHT, ARENA)
	doomed.free()
	await settle()
	check(is_instance_valid(light), "Deferred impacts tolerate targets deleted before resolution")
	var before := get_nodes_in_group("destruction_debris").size()
	var expected := mini(Destruction._fracture_parts(light.footprint_size, light.debris_profile).size(), Destruction.MAX_DEBRIS - before)
	light.break_apart(Vector3.RIGHT)
	var after_first := get_nodes_in_group("destruction_debris").size()
	check(after_first - before == expected, "Destruction produces one bounded family recipe")
	light.break_apart(Vector3.RIGHT)
	check(get_nodes_in_group("destruction_debris").size() == after_first, "Repeated destruction does not duplicate fragments")
	await settle()
	for material in ["ceramic", "wood", "electronic", "metal", "fabric"]:
		check(office.audio._streams.has(material + "_hit") and office.audio._streams.has(material + "_break"), "Synthesized feedback exists for " + material)
	print("PROP IMPACT CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await settle(4)
	# Give the audio server a moment to release stopped playback handles.
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
