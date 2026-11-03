extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
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
	office.game_menu.start_game()
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)
	await settle()

	# 1. Rigid-body props exist, are physics bodies, and can be picked up/thrown.
	check(office.props_container.get_child_count() >= 6, "Office spawns rigid-body props")
	var prop: PhysicsProp = office.props_container.get_child(0)
	check(prop is RigidBody3D and not prop.freeze, "Prop is a live RigidBody3D")
	# Isolate pickup from the furnished layout: the old test reached through a desk.
	prop.global_position = Vector3(30, 0.05, 30)
	prop.linear_velocity = Vector3.ZERO
	player.global_position = Vector3(30.6, 0, 30)
	player._update_nearby()
	check(player.try_pickup_prop() and player.held_prop == prop and prop.is_held(), "T picks up a nearby prop")
	# Let the animated pickup complete; normal play advances this in physics.
	for i in range(24):
		player.prop_handling.tick(1.0 / 60.0)
		await settle(1)
	player.throw_prop()
	await settle(8)
	check(player.held_prop == null and not prop.is_held() and (prop.linear_velocity.length() > 0.1 or prop.global_position.distance_to(player.global_position) > 0.8), "T throws the prop with physics velocity")
	check(prop.collision_layer == 8 and prop.collision_mask == (1 | 4 | 8), "Thrown prop restores its collision layers")

	# 2. Destruction: breakable furniture loses health and bursts into debris.
	var plant: FurnitureItem = office.place_furniture_item("potted_plant", Vector3(30, 0, 30), 0.0, false)
	await settle()
	check(plant.breakable and plant.health > 0.0, "Plant is breakable with health")
	var furniture_parent := plant.get_parent()
	plant.take_damage(plant.max_health + 10.0, Vector3.FORWARD)
	await settle()
	check(not is_instance_valid(plant) or plant.is_queued_for_deletion(), "Lethal damage destroys furniture")
	var debris_found := false
	for child in furniture_parent.get_children():
		if child is DebrisChunk:
			debris_found = true
	check(debris_found, "Destruction spawns rigid debris chunks")

	var desk: FurnitureItem = office.place_furniture_item("desk_pc", Vector3(34, 0, 30), 0.0, false)
	await settle()
	check(desk.breakable and desk.take_damage(1000), "Workstations break into their family debris")
	desk.queue_free()
	await settle()

	# 3. Audio is synthesized, present, and has the core sound set.
	check(is_instance_valid(office.audio), "Office has an audio system")
	check(office.audio._streams.has("punch") and office.audio._streams.has("break") and office.audio._streams.has("ding"), "Core sounds are synthesized without files")

	# 4. Human variety differs per worker and the rig stays unscaled.
	var hair_colors := {}
	for worker in office.workers_container.get_children():
		var variety := WorkerVariety.variety_for(worker.worker_index)
		hair_colors[variety["hair_color"]] = true
		check(worker.rig_root.transform.is_equal_approx(Transform3D.IDENTITY), "Variety never tilts or scales the character rig")
	check(hair_colors.size() >= 3, "Workers get distinct hair colors")
	check(WorkerVariety.variety_for(0)["hair_style"] != WorkerVariety.variety_for(2)["hair_style"] or WorkerVariety.variety_for(0)["has_glasses"] != WorkerVariety.variety_for(2)["has_glasses"], "Workers vary in style or accessories")

	# 5. Each familiar coworker has several short automatic lines and replies.
	for person_name in OfficeDialogue.PROFILES:
		var lines: Array = OfficeDialogue.PROFILES[person_name]
		var replies: Array = OfficeDialogue.REPLIES[person_name]
		check(lines.size() >= 6 and lines.size() == replies.size(), person_name + " has varied lines with matched replies")
		for line in lines + replies:
			check(String(line).length() <= 40 and String(line).contains(" "), "Speech fits a short bubble: " + String(line))

	# 6. Save and reload preserve the quest stage and furniture count.
	player.quest = 3
	var furniture_before := 0
	for child in office.furniture_container.get_children():
		if child is FurnitureItem:
			furniture_before += 1
	check(office.save_shift(), "Shift saves")
	player.quest = 0
	check(office.load_shift(), "Shift loads")
	check(player.quest == 3, "Load restores the quest stage")
	var furniture_after := 0
	for child in office.furniture_container.get_children():
		if child is FurnitureItem:
			furniture_after += 1
	check(furniture_after == furniture_before, "Load restores furniture")

	print("NEW SYSTEMS CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await settle(4)
	# Give the audio server a moment to release stopped playback handles.
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
