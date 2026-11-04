extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer
var dialogue: OfficeDialogue
var origin := Vector3(2, 0, 5)

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func settle(frames := 3) -> void:
	for index in range(frames):
		await process_frame
		await physics_frame

func key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func capture_dialogue() -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	office.iso_camera.target_zoom = 9.5
	office.iso_camera.focus_on(player.global_position + Vector3(0, 0, 0.5))
	await settle(15)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/office-dialogue-conversation.png")

func ready_worker(index: int) -> OfficeWorker:
	dialogue.close()
	for person in office.workers_container.get_children():
		person.global_position = Vector3(-11, 0, 8)
	var worker: OfficeWorker = office.workers_container.get_child(index)
	worker._enter_idle(100.0)
	worker.global_position = origin + Vector3(0, 0, 0.9)
	player.global_position = origin
	player.busy = 0.0
	player.nearby = worker
	return worker

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
		worker.nav_agent.avoidance_enabled = false
		worker._enter_idle(100.0)
	dialogue = player.get("dialogue")
	check(dialogue != null, "Player has automatic emoji conversations")
	if dialogue == null:
		quit(1)
		return
	check(not office.editor_visible and not office.editor_root.visible and office.editor_toggle.visible, "Editor starts hidden with one button to bring it back")
	check(not player.prompt.visible and not player.objective.visible and not player.work_status.visible, "Normal play has no fixed task, controls, or work panels")
	check(not player.status_label.visible, "Player has no permanent text above their head")
	for person in office.workers_container.get_children():
		check(not person.status_label.visible, "Coworker labels stay hidden in clean play")
	office.editor_toggle.pressed.emit()
	check(office.editor_visible and office.editor_root.visible, "Editor button restores the furniture tools")
	var item: FurnitureItem = office.place_furniture_item("desk_plain", Vector3(2, 0, 5), 0.0, false)
	office.select_furniture(item)
	office.start_moving_selected()
	var original: Vector3 = office.move_original_pos
	item.global_position += Vector3(2, 0, 0)
	office.editor_toggle.pressed.emit()
	check(not office.editor_visible and office.edit_mode == office.EditMode.SELECT and office.selected_furniture == null and item.global_position.is_equal_approx(original), "Closing editor restores an unfinished move and removes selection")
	item.queue_free()
	await settle()
	await key(KEY_1)
	await key(KEY_1, false)
	check(office.edit_mode == office.EditMode.SELECT and office.preview_furniture == null, "Hidden catalog hotkeys cannot begin a build")
	var first_lines := {}
	for index in range(6):
		var worker := ready_worker(index)
		await settle()
		check(dialogue.open(worker), worker.worker_name + " accepts a nearby conversation")
		first_lines[dialogue.current_text] = true
		check(dialogue.is_open and worker.player_conversation_partner == player and dialogue.get_child_count() == 0, worker.worker_name + " talks without a choice panel")
		check(worker.social_speech.visible and not player.social_speech.visible, "Only the speaking coworker has a bubble")
		dialogue._process(OfficeDialogue.TURN_SECONDS)
		check(player.social_speech.visible and not worker.social_speech.visible, "Player replies automatically in their own bubble")
		dialogue._process(OfficeDialogue.TURN_SECONDS)
		check(worker.social_speech.visible and not player.social_speech.visible, "Coworker waves goodbye automatically")
		dialogue._process(OfficeDialogue.TURN_SECONDS)
		check(not dialogue.is_open and not worker.social_speech.visible and not player.social_speech.visible, "Conversation finishes and clears both bubbles without input")
		dialogue.close()
		check(worker.player_conversation_partner == null, worker.worker_name + " resumes after the conversation closes")
	check(first_lines.size() == 6, "All six coworkers have distinct emoji greetings")
	var alex := ready_worker(0)
	await settle()
	var visits: int = dialogue.get_memory(alex).visits
	dialogue.open(alex)
	check(int(dialogue.get_memory(alex).visits) == visits + 1 and dialogue.current_text != OfficeDialogue.PROFILES["Alex"][0], "Returning visits rotate emoji greetings")
	await capture_dialogue()
	var before := alex.global_position
	var timer := alex.state_timer
	alex._physics_process(0.5)
	check(alex.global_position.is_equal_approx(before) and alex.state_timer == timer, "Conversation holds NPC movement and routine timing")
	player.set_physics_process(true)
	var player_before := player.global_position
	var yaw: float = office.iso_camera.target_yaw_deg
	await key(KEY_W)
	await key(KEY_Q)
	await settle(8)
	await key(KEY_W, false)
	await key(KEY_Q, false)
	check(player.global_position.is_equal_approx(player_before) and is_equal_approx(office.iso_camera.target_yaw_deg, yaw), "Held movement and camera keys do not move the player during dialogue")
	player.set_physics_process(false)
	await key(KEY_1)
	await key(KEY_1, false)
	check(office.edit_mode == office.EditMode.SELECT, "Number keys cannot trigger hidden furniture catalog hotkeys")
	await key(KEY_P)
	await key(KEY_P, false)
	await process_frame
	check(paused and dialogue.is_open and not dialogue.visible, "P pauses and hides dialogue while preserving its session")
	# Paused scene-tree physics frames do not advance, so use process frames here.
	await key(KEY_P)
	await key(KEY_P, false)
	await process_frame
	check(not paused and dialogue.is_open and dialogue.visible, "Resuming restores the same conversation")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE, false)
	check(not dialogue.is_open and not paused and office.game_menu.menu_state == &"playing", "Escape closes dialogue before opening the pause menu")
	alex.global_position = Vector3(-11, 0, 8)
	var fallback: OfficeWorker = office.spawn_worker(origin + Vector3(0, 0, 0.9))
	fallback.set_physics_process(false)
	fallback._enter_idle(100.0)
	await settle()
	check(dialogue.open(fallback) and dialogue.current_text == OfficeDialogue.FALLBACK[0], "Additional hires have an emoji introduction")
	dialogue.close()
	fallback.queue_free()
	await settle()
	var maya := ready_worker(1)
	await settle()
	office.levels.set_level(1)
	player.global_position = origin # New levels now restart at the entrance.
	player.nearby = maya
	player.interact()
	check(dialogue.is_open and dialogue.speaker == maya, "Interacting with Maya opens her conversation")
	check(office.levels.done[1], "Talking to Maya completes the level one conversation objective")
	check(dialogue.get_talk_label(maya) == "Talk", "Coworkers expose the normal conversation action")
	dialogue.close()
	player.busy = 0.0
	maya.state = OfficeWorker.State.WORKING
	maya.is_seated = true
	maya.state_timer = 20.0
	check(dialogue.open(maya) and maya.is_seated, "Seated coworker can talk without standing")
	maya._physics_process(0.5)
	check(maya.is_seated and maya.state == OfficeWorker.State.WORKING and maya.state_timer == 20.0, "Seated conversation preserves chair state and work timing")
	dialogue.close()
	maya.is_seated = false
	maya._enter_idle(100.0)
	dialogue.open(maya)
	player.global_position += Vector3(4, 0, 0)
	await settle()
	check(not dialogue.is_open and maya.player_conversation_partner == null, "Leaving conversation range closes the panel and releases the NPC")
	maya = ready_worker(1)
	await settle()
	dialogue.open(maya)
	maya.interrupt_for_combat()
	await settle()
	check(not dialogue.is_open, "Interrupted NPC routine closes its dialogue")
	maya = ready_worker(1)
	await settle()
	dialogue.open(maya)
	office.game_menu.return_to_title()
	await process_frame
	check(not dialogue.is_open and maya.player_conversation_partner == null, "Returning to title ends the held conversation")
	office.game_menu.start_game()
	alex = ready_worker(0)
	await settle()
	dialogue.open(alex)
	alex.queue_free()
	await settle()
	check(not dialogue.is_open, "Deleting the speaker safely closes dialogue")
	office.queue_free()
	await process_frame
	print("DIALOGUE CHECKS: ", checks - failures.size(), "/", checks, " passed")
	quit(0 if failures.is_empty() else 1)
