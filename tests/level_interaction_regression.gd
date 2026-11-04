extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
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
	for item in office.furniture_container.get_children():
		item.free()
	for prop in office.props_container.get_children():
		prop.free()
	var station: FurnitureItem = office.place_furniture_item("coffee_station", Vector3(0, 0, 5), 0.0, false)
	player.global_position = station.global_position + station.get_forward_dir() * (station.footprint_size.z * 0.5 + 0.5)
	for i in range(3):
		await physics_frame
		await process_frame
	player._update_nearby()
	office.levels._process(0.0)
	var actions := player.get_context_actions()
	check(player.nearby == station, "Coffee station is the interaction target")
	check(actions.size() == 1 and actions[0].id == "level_drink", "Level coffee uses one circular action")
	check(not office.levels.action_button.visible, "Separate level button is hidden at the coffee station")
	check(player.interaction_actions.action_ids.size() == 1, "Only one interaction circle is shown")
	player.interaction_actions.buttons[0].button_down.emit()
	player.interaction_actions.buttons[0].pressed.emit()
	check(office.levels.done[0], "Clicking the circle completes the coffee objective")
	player.busy = 0.0
	player._update_nearby()
	check(not player.get_context_actions().is_empty() and player.get_context_actions()[0].id == "eq_coffee", "Normal brewing remains available after the objective")
	office.levels.set_level(2)
	player.global_position = station.get_interact_world_pos() # Walk back from the new entrance spawn.
	player._update_nearby()
	check(player.get_context_actions().size() == 1 and player.get_context_actions()[0].id == "level_coffee", "Level two uses the same single circle")
	var event := InputEventKey.new()
	event.keycode = OfficeInput.key_for("interact")
	event.pressed = true
	player._unhandled_input(event)
	check(office.levels.done[1] and office.levels.has_coffee, "The interaction key completes the same objective")
	print("LEVEL INTERACTION CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
