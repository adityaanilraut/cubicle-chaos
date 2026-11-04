extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var path := OfficeIntro.INTRO_PATH
	var existed := FileAccess.file_exists(path)
	var original := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	if existed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(office)
	await create_timer(0.8, true).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	await create_timer(0.8).timeout
	var intro: OfficeIntro = office.intro
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)
	check(intro.active and intro.panel.visible and not intro.moved, "First start offers a brief movement prompt")
	player.global_position = Vector3(2, 0, 5)
	intro.start_intro()
	player.global_position += Vector3(1.1, 0, 0)
	intro._process(0.1)
	check(intro.moved and intro.instruction.text.contains(OfficeInput.key_name("interact")), "Moving advances to the current talk key")
	var worker: OfficeWorker = office.workers_container.get_child(0)
	worker.global_position = player.global_position + Vector3(0, 0, 0.9)
	player.nearby = worker
	player.busy = 0.0
	player.interact()
	check(player.dialogue.is_open and intro.talked and intro.finish_time > 0.0, "Talking through the normal interaction completes the intro")
	check(office.levels.done[1], "Talking also advances the first level")
	player.dialogue.close()
	intro._process(4.0)
	check(not intro.active and not intro.panel.visible, "Completed intro dismisses itself")
	intro.start_if_new()
	check(not intro.active, "Completed intro does not reappear")
	intro.start_intro()
	intro.skip()
	intro.start_if_new()
	check(not intro.active, "Skipping is remembered")
	office.game_menu.return_to_title()
	var replay: Button
	for child in office.game_menu.content.get_children():
		if child is Button and child.text == "Replay introduction":
			replay = child
	check(is_instance_valid(replay), "Level menu offers to replay the introduction")
	if is_instance_valid(replay):
		replay.pressed.emit()
	check(intro.active and office.game_menu.menu_state == &"playing", "Replay starts a fresh introduction")
	intro.skip()
	await create_timer(0.8).timeout
	intro.start_intro()
	intro.notice_talk()
	player.global_position = intro.start_position + Vector3(1.1, 0, 0)
	intro._process(0.1)
	check(intro.talked and intro.moved and intro.finish_time > 0, "Talking before moving also completes the introduction")
	intro.skip()
	player.busy = 0.0
	var first_lines := {}
	for person in office.workers_container.get_children():
		person.global_position = Vector3(-11, 0, 8)
	for person in office.workers_container.get_children():
		person.global_position = player.global_position + Vector3(0, 0, 0.9)
		var lines := {}
		var replies := {}
		for i in range(6):
			check(player.dialogue.open(person), "Coworker accepts automatic conversation")
			lines[player.dialogue.current_text] = true
			if i == 0: first_lines[player.dialogue.current_text] = true
			check(person.social_speech.visible and not player.social_speech.visible, "Coworker speaks first")
			player.dialogue._process(OfficeDialogue.TURN_SECONDS)
			replies[player.dialogue.current_text] = true
			check(player.social_speech.visible and not person.social_speech.visible, "Player responds automatically")
			player.dialogue._process(OfficeDialogue.TURN_SECONDS)
			player.dialogue._process(OfficeDialogue.TURN_SECONDS)
			check(not player.dialogue.is_open, "Conversation finishes without a choice")
		check(lines.size() == 6 and replies.size() >= 4, "Each coworker rotates distinct lines and responses")
		person.global_position = Vector3(-11, 0, 8)
	check(first_lines.size() == office.workers_container.get_child_count(), "Coworkers have distinctive voices")
	var a: OfficeWorker = office.workers_container.get_child(0)
	var b: OfficeWorker = office.workers_container.get_child(1)
	var routines = office.get_node("OfficeRoutines")
	var topics := {}
	for i in range(12):
		a.completed_conversations = i
		var session := {"a": a, "b": b, "talk_time": 0.0, "line": -1}
		routines._update_social_speech(session)
		topics[a.social_speech.text] = true
		check(a.social_speech.visible and not b.social_speech.visible, "First coworker speaks alone")
		session["talk_time"] = 2.5
		routines._update_social_speech(session)
		check(b.social_speech.visible and not a.social_speech.visible, "Other coworker replies alone")
	check(topics.size() == 12, "Repeat coworker chats rotate through twelve exchanges")
	office.queue_free()
	await process_frame
	await create_timer(0.6).timeout
	if existed:
		var saved := FileAccess.open(path, FileAccess.WRITE)
		saved.store_buffer(original)
		saved.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("INTRO AND CONVERSATIONS: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
