extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer

func _initialize() -> void:
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

func has_action(id: String) -> bool:
	for action in player.get_context_actions():
		if action.id == id:
			return true
	return false

func capture_scene(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	office.iso_camera.target_zoom = 7.5
	office.iso_camera.focus_on(player.global_position + Vector3(0, 0, 0.5))
	await settle(15)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/office-interaction-" + name + ".png")

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	player = office.player
	player.set_physics_process(false)
	player.nav_agent.avoidance_enabled = false
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)
		worker.nav_agent.avoidance_enabled = false
		worker.global_position = Vector3(-11, 0, 8)
	player.global_position = Vector3(2, 0, 5)
	player.rotation.y = 0.0 # Face the fixture after spawning facing into the entrance.
	var coworker: OfficeWorker = office.workers_container.get_child(1)
	coworker.global_position = player.global_position + Vector3(0, 0, 0.9)
	await settle()
	player._update_nearby()
	check(player.nearby == coworker, "Nearby person becomes the shared action target")
	check(has_action("interact") and has_action("fight") and not has_action("punch") and not has_action("kick"), "Reachable person shows Talk and a single Fight circle")
	check(player.interaction_focus.target == coworker and player.interaction_focus.visible, "Current nearby person gets white focus")
	check(player.interaction_actions.action_ids.size() == 2, "Circular buttons mirror available actions")
	await capture_scene("person")
	coworker.social_session_id = 999
	player._update_nearby()
	check(not has_action("interact"), "Coworker in an autonomous conversation does not offer an unavailable Talk action")
	coworker.social_session_id = 0
	player._update_nearby()

	coworker.global_position.z = player.global_position.z + 1.45
	await settle()
	player._update_nearby()
	player.nearby = coworker # Evaluate this person independently of newly usable equipment nearby.
	check(has_action("fight"), "One Fight circle remains at kicking range")

	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 2.0, 0.15)
	collision.shape = shape
	wall.add_child(collision)
	office.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 1, 0.7)
	await settle()
	check(not player._can_reach_interaction(coworker), "Wall blocks nearby interactions")
	player._update_nearby()
	check(player.nearby != coworker, "Person across wall is not offered as an action target")
	wall.queue_free()
	coworker.global_position = Vector3(-11, 0, 8)
	await settle()

	var chair: FurnitureItem = office.place_furniture_item("chair_desk", player.global_position + Vector3(0, 0, 0.9), 0.0, false)
	await settle()
	player._update_nearby()
	check(player.nearby == chair and has_action("interact"), "Free nearby chair offers Sit")
	check(player.interaction_focus.target == chair, "Furniture focus follows the current interaction target")
	await capture_scene("chair")
	player.seated = true
	player.sitting_chair = chair
	check(chair.is_in_use(), "A player-occupied chair is protected from editor or furniture movement")
	player.seated = false
	player.sitting_chair = null
	chair.reserved_by = coworker
	player._update_nearby()
	check(not has_action("interact"), "Reserved chair never offers Sit")
	player.interact()
	check(not player.seated, "F cannot steal a reserved chair")
	chair.reserved_by = null
	chair.set_preview_mode(true)
	await settle()
	player._update_nearby()
	check(player.nearby != chair, "Furniture preview never receives interaction focus")
	chair.set_preview_mode(false)

	var cup := Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	player._update_nearby()
	check(has_action("drop") and not has_action("grab"), "Carrying a cup offers Put down and hides two-hand furniture actions")
	player.busy = 1.0
	player._update_nearby()
	check(player.get_context_actions().is_empty() and not player.interaction_actions.visible, "Animation in progress hides actions until finished")
	player.busy = 0.0
	player.carried_cup = null
	cup.queue_free()
	player._update_nearby()
	player.set_interaction_hints_enabled(false)
	check(not player.interaction_focus.visible and not player.interaction_actions.visible, "Settings hide both circular hints and white focus")
	player.set_interaction_hints_enabled(true)
	player._update_nearby()
	player.set_gameplay_visible(false)
	check(not player.hud_layer.visible and not player.interaction_focus.visible, "Menus hide player HUD and world focus together")
	player.set_gameplay_visible(true)
	player._update_nearby()

	# A stale circle cannot act on a target that moved away after it was drawn.
	var previous_busy := player.busy
	player.interaction_actions.buttons[0].button_down.emit()
	chair.global_position += Vector3(4, 0, 0)
	await settle()
	player._update_nearby()
	player.interaction_actions.buttons[0].pressed.emit()
	player.perform_context_action("interact", chair)
	check(not player.seated and is_equal_approx(previous_busy, player.busy), "Stale circle click rechecks target and reach")

	print("Interaction regression: %d checks, %d failures" % [checks, failures.size()])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
