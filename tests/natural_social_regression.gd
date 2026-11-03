extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	# Do not force workers' needs, timers, locations, or states: this verifies
	# the first-day office actually produces conversations by itself.
	seed(261102)
	var routines := office.get_node("OfficeRoutines")
	routines.max_outings = 2
	routines.stand_gap_seconds = 1.25
	office.player.set_physics_process(false)
	office.player.global_position = Vector3(3, 0, 8)
	var completed := 0
	var saw_speech := false
	var simultaneous_stands := false
	var exceeded_capacity := false
	var captured := false
	Engine.time_scale = 8.0
	for frame in range(3600):
		await physics_frame
		var standing := 0
		completed = 0
		for worker in office.workers_container.get_children():
			completed += worker.completed_conversations
			saw_speech = saw_speech or worker.social_speech.visible
			if worker.combat.phase == OfficeCombat.Phase.GETTING_UP or (worker.state == OfficeWorker.State.BREAK and worker.break_phase != OfficeWorker.BreakPhase.PERFORM_ACTION):
				standing += 1
		simultaneous_stands = simultaneous_stands or standing > 1
		exceeded_capacity = exceeded_capacity or routines.get_active_outing_count() > 2
		if not captured and "--capture" in OS.get_cmdline_user_args() and saw_speech:
			for session in routines.social_sessions.values():
				if not session["talking"]:
					continue
				var center: Vector3 = (session["pos_a"] + session["pos_b"]) * 0.5
				office.iso_camera.focus_on(center)
				office.iso_camera.position = office.iso_camera.target_pos
				office.iso_camera.target_zoom = 8.0
				office.iso_camera.camera.size = 8.0
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/office-natural-conversation.png")
				captured = true
				break
		if completed >= 2:
			break
	Engine.time_scale = 1.0
	var passed := completed >= 2 and saw_speech and not simultaneous_stands and not exceeded_capacity
	if not passed:
		for worker in office.workers_container.get_children():
			print("NATURAL SOCIAL DIAG ", worker.worker_name, ": ", worker.get_state_name(), " social ", worker.social_need, " session ", worker.social_session_id, " cooldown ", worker.social_cooldown, " at ", worker.global_position)
		push_error("Natural shift must produce a completed visible coworker conversation within capacity and without overlapping stands")
	print("NATURAL SOCIAL CHECKS: ", int(completed >= 2) + int(saw_speech) + int(not simultaneous_stands) + int(not exceeded_capacity), "/4 passed; completed participants: ", completed)
	office.queue_free()
	await process_frame
	quit(0 if passed else 1)
