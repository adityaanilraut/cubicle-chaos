class_name WorkerSocial
extends RefCounted

# Coworker chats, paired social sessions and player conversations.
# Social state stays on the worker; this module drives the transitions.
var worker: OfficeWorker

func _init(p_worker: OfficeWorker) -> void:
	worker = p_worker

func join_coworker_chat(initiator: OfficeWorker) -> void:
	if worker.combat.is_engaged() or worker.is_seated or worker.state == OfficeWorker.State.SITTING or worker.state == OfficeWorker.State.WORKING or worker.state == OfficeWorker.State.WALKING:
		return
	worker._release_routine()
	worker._release_break_spot()
	worker.target_partner = initiator
	worker.break_type = OfficeWorker.BreakType.CHAT_WORKER
	worker.break_phase = OfficeWorker.BreakPhase.PERFORM_ACTION
	worker.state = OfficeWorker.State.BREAK
	worker.velocity = Vector3.ZERO
	worker.state_timer = 5.0
	worker.play_anim("wave" if randf() < 0.35 else ("talk2" if randf() < 0.5 else "talk"))
	worker._update_label()

func greet_player(player: OfficeWorker) -> void:
	# A seated coworker can answer without interrupting their chair animation.
	if worker.is_seated or worker.state == OfficeWorker.State.SITTING or worker.state == OfficeWorker.State.WORKING:
		return
	join_coworker_chat(player)
	worker.play_anim("wave")

func is_willing_to_socialize(initiator: OfficeWorker) -> bool:
	if is_instance_valid(worker.meeting) or worker == initiator or worker.combat.is_engaged() or worker.social_session_id != 0 or worker.social_cooldown > 0.0 or is_instance_valid(worker.player_conversation_partner) or worker._forced_stand_pending:
		return false
	if worker.state == OfficeWorker.State.WORKING:
		return worker.social_need >= 0.40 or worker.state_timer <= 12.0
	if worker.state == OfficeWorker.State.WALKING and worker.walk_goal == OfficeWorker.WalkGoal.TO_CHAIR and is_instance_valid(worker.routines) and worker.routines.outing_workers.has(worker):
		return worker.social_need >= 0.40
	return worker.state == OfficeWorker.State.IDLE and not worker.is_seated

func prepare_social_session(partner: OfficeWorker, meeting_position: Vector3, id: int) -> void:
	worker._release_break_spot()
	worker.social_session_id = id
	worker.target_partner = partner
	worker.target_walk_pos = meeting_position
	worker.break_type = OfficeWorker.BreakType.CHAT_WORKER
	worker._planned_break = true
	worker._social_departure_pending = true
	worker._social_arrived = false
	worker._stop_walking_velocity()
	worker._update_label()

func process_social_departure() -> void:
	if not is_instance_valid(worker.target_partner) or worker.social_session_id == 0:
		worker._release_routine()
		return
	if worker.is_seated:
		if is_instance_valid(worker.routines) and not worker.routines.request_stand(worker):
			worker.play_anim("typing")
			return
		worker._social_departure_pending = false
		worker._begin_standing()
	else:
		worker._social_departure_pending = false
		worker._choose_and_walk_to_break()

func begin_social_talk() -> void:
	worker.play_anim("talk")
	worker._update_label()

func show_social_speech(line: String) -> void:
	if worker.social_speech:
		worker.social_speech.say(line)

func finish_social_session(completed: bool, interrupted := false) -> void:
	worker.social_session_id = 0
	worker._social_departure_pending = false
	worker._social_arrived = false
	worker._planned_break = false
	worker.target_partner = null
	show_social_speech("")
	if completed:
		worker.completed_conversations += 1
		worker.social_need = 0.0
		worker.social_cooldown = 70.0 + float(worker.worker_index % 4) * 5.0
		worker.last_break_type = OfficeWorker.BreakType.CHAT_WORKER
	else:
		worker.social_cooldown = maxf(worker.social_cooldown, 18.0)
	if interrupted:
		return
	if worker.is_seated:
		if worker.state == OfficeWorker.State.BREAK:
			worker._idle_after_standing = true
		else:
			if is_instance_valid(worker.routines):
				worker.routines.release(worker)
			worker.state_timer = maxf(worker.state_timer, 8.0)
			worker.play_anim("typing")
		return
	return_to_own_work()

func return_to_own_work() -> void:
	var chair: FurnitureItem = worker.office_ref.get_or_assign_personal_chair(worker) if worker.office_ref else null
	if is_instance_valid(chair) and worker._chair_retry_timer <= 0.0:
		worker._start_walking_to_chair(chair)
	else:
		worker._deskless_wait = 15.0
		worker._enter_idle(3.0)

func can_accept_player_conversation(player: OfficeWorker) -> bool:
	if not is_instance_valid(player) or player == worker or worker.combat.is_engaged() or worker.social_session_id != 0 or worker._forced_stand_pending:
		return false
	if is_instance_valid(worker.player_conversation_partner):
		return worker.player_conversation_partner == player
	if worker.state == OfficeWorker.State.SITTING or (worker.state == OfficeWorker.State.BREAK and worker.is_seated):
		return false
	return true

func begin_player_conversation(player: OfficeWorker) -> bool:
	if not can_accept_player_conversation(player):
		return false
	if worker.player_conversation_partner == player:
		return true
	if (worker.state == OfficeWorker.State.WORKING or worker.state == OfficeWorker.State.IDLE) and is_instance_valid(worker.routines):
		# A seated conversation must not sit at the front of the stand queue.
		worker.routines.release(worker)
		worker._release_break_spot()
		worker._planned_break = false
	worker.player_conversation_partner = player
	worker._conversation_hold_time = 0.0
	worker._conversation_anim = String(worker.state_playback.get_current_node()) if worker.state_playback != null else "idle"
	worker._stop_walking_velocity()
	worker._path_initialized = false
	worker.play_anim("sitting_idle" if worker.is_seated else "idle_breath")
	worker._update_label()
	return true

func end_player_conversation(player: OfficeWorker) -> void:
	if worker.player_conversation_partner != player:
		return
	worker.player_conversation_partner = null
	worker._conversation_hold_time = 0.0
	worker._path_initialized = false
	worker.play_anim(worker._conversation_anim)
	worker._update_label()
