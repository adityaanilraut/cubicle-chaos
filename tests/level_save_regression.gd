extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var had_save := FileAccess.file_exists(OfficeSave.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(OfficeSave.SAVE_PATH) if had_save else PackedByteArray()
	var office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	for audio in get_nodes_in_group("office_audio"): audio.enabled = false
	office.game_menu.pause_on_focus_loss = false
	office.levels.set_level(2)
	office.levels.unlocked = 2
	office.levels.done[0] = true
	office.levels.done[1] = true
	office.levels.has_coffee = true
	check(OfficeSave.save_game(office), "Level two saves")
	office.levels.set_level(1)
	check(OfficeSave.load_game(office), "Level two loads from another level")
	check(office.levels.level == 2 and office.levels.unlocked == 2, "Level and unlock restore")
	check(office.levels.done == [true, true, false] and office.levels.has_coffee, "Checklist and carried delivery restore")
	check(office.levels.server.visible and not office.levels.delivery_spot.visible, "Level markers match restored level")
	office.levels.set_level(1)
	office.levels.done[0] = true
	check(OfficeSave.save_game(office), "Level one saves")
	office.levels.set_level(2)
	check(OfficeSave.load_game(office), "Level one loads from another level")
	check(office.levels.level == 1 and office.levels.done == [true, false, false], "Level one progress restores")
	check(is_instance_valid(office.levels.task_prop), "Level one delivery box is reconnected")
	var legacy := ConfigFile.new()
	legacy.load(OfficeSave.SAVE_PATH)
	legacy.erase_section("level")
	legacy.save(OfficeSave.SAVE_PATH)
	office.levels.set_level(2)
	check(OfficeSave.load_game(office) and office.levels.level == 2, "Older saves retain the current level")
	for level_number in range(3, 6):
		office.levels.set_level(level_number)
		var keys: Array = LevelObjectives.STAT_KEYS[level_number - 1]
		for key in keys:
			office.player.equipment.stats[key] += 1
		office.levels._process(0.0)
		check(office.levels.done == [true, true, true], "Office activities complete level %d" % level_number)
		check(office.levels.unlocked >= mini(level_number + 1, 5), "Completion unlocks the next level")
	office.levels.set_level(3)
	var baseline: int = office.player.equipment.stats.reports_written
	check(OfficeSave.save_game(office), "New level saves")
	office.player.equipment.stats.reports_written += 1
	check(OfficeSave.load_game(office), "New level loads")
	check(office.levels.level == 3 and int(office.levels.stat_baseline.reports_written) == baseline, "Activity baseline restores")
	office.player.equipment.stats.reports_written += 1
	office.levels._process(0.0)
	check(office.levels.done[0], "Activity after loading completes its task")
	office.levels.set_level(1)
	var old_box: PhysicsProp = office.levels.task_prop
	old_box.break_apart()
	office.levels._process(0.0)
	check(is_instance_valid(office.levels.task_prop) and office.levels.task_prop != old_box, "Destroyed objective box is replaced")
	check(OfficeSave.save_game(office), "Shift saves before invalid-load check")
	var invalid := ConfigFile.new()
	invalid.load(OfficeSave.SAVE_PATH)
	invalid.set_value("furniture_0", "position", "not a position")
	invalid.save(OfficeSave.SAVE_PATH)
	var furniture_count: int = office.furniture_container.get_child_count()
	var first_item = office.furniture_container.get_child(0)
	check(not OfficeSave.load_game(office), "Malformed shift is rejected")
	check(office.furniture_container.get_child_count() == furniture_count and is_instance_valid(first_item), "Rejected shift leaves the office intact")
	if had_save:
		var file := FileAccess.open(OfficeSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OfficeSave.SAVE_PATH))
	print("LEVEL SAVE: %d failure(s)" % failures.size())
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
