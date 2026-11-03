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
	var scheduler := preload("res://scripts/office_routines.gd").new()
	root.add_child(scheduler)
	scheduler.set_physics_process(false)
	scheduler.max_outings = 1
	var a := Node.new()
	var b := Node.new()
	var c := Node.new()
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	check(scheduler.request_outing(a), "First worker receives the outing")
	check(not scheduler.request_outing(b) and not scheduler.request_outing(c), "Outing cap queues additional workers")
	scheduler.release(a)
	check(not scheduler.request_outing(c), "Later arrivals cannot skip the outing queue")
	check(scheduler.request_outing(b), "Next queued worker receives the outing")
	scheduler.max_outings = 2
	check(scheduler.request_outing(c) and scheduler.get_active_outing_count() == 2, "Two outings can coexist independently of stand-up lane")
	check(scheduler.request_stand(a) and not scheduler.request_stand(b) and not scheduler.request_stand(c), "Only one worker can stand up")
	scheduler.finish_stand(a)
	check(not scheduler.request_stand(c), "Stand-up spacing is enforced")
	scheduler._physics_process(1.3)
	check(not scheduler.request_stand(c), "A later stand requester cannot skip the oldest waiter")
	check(scheduler.request_stand(b), "Oldest stand requester receives the lane")
	scheduler.release(b)
	scheduler._physics_process(1.3)
	check(scheduler.request_stand(c), "Cancellation allows the next stand requester to proceed")
	scheduler.release(c)
	check(scheduler.waiting_workers.is_empty() and scheduler.stand_queue.is_empty() and scheduler.get_active_outing_count() == 0, "Cancellation clears both queues and outing ownership")
	a.free()
	b.free()
	c.free()
	scheduler.free()

	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.6).timeout
	office.player.set_physics_process(false)
	office.player.global_position = Vector3(3.0, 0, 8.0)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)
		worker.social_cooldown = 1000.0

	var worker: OfficeWorker = office.workers_container.get_child(0)
	var other: OfficeWorker = office.workers_container.get_child(1)
	worker.routines.max_outings = 2
	worker.target_chair = worker.assigned_chair
	other.target_chair = other.assigned_chair
	worker._enter_working()
	other._enter_working()
	worker.thirst = 1.0
	worker.fatigue = 0.0
	worker.task_pressure = 0.0
	worker.focus_strain = 0.0
	worker._start_break_from_work()
	other._start_break_from_work()
	check(worker.state == OfficeWorker.State.BREAK and worker.is_seated, "First worker begins a seated stand-up sequence")
	check(other.state == OfficeWorker.State.WORKING and other.is_seated, "Stand-queued worker remains seated and working")
	check(worker.routines.get_active_outing_count() == 2, "Independent destinations reserve separate concurrent outings")
	check(worker.break_type == OfficeWorker.BreakType.WATER_COOLER, "Most urgent need chooses a relevant destination")
	var spot := worker.target_furniture
	check(spot != null and spot.reserved_by == worker, "Destination is reserved before getting up")
	worker.interrupt_for_combat()
	check(spot.reserved_by == null and not worker.routines.outing_workers.has(worker), "Combat interruption releases destination and outing")
	other._enter_idle(100.0)
	worker._enter_idle(100.0)

	# Actual navigation and two independent outings, with serialized animation.
	var completed := 0
	var standing_overlap := false
	var unexplained_walk := false
	var waiting_stood := false
	var concurrent_outings_seen := false
	Engine.time_scale = 6.0
	for npc in office.workers_container.get_children():
		npc.set_physics_process(true)
		npc._enter_idle(0.1)
	for frame in range(1000):
		await physics_frame
		var standing := 0
		concurrent_outings_seen = concurrent_outings_seen or worker.routines.get_active_outing_count() > 1
		for npc in office.workers_container.get_children():
			if npc.state == OfficeWorker.State.BREAK and npc.break_phase != OfficeWorker.BreakPhase.PERFORM_ACTION:
				standing += 1
			if npc.state == OfficeWorker.State.WALKING and npc.walk_goal == OfficeWorker.WalkGoal.TO_BREAK and not is_instance_valid(npc.target_furniture) and npc.social_session_id == 0:
				unexplained_walk = true
			if npc.routines.is_waiting(npc) and npc.state == OfficeWorker.State.WORKING and not npc.is_seated:
				waiting_stood = true
		standing_overlap = standing_overlap or standing > 1
	for npc in office.workers_container.get_children():
		completed += npc.completed_tasks
	check(not standing_overlap, "Live routines never have overlapping desk stand-ups")
	check(not waiting_stood, "Waiting workers continue seated work")
	check(not unexplained_walk, "Every live break route has a real task destination")
	check(concurrent_outings_seen, "Live routines allow multiple simultaneous outings")
	check(completed >= 2, "Workers complete useful actions and continue their routines")
	Engine.time_scale = 1.0
	print("NPC ROUTINE CHECKS: ", checks - failures.size(), "/", checks, " passed; completed tasks: ", completed)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
