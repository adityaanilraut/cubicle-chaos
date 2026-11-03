extends Node

# Outing capacity and the animation lane are deliberately independent:
# coworkers may use different rooms while every desk exit/recovery takes turns.
var max_outings := 2
var stand_gap_seconds := 1.25
var outing_workers: Array[Node] = []
var standing_worker: Node
var waiting_workers: Array[Node] = []
var stand_queue: Array[Node] = []
var stand_spacing := 0.0
var social_sessions: Dictionary = {}
var _next_session_id := 1
var _meeting_check_timer := 0.0

# Compatibility for callers that previously inspected the sole outing owner.
var outing_worker: Node:
	get:
		return outing_workers.front() if not outing_workers.is_empty() else null

func _physics_process(delta: float) -> void:
	stand_spacing = maxf(0.0, stand_spacing - delta)
	_prune_queue()
	_meeting_check_timer -= delta
	for id in social_sessions.keys():
		var session: Dictionary = social_sessions[id]
		var a: OfficeWorker = session["a"]
		var b: OfficeWorker = session["b"]
		if not is_instance_valid(a) or not is_instance_valid(b) or a.is_queued_for_deletion() or b.is_queued_for_deletion():
			finish_social(id, false)
			continue
		if a.combat.is_engaged() or b.combat.is_engaged() or is_instance_valid(a.player_conversation_partner) or is_instance_valid(b.player_conversation_partner):
			finish_social(id, false)
			continue
		session["elapsed"] += delta
		if session["elapsed"] > 45.0:
			finish_social(id, false)
			continue
		if _meeting_check_timer <= 0.0 and not _meeting_clear(a, b, session["pos_a"], session["pos_b"]):
			finish_social(id, false)
			continue
		if not session["arrived_a"] or not session["arrived_b"]:
			continue
		if not session["talking"]:
			session["talking"] = true
			a._begin_social_talk()
			b._begin_social_talk()
		session["talk_time"] += delta
		_update_social_speech(session)
		if session["talk_time"] >= 7.5:
			finish_social(id, true)
	if _meeting_check_timer <= 0.0:
		_meeting_check_timer = 0.5

func _prune_queue() -> void:
	for list in [waiting_workers, stand_queue, outing_workers]:
		for i in range(list.size() - 1, -1, -1):
			if not is_instance_valid(list[i]) or list[i].is_queued_for_deletion():
				list.remove_at(i)
	if not is_instance_valid(standing_worker) or standing_worker.is_queued_for_deletion():
		standing_worker = null

func get_active_outing_count() -> int:
	_prune_queue()
	return outing_workers.size()

func request_outing(worker: Node) -> bool:
	_prune_queue()
	if outing_workers.has(worker):
		return true
	if not waiting_workers.has(worker):
		waiting_workers.append(worker)
	if outing_workers.size() >= maxi(1, max_outings) or waiting_workers.front() != worker:
		return false
	outing_workers.append(worker)
	waiting_workers.pop_front()
	return true

func request_stand(worker: Node) -> bool:
	_prune_queue()
	if standing_worker == worker:
		return true
	if not stand_queue.has(worker):
		stand_queue.append(worker)
	if standing_worker != null or stand_spacing > 0.0 or stand_queue.front() != worker:
		return false
	stand_queue.pop_front()
	standing_worker = worker
	return true

func finish_stand(worker: Node) -> void:
	stand_queue.erase(worker)
	if standing_worker == worker:
		standing_worker = null
		stand_spacing = maxf(0.0, stand_gap_seconds)

func release_outing(worker: Node) -> void:
	waiting_workers.erase(worker)
	outing_workers.erase(worker)

func release(worker: Node) -> void:
	release_outing(worker)
	finish_stand(worker)

func is_waiting(worker: Node) -> bool:
	return waiting_workers.has(worker) or stand_queue.has(worker)

func try_start_social(initiator: OfficeWorker) -> bool:
	_prune_queue()
	if not outing_workers.has(initiator) or initiator.social_session_id != 0 or initiator.social_cooldown > 0.0:
		return false
	var candidates: Array[OfficeWorker] = []
	# A coworker already returning from a break can reuse their outing slot.
	# Without this, a busy office can keep both slots occupied indefinitely and
	# never have room to invite a seated partner into a conversation.
	for node in outing_workers:
		if node is OfficeWorker and node.office_ref == initiator.office_ref and node.is_willing_to_socialize(initiator):
			candidates.append(node)
	if outing_workers.size() < maxi(1, max_outings) and not waiting_workers.is_empty():
		# Inviting the oldest waiting coworker preserves outing queue order.
		var first := waiting_workers.front() as OfficeWorker
		if first != null and first.is_willing_to_socialize(initiator):
			candidates.append(first)
	elif outing_workers.size() < maxi(1, max_outings):
		for node in get_tree().get_nodes_in_group("workers"):
			if node is OfficeWorker and node.office_ref == initiator.office_ref and node.is_willing_to_socialize(initiator):
				candidates.append(node)
	candidates.sort_custom(func(a: OfficeWorker, b: OfficeWorker):
		return a.global_position.distance_squared_to(initiator.global_position) < b.global_position.distance_squared_to(initiator.global_position)
	)
	for partner in candidates:
		var positions := _find_meeting_positions(initiator, partner)
		if positions.is_empty():
			continue
		var id := _next_session_id
		_next_session_id += 1
		if not outing_workers.has(partner):
			outing_workers.append(partner)
		waiting_workers.erase(partner)
		social_sessions[id] = {
			"a": initiator, "b": partner, "pos_a": positions[0], "pos_b": positions[1],
			"elapsed": 0.0, "talking": false, "talk_time": 0.0,
			"arrived_a": false, "arrived_b": false, "line": -1
		}
		initiator._prepare_social_session(partner, positions[0], id)
		partner._prepare_social_session(initiator, positions[1], id)
		return true
	return false

