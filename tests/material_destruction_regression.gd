extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D

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

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.player.set_physics_process(false)
	for worker in office.workers_container.get_children(): worker.set_physics_process(false)
	var plant: FurnitureItem = office.place_furniture_item("potted_plant", Vector3(30, 0, 30), 0.0, false)
	var table: FurnitureItem = office.place_furniture_item("side_table", Vector3(33, 0, 30), 0.0, false)
	var monitor: PhysicsProp = office.spawn_prop("monitor", Vector3(36, 0.05, 30))
	monitor.freeze = true
	await settle()
	check(plant.destructible.profile.material_id == "ceramic", "Plant uses ceramic material")
	check(table.destructible.profile.fracture_id == "table", "Side table uses table fracture profile")
	check(monitor.destructible.profile.fracture_id == "monitor" and is_instance_valid(monitor.destructible.screen), "Loose monitor has screen and electronic fracture profile")
	for body in [plant, table, monitor]:
		var state: DestructibleState = body.destructible
		check(state.damage_state == "intact" and not state.damage_visual.visible, "Object begins intact without cracks")
		body.take_damage(body.max_health * 0.4, Vector3.RIGHT)
		check(state.damage_state == "damaged" and state.damage_visual.visible, "Nonlethal damage reveals material damage")
		check(state.damage_visual.get_child_count() > 0, "Material damage uses actual crack geometry")
		var damaged_health: float = body.health
		body.health = body.max_health
		check(state.damage_state == "intact" and not state.damage_visual.visible, "Restoring health clears damage appearance")
		body.health = damaged_health
		check(state.damage_state == "damaged" and state.damage_visual.visible, "Loading damaged health restores cracks")
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var save_backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	check(OfficeSave.save_game(office) and OfficeSave.load_game(office), "Damaged shift saves and loads")
	for item in office.furniture_container.get_children():
		if item is FurnitureItem and item.global_position.x == 30: plant = item
		if item is FurnitureItem and item.global_position.x == 33: table = item
	for prop in office.props_container.get_children():
		if prop is PhysicsProp and prop.prop_id == "monitor" and prop.global_position.x == 36: monitor = prop
	for body in [plant, table, monitor]:
		check(body.destructible.damage_state == "damaged" and body.destructible.damage_visual.visible, "Save/load preserves material damage and cracks")
	if had_save:
		var backup_file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		backup_file.store_buffer(save_backup)
		backup_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))
	var material := monitor.destructible.screen.material_override as StandardMaterial3D
	monitor.destructible.flicker_time = 0
	monitor.destructible._process(0.01)
	var dim := material.emission_energy_multiplier
	monitor.destructible._process(0.1)
	check(material.emission_energy_multiplier > dim, "Damaged monitor screen flickers")
	var debris_before := get_nodes_in_group("destruction_debris").size()
	plant.take_damage(1000, Vector3.RIGHT)
	table.take_damage(1000, Vector3.RIGHT)
	monitor.take_damage(1000, Vector3.RIGHT)
	var count := get_nodes_in_group("destruction_debris").size()
	check(count - debris_before == 21, "Three examples produce bounded recognisable physical parts")
	var names := {}
	for chunk in get_nodes_in_group("destruction_debris"):
		names[chunk.part_name] = true
		check(chunk.collision_layer == 16 and chunk.collision_mask == 1, "Debris cannot collide with workers or other debris")
	check(names.has("PotShard") and names.has("PotBase") and names.has("PlantStem"), "Plant produces pot fragments, base and stem")
	check(names.has("TabletopLeft") and names.has("TableLeg") and names.has("DrawerPanel"), "Side table produces tabletop, legs and drawer panels")
	check(names.has("ScreenPanel") and names.has("MonitorStand") and names.has("CircuitBoard"), "Monitor produces screen, stand and circuitry")
	check(get_nodes_in_group("material_effects").size() >= 3, "Material destruction creates lightweight effects")
	await settle()
	check(not is_instance_valid(plant) and not is_instance_valid(table) and not is_instance_valid(monitor), "Broken source bodies are removed")
	var desk: FurnitureItem = office.place_furniture_item("desk_pc", Vector3(30, 0, 34), 0, false)
	check(desk.breakable and desk.take_damage(1000), "Workstations can be destroyed")
	desk.queue_free()
	var occupied: FurnitureItem = office.place_furniture_item("lounge_chair", Vector3(33, 0, 34), 0, false)
	occupied.reserved_by = office.player
	check(occupied.take_damage(1000) and occupied.is_queued_for_deletion(), "Reserved furniture can be destroyed")
	occupied.queue_free()
	var profile := DestructionProfile.for_item("plant")
	for i in range(20):
		Destruction.spawn_fracture(office.props_container, Transform3D(Basis.IDENTITY, Vector3(36, 1, 34)), Vector3(0.5, 0.8, 0.5), profile, Vector3.RIGHT)
	check(get_nodes_in_group("destruction_debris").size() <= Destruction.MAX_DEBRIS, "Repeated breaks respect the global physics debris limit")
	check(get_nodes_in_group("material_effects").size() <= Destruction.MAX_EFFECTS, "Repeated hits respect the visual effect limit")
	# Pause must suspend cleanup timers, then all objects must expire on resume.
	paused = true
	var first: DebrisChunk = get_nodes_in_group("destruction_debris")[0]
	var age := first.age
	await create_timer(0.1, true).timeout
	check(is_equal_approx(first.age, age), "Pause freezes debris lifetime")
	paused = false
	for chunk in get_nodes_in_group("destruction_debris"): chunk.age = chunk.lifetime - 0.02
	for effect in get_nodes_in_group("material_effects"): effect.age = effect.lifetime - 0.02
	await settle(8)
	check(get_nodes_in_group("destruction_debris").is_empty() and get_nodes_in_group("material_effects").is_empty(), "All debris and particle emitters clean up after their lifetime")
	print("MATERIAL DESTRUCTION CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await settle(4)
	# Give the audio server a moment to release stopped playback handles.
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
