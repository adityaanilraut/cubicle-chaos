extends SceneTree

var checks := 0
var failures: Array[String] = []
var office: Node3D

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

func clear_props() -> void:
	for child in office.props_container.get_children(): child.free()

func _run() -> void:
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.player.set_physics_process(false)
	for worker in office.workers_container.get_children(): worker.set_physics_process(false)
	clear_props()
	var prop: PhysicsProp = office.spawn_prop("monitor", Vector3(0, 2, 5))
	prop.global_rotation = Vector3(0.1, 0.7, 0.2)
	prop.linear_velocity = Vector3(1, 2, 3)
	prop.angular_velocity = Vector3(0.5, 1.5, -0.5)
	prop.health = prop.max_health * 0.6
	prop.impact.thrower = weakref(office.player)
	check(OfficeSave.save_game(office), "In-flight shift saves")
	Destruction.spawn_debris(office.props_container, Vector3(0, 2, 5), Vector3.ONE, Color.WHITE, 4)
	check(OfficeSave.load_game(office), "In-flight shift loads")
	prop = office.props_container.get_child(0)
	check(prop.linear_velocity.is_equal_approx(Vector3(1, 2, 3)), "Load restores in-flight velocity")
	check(prop.angular_velocity.is_equal_approx(Vector3(0.5, 1.5, -0.5)), "Load restores prop spin")
	check(prop.global_rotation.is_equal_approx(Vector3(0.1, 0.7, 0.2)), "Load restores full prop rotation")
	check(prop.destructible.damage_state == "damaged" and prop.destructible.damage_visual.visible, "Load restores damaged electronic visuals")
	check(prop.impact.previous_velocity.is_equal_approx(prop.linear_velocity), "Load initializes incoming collision velocity")
	check(prop.impact.thrower.get_ref() == office.player, "Load retains the player's thrown-prop attribution")
	check(get_nodes_in_group("destruction_debris").is_empty(), "Load removes transient debris")
	clear_props()
	prop = office.spawn_prop("book", Vector3(0, 1, 5))
	prop.pick_up(office.player)
	office.player.held_prop = prop
	office.player.prop_handling.begin_charge()
	check(OfficeSave.save_game(office) and OfficeSave.load_game(office), "A shift can save and load while carrying and aiming")
	prop = office.props_container.get_child(0)
	check(office.player.held_prop == null and not office.player.prop_handling.charging, "Load clears carry and charge ownership")
	check(not prop.freeze and not prop.is_held() and prop.linear_velocity.is_zero_approx(), "Previously carried prop restores as a released object")
	check(prop.impact.quiet_time > 0 and office.player in prop.get_collision_exceptions(), "Loaded carried prop has safe settling and owner grace")
	clear_props()
	check(OfficeSave.save_game(office) and OfficeSave.load_game(office), "Empty prop state saves and loads")
	check(office.props_container.get_child_count() == 0, "Destroyed props do not respawn when loading a zero-prop save")
	if had_save:
		var file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))
	print("PROP SAVE CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