func mark_social_arrived(worker: OfficeWorker) -> void:
	if not social_sessions.has(worker.social_session_id):
		return
	var session: Dictionary = social_sessions[worker.social_session_id]
	session["arrived_a" if session["a"] == worker else "arrived_b"] = true

func finish_social(id: int, completed: bool, interrupted_worker: OfficeWorker = null) -> void:
	if not social_sessions.has(id):
		return
	var session: Dictionary = social_sessions[id]
	# Remove first: worker cleanup can call back into cancellation safely.
	social_sessions.erase(id)
	for member in [session["a"], session["b"]]:
		if is_instance_valid(member) and not member.is_queued_for_deletion():
			member._finish_social_session(completed, member == interrupted_worker)

func _update_social_speech(session: Dictionary) -> void:
	var index := mini(2, int(float(session["talk_time"]) / 2.5))
	if session["line"] == index:
		return
	session["line"] = index
	var a: OfficeWorker = session["a"]
	var b: OfficeWorker = session["b"]
	var topics := [
		["☕ Coffee meeting?", "📅 My calendar says yes!", "☕ Best meeting today!"],
		["🖨️ The printer jammed.", "🥪 Did it want lunch?", "😂 I'll offer a snack!"],
		["🌱 My plant looks tired.", "☕ Give it a coffee?", "😅 Maybe just water!"],
		["📋 I made a list.", "📝 Is 'nap' on it?", "✅ Top priority!"],
		["💻 My screen froze!", "🧣 Get it a sweater!", "😂 Tech support solved!"],
		["🍪 Who took my cookie?", "😇 Define 'took'...", "🔎 Crumbs are evidence!"],
		["📚 Got a good book?", "📖 The printer manual!", "😴 A real page-turner!"],
		["🎨 I drew our boss.", "🖼️ Is that a potato?", "🤫 It's modern art!"],
		["📅 Another meeting?", "🏃 Race you to lunch!", "🥇 Winner picks snacks!"],
		["🤖 Will robots take over?", "☕ Only the coffee machine.", "😱 We're doomed!"],
		["🌧️ Rain later?", "☂️ I brought a plant.", "🌱 Very thoughtful!"],
		["💾 Did you save it?", "😬 Define 'save'...", "🔌 Don't touch anything!"]
	]
	var lines: Array = topics[(a.worker_index * 3 + b.worker_index * 5 + a.completed_conversations) % topics.size()]
	a.show_social_speech(lines[index] if index != 1 else "")
	b.show_social_speech(lines[index] if index == 1 else "")
	a.play_anim("talk" if index != 1 else "idle_breath")
	b.play_anim("talk2" if index == 1 else "idle_breath")

func _find_meeting_positions(a: OfficeWorker, b: OfficeWorker) -> Array[Vector3]:
	var nav_map := a.nav_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return []
	var start_a := a.target_chair.get_chair_approach_pos() if a.is_seated and is_instance_valid(a.target_chair) else a.global_position
	var start_b := b.target_chair.get_chair_approach_pos() if b.is_seated and is_instance_valid(b.target_chair) else b.global_position
	var midpoint := (start_a + start_b) * 0.5
	var centers: Array[Vector3] = [midpoint, midpoint + Vector3(0, 0, 1.5), midpoint + Vector3(1.5, 0, 0), midpoint + Vector3(-1.5, 0, 0), Vector3(-1, 0, 4), Vector3(1, 0, 5), Vector3(-3, 0, 3)]
	for center in centers:
		for axis in [Vector3.RIGHT, Vector3.FORWARD]:
			var pa: Vector3 = center - axis * 0.68
			var pb: Vector3 = center + axis * 0.68
			var projected_a := NavigationServer3D.map_get_closest_point(nav_map, pa)
			var projected_b := NavigationServer3D.map_get_closest_point(nav_map, pb)
			if Vector2(projected_a.x - pa.x, projected_a.z - pa.z).length() > 0.25 or Vector2(projected_b.x - pb.x, projected_b.z - pb.z).length() > 0.25:
				continue
			pa = Vector3(projected_a.x, 0, projected_a.z)
			pb = Vector3(projected_b.x, 0, projected_b.z)
			if not _meeting_clear(a, b, pa, pb):
				continue
			var busy := false
			for session in social_sessions.values():
				if center.distance_to(session["pos_a"]) < 2.5:
					busy = true
			if busy:
				continue
			var path_a := NavigationServer3D.map_get_path(nav_map, start_a, projected_a, true)
			var path_b := NavigationServer3D.map_get_path(nav_map, start_b, projected_b, true)
			if path_a.is_empty() or path_b.is_empty() or path_a[-1].distance_to(projected_a) > 0.4 or path_b[-1].distance_to(projected_b) > 0.4:
				continue
			return [pa, pb]
	return []

func _meeting_clear(a: OfficeWorker, b: OfficeWorker, pa: Vector3, pb: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [a.get_rid(), b.get_rid()]
	for point in [pa, pb]:
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.825)
		if not a.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	var ray := PhysicsRayQueryParameters3D.create(pa + Vector3.UP, pb + Vector3.UP, 1)
	return a.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
