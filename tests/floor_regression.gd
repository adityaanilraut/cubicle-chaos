extends SceneTree

const SETTINGS_PATH := "user://office_settings.cfg"
var failures: Array[String] = []
var checks := 0
var office: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func capture(filename: String) -> void:
	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/previews/" + filename + ".png"))

func _run() -> void:
	var had_settings := FileAccess.file_exists(SETTINGS_PATH)
	var saved_settings := FileAccess.get_file_as_bytes(SETTINGS_PATH) if had_settings else PackedByteArray()
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	var menu = office.game_menu
	menu.pause_on_focus_loss = false
	menu.start_game()
	menu.set_setting("simulation_speed", 0)
	office.set_editor_visible(true)
	check(office.floor_color_picker.is_visible_in_tree() and office.floor_pattern_option.is_visible_in_tree() and office.floor_texture_option.is_visible_in_tree(), "Floor controls appear in Edit office")
	check(office.floor_pattern_option.item_count == 4 and office.floor_texture_option.item_count == 4, "Editor offers all patterns and textures")

	# Exercise the actual editor signals, then reload saved preferences.
	office.floor_color_picker.color_changed.emit(Color("738c82"))
	office.floor_pattern_option.select(2)
	office.floor_pattern_option.item_selected.emit(2)
	office.floor_texture_option.select(1)
	office.floor_texture_option.item_selected.emit(1)
	check(office.floor_mat.albedo_color.is_equal_approx(Color("738c82")), "Color picker recolors the floor live")
	check(office.floor_pattern_idx == 2 and office.floor_texture_idx == 1 and office.floor_mat.albedo_texture != null, "Pattern and texture combine on the floor")
	menu.set_setting("theme", 1)
	menu.set_setting("lighting", 0)
	check(office.floor_mat.albedo_color.is_equal_approx(Color("738c82")) and office.floor_pattern_idx == 2, "Other settings preserve a custom floor")
	office._apply_floor_style("", 0, 0)
	menu._load_settings()
	check(office.floor_mat.albedo_color.is_equal_approx(Color("738c82")) and office.floor_pattern_idx == 2 and office.floor_texture_idx == 1, "Floor choices reload from saved preferences")
	check(office.floor_pattern_option.selected == 2 and office.floor_texture_option.selected == 1 and office.floor_color_picker.color.is_equal_approx(Color("738c82")), "Editor controls reflect loaded floor choices")

	for pattern in range(OfficeFloor.PATTERNS.size()):
		for finish in range(OfficeFloor.TEXTURES.size()):
			office._apply_floor_style("738c82", pattern, finish)
			check((office.floor_mat.albedo_texture == null) == (pattern == 0 and finish == 0), "Pattern %d / texture %d produces the expected floor material" % [pattern, finish])
	check(office.floor_mat.uv1_world_triplanar, "Texture alignment spans the whole office in world space")
	var stack: Array = [office.find_child("FloorTiles", true, false)]
	var all_shared := true
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is MeshInstance3D and node.material_override != office.floor_mat:
			all_shared = false
		stack.append_array(node.get_children())
	check(all_shared, "Every room and floor tile shares the customized material")

	menu.set_setting("floor_pattern", -3)
	menu.set_setting("floor_texture", 100)
	menu.set_setting("floor_color", "invalid")
	check(office.floor_pattern_idx == 0 and office.floor_texture_idx == 3 and office.floor_color_override.is_empty(), "Invalid floor preferences fall back to valid choices")
	menu.set_setting("floor_color", "")
	check(office.floor_mat.albedo_color.is_equal_approx(OfficeTheme.floor_color(office.theme_idx)), "Match theme restores the theme floor color")
	menu.set_setting("floor_pattern", 0)
	menu.set_setting("floor_texture", 0)
	check(office.floor_mat.albedo_texture == null, "Solid and smooth restore an untextured floor")

	if "--capture" in OS.get_cmdline_user_args():
		office.iso_camera.target_yaw_deg = 45
		office.iso_camera.focus_on(Vector3(-2, 0, 4))
		office.iso_camera.target_zoom = 22
		menu.set_setting("floor_color", "a9987e")
		menu.set_setting("floor_pattern", 2)
		menu.set_setting("floor_texture", 1)
		await capture("floor-editor")
		office.set_editor_visible(false)
		menu.set_setting("floor_color", "879b96")
		menu.set_setting("floor_pattern", 1)
		menu.set_setting("floor_texture", 3)
		await capture("floor-stone")

	office.set_editor_visible(false)
	check(not office.floor_color_picker.is_visible_in_tree(), "Done hides floor controls")
	root.remove_child(office)
	office.queue_free()
	await process_frame
	if had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(saved_settings)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	Engine.time_scale = 1.0
	print("FLOOR CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
