extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var a: OfficeWorker
var b: OfficeWorker

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func prepare_pair() -> void:
	for npc in office.workers_container.get_children():
		npc.set_physics_process(false)
		npc._enter_idle(100.0)
		npc.social_cooldown = 1000.0
		# A consenting, seated participant remains at their own chair until their turn.
		if is_instance_valid(npc.assigned_chair):
			npc.target_chair = npc.assigned_chair
			npc.global_position = npc.target_chair.get_seat_world_pos()
			npc.rotation.y = npc.target_chair.global_rotation.y
			npc._enter_working()
	for npc in [a, b]:
		npc.social_need = 1.0
		npc.social_cooldown = 0.0
		npc.thirst = 0.0
		npc.fatigue = 0.0
		npc.task_pressure = 0.0
		npc.focus_strain = 0.0
		npc.state_timer = 0.0
	a.routines.stand_spacing = 0.0
	a.routines.max_outings = 2

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.player.set_physics_process(false)
	office.player.global_position = Vector3(3, 0, 8)
	# Social destinations require a published navigation map. The expanded
	# floor may still be baking after the scene's first few frames.
	for npc in office.workers_container.get_children():
		npc.set_physics_process(false)
	var map: RID = office.get_world_3d().navigation_map
	for i in range(400):
		if not office.nav_region.is_baking() and not office._nav_rebake_pending and NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await create_timer(0.05).timeout
	await physics_frame
	check(not office.nav_region.is_baking() and NavigationServer3D.map_get_iteration_id(map) > 0, "Navigation is ready before reserving a social destination")
	a = office.workers_container.get_child(0)
	b = office.workers_container.get_child(1)
	prepare_pair()
	a._start_break_from_work()
	check(a.social_session_id != 0 and a.social_session_id == b.social_session_id, "Autonomous social choice reserves two consenting participants")
	check(a.routines.social_sessions.size() == 1 and a.routines.get_active_outing_count() == 2, "One pair consumes two outing slots")
	check(not a.begin_player_conversation(office.player), "Player conversation cannot steal an autonomous participant")
	var meeting_a := a.target_walk_pos
	var meeting_b := b.target_walk_pos
	check(meeting_a.distance_to(meeting_b) > 1.0 and meeting_a.distance_to(meeting_b) < 1.6, "Meeting reserves separate fixed standing positions")
	var initial_a := a.completed_conversations
	var initial_b := b.completed_conversations
	var seen_talking := false
	var seen_speech := false
	var overlap := false
	var chased := false
	var finished := false
	Engine.time_scale = 5.0
	a.set_physics_process(true)
	b.set_physics_process(true)
	for frame in range(1000):
		await physics_frame
		var stands := 0
		for npc in [a, b]:
			if npc.state == OfficeWorker.State.BREAK and npc.break_phase != OfficeWorker.BreakPhase.PERFORM_ACTION:
				stands += 1
			seen_speech = seen_speech or npc.social_speech.visible
		overlap = overlap or stands > 1
		if a.social_session_id != 0:
			chased = chased or a.target_walk_pos.distance_to(meeting_a) > 0.01 or b.target_walk_pos.distance_to(meeting_b) > 0.01
			seen_talking = seen_talking or (a._social_arrived and b._social_arrived)
		if a.completed_conversations > initial_a and b.completed_conversations > initial_b and a.state == OfficeWorker.State.WORKING and b.state == OfficeWorker.State.WORKING:
			finished = true
			break
	check(seen_talking and seen_speech, "Both coworkers meet and exchange visible dialogue")
	check(not overlap, "Pair desk exits never overlap")
	check(not chased, "Social partners navigate to fixed positions without chasing")
	if not finished:
		print("SOCIAL DIAG ", a.completed_conversations, " / ", b.completed_conversations, " | ", a.get_state_name(), " at ", a.global_position, " chair retry ", a._chair_retry_timer, " | ", b.get_state_name(), " at ", b.global_position, " chair retry ", b._chair_retry_timer)
		print("SOCIAL PATH ", a.target_walk_pos, " path ", a.nav_agent.get_current_navigation_path(), " velocity ", a.velocity, " repaths ", a._repath_attempts, " | b path ", b.nav_agent.get_current_navigation_path())
	check(finished, "Both partners complete the conversation and return to their own desks")
	check(a.social_cooldown > 0.0 and b.social_cooldown > 0.0, "Completed conversations impose a social cooldown")
	Engine.time_scale = 1.0

	prepare_pair()
	a._start_break_from_work()
	check(a.social_session_id != 0, "A new consenting pair can be reserved")
	a.interrupt_for_combat()
	check(a.social_session_id == 0 and b.social_session_id == 0 and a.routines.social_sessions.is_empty(), "Combat interruption cancels the complete paired session")
	check(not a.social_speech.visible and not b.social_speech.visible and b.target_partner == null, "Interrupted conversations clear speech and partner reservations")

	prepare_pair()
	a._start_break_from_work()
	var blocked_position := a.target_walk_pos
	var blocker: FurnitureItem = office.place_furniture_item("desk_plain", blocked_position, 0, false)
	await physics_frame
	a.routines._meeting_check_timer = 0.0
	a.routines._physics_process(0.6)
	check(a.social_session_id == 0 and b.social_session_id == 0, "Furniture blocking a reserved meeting cancels both participants")
	blocker.queue_free()
	await physics_frame

	prepare_pair()
	# Hold a seated conversation without entering the shared stand queue.
	office.player.global_position = a.global_position + Vector3(0, 0, 1.2)
	a.routines.request_stand(b)
	a.routines.request_stand(a)
	check(a.begin_player_conversation(office.player), "Seated coworker accepts a player conversation")
	var held_position := a.global_position
	a._physics_process(0.2)
	check(a.is_seated and a.global_position.is_equal_approx(held_position), "Player conversation preserves the seated pose and position")
	check(not a.routines.stand_queue.has(a), "Held seated conversation does not block the stand queue")
	a.end_player_conversation(office.player)
	check(a.player_conversation_partner == null and a.state == OfficeWorker.State.WORKING, "Closing dialogue resumes seated work")
	# A standing coworker's route pauses, then resumes with a fresh path.
	a._enter_idle(100.0)
	a.global_position = Vector3(-1, 0, 5)
	a.walk_goal = OfficeWorker.WalkGoal.TO_STROLL
	a._enter_walking(Vector3(1, 0, 5))
	office.player.global_position = a.global_position + Vector3(0, 0, 1.2)
	check(a.begin_player_conversation(office.player), "Standing coworker accepts a player conversation")
	held_position = a.global_position
	a._physics_process(0.2)
	check(a.global_position.is_equal_approx(held_position) and a.velocity == Vector3.ZERO, "Player conversation stops navigation movement")
	a.end_player_conversation(office.player)
	check(a.state == OfficeWorker.State.WALKING and not a._path_initialized, "Closing dialogue preserves destination and refreshes its route")

	prepare_pair()
	var c: OfficeWorker = office.workers_container.get_child(2)
	var d: OfficeWorker = office.workers_container.get_child(3)
	# Simultaneous combat recovery must queue behind a desk stand, then use FIFO.
	a.social_need = 0.0
	a._start_break_from_work()
	for npc in [c, d]:
		npc.interrupt_for_combat()
		npc.combat.phase = OfficeCombat.Phase.FALLEN
		npc.combat.phase_time = OfficeCombat.FALL_TIME
		npc.combat.knockback = Vector3.ZERO
		npc.combat.tick(0.0)
	check(c.combat.phase == OfficeCombat.Phase.FALLEN and d.combat.phase == OfficeCombat.Phase.FALLEN, "Fallen coworkers wait while a desk stand owns the lane")
	a._enter_idle(100.0)
	a.routines._physics_process(1.3)
	d.combat.tick(0.0)
	check(d.combat.phase == OfficeCombat.Phase.FALLEN, "Later combat recovery cannot skip the stand queue")
	c.combat.tick(0.0)
	check(c.combat.phase == OfficeCombat.Phase.GETTING_UP and d.combat.phase == OfficeCombat.Phase.FALLEN, "Only the oldest fallen coworker starts getting up")
	c.combat.tick(OfficeCombat.GET_UP_TIME)
	a.routines._physics_process(1.3)
	d.combat.tick(0.0)
	check(d.combat.phase == OfficeCombat.Phase.GETTING_UP and c.combat.phase == OfficeCombat.Phase.READY, "Recovery completion releases the next coworker after spacing")
	d.combat.tick(OfficeCombat.GET_UP_TIME)

	print("SOCIAL CHECKS: ", checks - failures.size(), "/", checks, " passed")
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
