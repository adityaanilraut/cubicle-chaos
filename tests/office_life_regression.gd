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

func settle(frames := 3) -> void:
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
	var life: OfficeLife = office.life
	player.set_physics_process(false)
	var spawn := OfficeArrival.PLAYER_SPAWN
	check(player.global_position.distance_to(spawn) < 0.05 and player.global_basis.z.dot(Vector3.LEFT) > 0.99, "Player begins at the entrance, facing into the office")
	var nav_map := player.get_world_3d().navigation_map
	var route := NavigationServer3D.map_get_path(nav_map, spawn, Vector3(11, 0, 7), true)
	check(not route.is_empty() and route[-1].distance_to(Vector3(11, 0.2, 7)) < 0.5, "Entrance spawn has a usable route through staff security")
	check(office.workers_container.get_child(0).is_boss and office.workers_container.get_child(0).has_node("BossTitle"), "Executive has a visible boss identity")
	check(life.participants.size() == 3 and is_instance_valid(life.stage), "Meeting room opens with a presenter, two viewers and a live screen")
	var presenter: OfficeWorker = office.workers_container.get_child(6)
	var attendee: OfficeWorker = office.workers_container.get_child(7)
	check(attendee.is_seated and attendee.collision_shape.disabled and attendee.global_basis.z.dot(Vector3.FORWARD) > 0.99, "Audience sits facing the presentation without blocking chair navigation")
	check(presenter.assigned_chair == null and attendee.assigned_chair == null, "Meeting guests do not take coworkers' personal desks")
	check(life.table.is_in_use(), "Occupied meeting table is protected against moving and editing")
	await create_timer(2.0).timeout
	var routines := office.get_node("OfficeRoutines")
	check(not routines.social_sessions.is_empty(), "Coworkers start an actual conversation shortly after arrival")
	var saw_lobby_speech := false
	for i in [1, 2]: saw_lobby_speech = saw_lobby_speech or office.workers_container.get_child(i).social_speech.visible
	check(saw_lobby_speech, "Arriving player can see coworker speech bubbles")
	# Freeze the timeline to inspect the authored question, reply, and applause.
	life.set_physics_process(false)
	for worker in life.participants: worker.set_physics_process(false)
	life.elapsed = 5.1
	life._physics_process(0.01)
	for worker in life.participants: worker._physics_process(0.01)
	check(attendee.social_speech.text.contains("printer") and not presenter.social_speech.visible, "A viewer asks the presenter a question in their own turn")
	life.elapsed = 7.6
	life._physics_process(0.01)
	for worker in life.participants: worker._physics_process(0.01)
	check(presenter.social_speech.text.contains("Morgan") and not attendee.social_speech.visible and life.slide_index == 1, "Presenter replies and advances to the next real slide")
	var chart_before := life.bars[0].scale.y
	life._physics_process(0.4)
	check(not is_equal_approx(chart_before, life.bars[0].scale.y), "Presentation charts visibly animate")
	life.elapsed = 25.1
	life._physics_process(0.01)
	for worker in life.participants: worker._physics_process(0.01)
	await settle(15)
	check(String(attendee.state_playback.get_current_node()) == "applaud", "Viewers applaud at the end of the briefing")
	life.set_physics_process(true)
	for worker in life.participants: worker.set_physics_process(true)
	var before := life.elapsed
	office.game_menu.pause_game()
	await create_timer(0.1, true).timeout
	check(is_equal_approx(before, life.elapsed), "Pause freezes the meeting and slide timeline")
	office.game_menu.start_game()
	# Player conversations take priority, then the viewer resumes watching.
	player.global_position = attendee.global_position + Vector3(0, 0, 1.2)
	check(player.dialogue.open(attendee), "Seated audience remains available for normal player conversations")
	player.dialogue.close()
	await settle()
	check(attendee.meeting == life and attendee.is_seated, "Viewer resumes the meeting after talking")
	# Exercise completion, cancellation and saved counters for the new activities.
	var equipment := player.equipment
	for entry in [["eq_brainstorm", "whiteboard", "ideas_shared"], ["eq_check_in", "reception_desk", "check_ins"], ["eq_stretch", "lounge_chair", "stretch_breaks"]]:
		var item: FurnitureItem = office.place_furniture_item(entry[1], Vector3(30, 0, 30), 0.0, false)
		player.global_position = item.get_interact_world_pos()
		player.busy = 0.0
		await settle()
		check(equipment.perform(entry[0], item), "New activity can start: " + entry[0])
		equipment.cancel()
		check(int(equipment.stats[entry[2]]) == 0 and item.reserved_by == null, "Cancelling activity releases it without awarding progress")
		check(equipment.perform(entry[0], item), "Cancelled activity can restart")
		equipment.tick(equipment.duration + 0.1)
		check(int(equipment.stats[entry[2]]) == 1 and item.reserved_by == null, "Activity completes once and releases reservation")
		if entry[0] == "eq_brainstorm": check(item.has_node("SharedIdeas"), "Brainstorming leaves visible ideas on the board")
		item.queue_free()
		await settle()
	player.global_position = life.screen.global_position + Vector3(0, 0, 1.1)
	check(equipment.perform("eq_watch", life.screen), "Player can join the presentation as an activity")
	equipment.tick(equipment.duration + 0.1)
	check(int(equipment.stats.briefings_watched) == 1, "Watching a briefing records completion")
	var whiteboard: FurnitureItem
	for item in office.furniture_container.get_children():
		if item.item_id == "whiteboard":
			whiteboard = item
			break
	life.leave_ideas(whiteboard)
	player.global_position = spawn
	check(office.save_shift() and office.load_shift(), "Live meeting can be saved and reloaded")
	await settle()
	life = office.life
	check(not life.slide_title.text.is_empty() and not life.slide_body.text.is_empty(), "Restored screen renders its current slide immediately")
	var restored_ideas := false
	for item in office.furniture_container.get_children():
		if item.has_node("SharedIdeas"): restored_ideas = true
	check(restored_ideas, "Shared whiteboard ideas remain visible after loading")
	check(life.participants.size() == 3 and office.workers_container.get_child(0).is_boss, "Load restores the meeting cast and boss role")
	check(int(player.equipment.stats.ideas_shared) == 1 and int(player.equipment.stats.briefings_watched) == 1, "Load preserves completed new activities")
	if "--capture" in OS.get_cmdline_user_args():
		office.iso_camera.focus_on(Vector3(16.5, 0, -6.4))
		office.iso_camera.target_zoom = 8.5
		office.iso_camera.camera.size = 8.5
		await settle(20)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/office-live-meeting.png")
	# Violence and missing furniture must release, never pin or respawn, actors.
	attendee = office.workers_container.get_child(7)
	attendee.interrupt_for_combat()
	check(attendee.meeting == null and not attendee.is_seated and life.participants.size() == 2, "Combat releases a seated participant and their furniture claim")
	life.screen.take_damage(10000.0)
	await settle(10)
	check(life.participants.is_empty(), "Destroying the presentation screen safely ends the meeting")
	player.global_position = Vector3(-5, 0, 5)
	var seat: FurnitureItem = office.place_furniture_item("chair_desk", Vector3(30, 0, 30), 0, false)
	player.seated = true
	player.sitting_chair = seat
	seat.reserved_by = player
	player.busy = 5.0
	office.levels.set_level(2)
	check(not player.seated and player.sitting_chair == null and seat.reserved_by == null and player.busy == 0.0, "Starting a level releases old seats and unfinished interactions")
	check(player.global_position.distance_to(spawn) < 0.05, "Starting a new level spawns the player at the entrance")
	print("OFFICE LIFE CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	office.queue_free()
	await process_frame
	await create_timer(0.6).timeout
	quit(0 if failures.is_empty() else 1)
