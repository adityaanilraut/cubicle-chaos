extends SceneTree

# Capture the real gameplay rig and shared bat poses for visual review.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1000, 780)
	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	paused = false
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	player.hud_layer.visible = false
	player.interaction_focus.set_target(null)
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person.nav_agent.avoidance_enabled = false
		person.visible = false
	player.global_position = Vector3(0.5, 0, 4.0)
	player.rotation.y = 0.0
	player.busy = 0.0
	player.seated = false
	var bat: PhysicsProp = office.spawn_prop("baseball_bat", player.global_position + Vector3(0, 0.04, 0.55))
	bat.pick_up(player)
	player.held_prop = bat
	bat.global_transform = BaseballBat.held_pose(player)
	var camera: IsometricCamera = office.iso_camera
	camera.target_zoom = 4.5
	camera.camera.size = 4.5
	camera.target_yaw_deg = 145.0
	camera.rotation_degrees.y = 145.0
	camera.focus_on(player.global_position + Vector3(0, 0, 0.4))
	camera.position = camera.target_pos + Vector3.UP * 0.6
	camera.set_process(false)
	DirAccess.make_dir_recursive_absolute("res://build/previews/bat")
	var poses := [["idle", "", 0.0], ["forehand-windup", "bat_forehand", 0.13], ["forehand-contact", "bat_forehand", 0.28], ["backhand-contact", "bat_backhand", 0.30], ["overhead-windup", "bat_overhead", 0.23], ["overhead-smash", "bat_overhead", 0.48]]
	for pose in poses:
		player.combat.reset()
		player.combat.stance_time = 2.0
		player.combat.stance_style = "Baseball"
		if not String(pose[1]).is_empty():
			player.combat.move_id = pose[1]
			player.combat.kind = "bat"
			player.combat.phase = OfficeCombat.Phase.ATTACK
			player.combat.phase_time = pose[2]
		bat.global_transform = BaseballBat.held_pose(player)
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/bat/" + pose[0] + ".png")
	print("Bat poses: ", ProjectSettings.globalize_path("res://build/previews/bat/"))
	office.queue_free()
	await process_frame
	quit()
