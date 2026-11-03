extends SceneTree

# Render the actual generated meshes and AnimationPlayer output for visual QA.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 900)
	if "--office" in OS.get_cmdline_user_args():
		await _office_preview()
		return
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("d9e1e5")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	floor_mesh.material_override = AssetCatalog.get_shared_material("preview_floor", Color("8f9da8"))
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.position = Vector3(0, 8, 11)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0))
	var clips := ["idle", "walk", "typing", "drink", "wave", "shower", "run", "stretch"]
	for index in range(clips.size()):
		var worker := OfficeWorker.new()
		stage.add_child(worker)
		worker.setup(null, index, String(clips[index]), index)
		worker.set_physics_process(false)
		worker.nav_agent.avoidance_enabled = false
		worker.anim_tree.active = false
		worker.position = Vector3((float(index % 4) - 1.5) * 1.75, 0, float(index / 4) * 4.4 - 2.2)
		worker.rotation.y = 0.20
		worker.anim_player.play("office/" + clips[index])
		worker.anim_player.seek(worker.anim_player.current_animation_length * (0.5 if clips[index] != "run" else 0.25), true)
		worker.anim_player.pause()
		var label := Label3D.new()
		label.text = String(clips[index]).replace("_", " ")
		label.position.y = 2.1
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 44
		label.pixel_size = 0.003
		label.modulate = Color("233448")
		label.outline_size = 0
		worker.add_child(label)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	var path := "res://build/previews/original-characters.png"
	root.get_texture().get_image().save_png(path)
	print("Character preview: ", ProjectSettings.globalize_path(path))
	stage.queue_free()
	await process_frame
	quit()

func _office_preview() -> void:
	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	for frame in range(120):
		if is_instance_valid(office.game_menu): break
		await process_frame
	office.game_menu.pause_on_focus_loss = false
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	var path := "res://build/previews/original-office.png"
	root.get_texture().get_image().save_png(path)
	print("Office preview: ", ProjectSettings.globalize_path(path))
	office.queue_free()
	await process_frame
	quit()
