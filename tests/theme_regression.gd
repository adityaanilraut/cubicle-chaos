extends SceneTree

# Run with: Godot --headless --path . --script res://tests/theme_regression.gd
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

func _run() -> void:
	var settings_path := OfficeMenus.SETTINGS_PATH
	var had_settings := FileAccess.file_exists(settings_path)
	var saved_settings := FileAccess.get_file_as_bytes(settings_path) if had_settings else PackedByteArray()
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	# Theme assertions cover the default floor, independently of editor overrides.
	office.game_menu.set_setting("floor_color", "")
	office.game_menu.set_setting("floor_pattern", 0)
	office.game_menu.set_setting("floor_texture", 0)

	# One floor colour everywhere: every floor tile shares one material/colour.
	var tiles := office.find_child("FloorTiles", true, false)
	check(tiles != null and tiles.get_child_count() > 50, "Floor tiles exist across the whole office")
	var floor_colors := {}
	var tile_count := 0
	for tile in tiles.get_children():
		var stack: Array = [tile]
		while not stack.is_empty():
			var n = stack.pop_back()
			if n is MeshInstance3D and n.material_override != null:
				floor_colors[n.material_override.albedo_color.to_html()] = true
				tile_count += 1
			for c in n.get_children():
				stack.append(c)
	check(tile_count > 50, "Floor tiles carry a material")
	check(floor_colors.size() == 1, "Every floor tile uses exactly one colour (got %d)" % floor_colors.size())
	check(office.floor_mat != null and floor_colors.has(office.floor_mat.albedo_color.to_html()), "Tiles use the unified floor material")

	# All presets leave headroom for pale surfaces and overlapping room lights.
	for preset in range(office.LIGHT_PRESET_NAMES.size()):
		office.game_menu.set_setting("lighting", preset)
		check(office.light_preset_idx == preset, "Lighting preset %d applies" % preset)
		var env: Environment = office.world_env.environment
		check(env.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "Compatibility tone mapping preserves surface detail")
		check(env.tonemap_exposure >= 0.5 and env.tonemap_exposure <= 0.7, "Exposure keeps highlight headroom")
		check(env.ambient_light_energy >= 0.2 and env.ambient_light_energy <= 0.35, "Ambient light keeps shaded rooms readable without washing them out")
		check(office.sun_light.light_energy + office.fill_light.light_energy <= 0.8, "Directional lights stay within the daylight budget")
		for l in office.room_omni_lights:
			check(l.light_energy <= 0.2, "Overlapping room lights stay below the washout threshold")
			check(l.light_color.r > 0.9 and l.light_color.g > 0.85, "Room lights share one warm daylight colour")
	office.game_menu.set_setting("lighting", 0)

	# Data center equipment shares the warm office style; it is isolated in
	# its own room instead of displacing the focus room or public reception.
	var ids := {}
	for item in office.furniture_container.get_children():
		if item is FurnitureItem:
			ids[item.item_id] = true
	for techno in ["server_rack", "network_rack", "cooling_unit", "ups_battery"]:
		check(ids.has(techno), "Default data center includes " + techno)
		for item in office.furniture_container.get_children():
			if item.item_id == techno:
				check(item.position.x < -5 and item.position.z > 12, techno + " stays in the data center")
	check(ids.has("glass_table") and ids.has("whiteboard"), "Collaboration studio is furnished")
	check(ids.has("desk_pc") or ids.has("tech_workbench"), "Focus rooms are furnished with desks")

	# Theme options: all three exist, each keeps a single floor colour, switching recolours.
	check(OfficeTheme.THEMES.size() == 3, "Three theme options are offered")
	for i in range(OfficeTheme.THEMES.size()):
		office._apply_theme(i)
		check(office.floor_mat.albedo_color.is_equal_approx(OfficeTheme.floor_color(i)), "Theme %d recolours the unified floor" % i)
	office.game_menu.set_setting("theme", 1)
	check(office.theme_idx == 1 and office.floor_mat.albedo_color.is_equal_approx(OfficeTheme.floor_color(1)), "Settings theme option applies live")
	office.game_menu.set_setting("theme", 99)
	check(office.theme_idx == 2, "Theme setting clamps to a valid option")
	office.game_menu.set_setting("theme", 0)

	print("THEME CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	if had_settings:
		var file := FileAccess.open(settings_path, FileAccess.WRITE)
		file.store_buffer(saved_settings)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	quit(0 if failures.is_empty() else 1)
