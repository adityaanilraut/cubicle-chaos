extends SceneTree

# Visual inspection of every family without changing the active office/save.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color("182128")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var title := Label.new()
	title.text = "OFFICE / DEBRIS FAMILIES"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 28)
	background.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(24, 60)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	background.add_child(grid)
	for family in DestructionProfile.FAMILIES:
		var spec: Dictionary = DestructionProfile.FAMILIES[family]
		var id: String = spec.items[0] if not spec.items.is_empty() else "future_asset"
		var profile := DestructionProfile.for_item(id)
		var panel := VBoxContainer.new()
		panel.custom_minimum_size = Vector2(302, 324)
		grid.add_child(panel)
		var label := Label.new()
		label.text = family.replace("_", " ").capitalize()
		label.add_theme_font_size_override("font_size", 20)
		panel.add_child(label)
		var subtitle := Label.new()
		subtitle.text = "%d types | %s" % [spec.items.size(), profile.material_id]
		subtitle.modulate = Color("abbcc5")
		panel.add_child(subtitle)
		var container := SubViewportContainer.new()
		container.custom_minimum_size = Vector2(302, 260)
		panel.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(302, 260)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("e3e5df")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.65
		viewport.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -30, 0)
		light.light_energy = 1.1
		viewport.add_child(light)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.8
		viewport.add_child(camera)
		camera.position = Vector3(2.5, 2.0, 3)
		camera.look_at(Vector3(0, 0.7, 0))
		var size := Vector3(1.3, 1.3, 0.9)
		if family in ["wooden_table", "workstation", "upholstered_seating", "office_chair"]: size = Vector3(1.5, 1.0, 1.0)
		if family == "paper": size = Vector3(1, 0.35, 0.8)
		if family == "textile": size = Vector3(1.5, 0.045, 1.3)
		if family in ["glass_fixture", "office_partition", "masonry"]: size = Vector3(1.5, 1.3, 0.25)
		var parts := Destruction._fracture_parts(size, profile)
		for part in parts:
			var chunk := DebrisChunk.new()
			viewport.add_child(chunk)
			chunk.setup(part.size, part.color, Vector3.ZERO, part.get("mesh"), profile, part.get("material", ""))
			chunk.freeze = true
			chunk.set_process(false)
			var offset: Vector3 = part.at - Vector3(0, size.y * 0.5, 0)
			chunk.position = part.at + offset * 0.28 + Vector3.UP * 0.08
			chunk.rotation.y = part.get("yaw", 0.0)
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/previews/debris-families.png"))
	print("Debris family preview saved to build/previews/debris-families.png")
	background.free()
	await process_frame
	quit()
