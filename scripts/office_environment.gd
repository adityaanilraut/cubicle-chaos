class_name OfficeEnvironment
extends RefCounted

# Environment, lighting, theme and floor finish for the office.
# State stays on the office; this module only operates on it.
var office: Node3D

func _init(p_office: Node3D) -> void:
	office = p_office

func setup_environment_and_lights() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.0
	# Keep pale surfaces below clipping in the Compatibility/Web renderer.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	office.world_env = WorldEnvironment.new()
	office.world_env.name = "WorldEnvironment"
	office.world_env.environment = env
	office.add_child(office.world_env)

	office.sun_light = DirectionalLight3D.new()
	office.sun_light.name = "SunLight"
	office.sun_light.rotation_degrees = Vector3(-50.0, 36.0, 0.0)
	office.sun_light.shadow_enabled = true
	office.sun_light.directional_shadow_max_distance = 70.0
	office.add_child(office.sun_light)

	office.fill_light = DirectionalLight3D.new()
	office.fill_light.name = "FillLight"
	office.fill_light.rotation_degrees = Vector3(-38.0, -135.0, 0.0)
	office.fill_light.shadow_enabled = false
	office.add_child(office.fill_light)

	# One consistent daylight colour in every room — no per-room tints.
	var daylight := Color(1.0, 0.95, 0.86)
	var room_light_configs := [
		{"pos": Vector3(-9.0, 3.2, -6.0), "color": daylight, "range": 8.5},
		{"pos": Vector3(-1.0, 3.2, -6.0), "color": daylight, "range": 8.0},
		{"pos": Vector3(8.0, 3.2, -6.0), "color": daylight, "range": 9.0},
		{"pos": Vector3(-5.0, 3.6, 3.5), "color": daylight, "range": 12.0},
		{"pos": Vector3(9.0, 3.2, 4.0), "color": daylight, "range": 9.5},
		{"pos": Vector3(-9, 3.2, 16), "color": daylight, "range": 7.5},
		{"pos": Vector3(-2, 3.2, 16), "color": daylight, "range": 6.0},
		{"pos": Vector3(4, 3.2, 16), "color": daylight, "range": 6.0},
		{"pos": Vector3(10, 3.2, 16), "color": daylight, "range": 6.0},
		{"pos": Vector3(16.5, 3.2, -6), "color": daylight, "range": 6.0},
		{"pos": Vector3(17, 3.2, 3.5), "color": daylight, "range": 7.5},
		{"pos": Vector3(17, 3.2, 9), "color": daylight, "range": 6.0},
		{"pos": Vector3(16.5, 3.2, 16), "color": daylight, "range": 6.0},
	]
	for cfg in room_light_configs:
		var omni := OmniLight3D.new()
		omni.position = cfg["pos"]
		omni.light_color = cfg["color"]
		omni.omni_range = cfg["range"]
		omni.omni_attenuation = 1.35
		office.add_child(omni)
		office.room_omni_lights.append(omni)

	apply_lighting_preset(0)

func apply_lighting_preset(idx: int) -> void:
	office.light_preset_idx = idx % office.LIGHT_PRESET_NAMES.size()
	var env: Environment = office.world_env.environment
	match office.light_preset_idx:
		0: # Balanced daylight with headroom for pale walls and overlapping lights.
			env.background_color = Color(0.20, 0.24, 0.29)
			env.ambient_light_color = Color(0.96, 0.94, 0.89)
			env.ambient_light_energy = 0.28
			env.tonemap_exposure = 0.62
			office.sun_light.light_color = Color(1.0, 0.96, 0.88)
			office.sun_light.light_energy = 0.62
			office.fill_light.light_color = Color(0.82, 0.88, 0.96)
			office.fill_light.light_energy = 0.12
			for l in office.room_omni_lights:
				l.light_energy = 0.16
		1: # Softer daylight with a weaker key light.
			env.background_color = Color(0.22, 0.25, 0.29)
			env.ambient_light_color = Color(0.95, 0.93, 0.88)
			env.ambient_light_energy = 0.30
			env.tonemap_exposure = 0.60
			office.sun_light.light_color = Color(1.0, 0.95, 0.87)
			office.sun_light.light_energy = 0.46
			office.fill_light.light_color = Color(0.80, 0.87, 0.95)
			office.fill_light.light_energy = 0.14
			for l in office.room_omni_lights:
				l.light_energy = 0.14
		2: # Warm afternoon without overexposing light oak and white surfaces.
			env.background_color = Color(0.25, 0.24, 0.23)
			env.ambient_light_color = Color(0.96, 0.91, 0.82)
			env.ambient_light_energy = 0.26
			env.tonemap_exposure = 0.62
			office.sun_light.light_color = Color(1.0, 0.90, 0.74)
			office.sun_light.light_energy = 0.56
			office.fill_light.light_color = Color(0.78, 0.85, 0.94)
			office.fill_light.light_energy = 0.10
			for l in office.room_omni_lights:
				l.light_energy = 0.16

	if office.btn_light:
		office.btn_light.text = "💡 Light: " + office.LIGHT_PRESET_NAMES[office.light_preset_idx]

func apply_theme(idx: int) -> void:
	office.theme_idx = clampi(idx, 0, OfficeTheme.THEMES.size() - 1)
	var theme := OfficeTheme.get_theme(office.theme_idx)
	if is_instance_valid(office.floor_mat):
		apply_floor_style(office.floor_color_override, office.floor_pattern_idx, office.floor_texture_idx)
	if is_instance_valid(office.plinth_mat):
		office.plinth_mat.albedo_color = theme["plinth"]
	AssetCatalog.get_shared_material("modern_architecture", theme["architecture"], 0.38).albedo_color = theme["architecture"]
	AssetCatalog.get_shared_material("modern_frame", theme["frame"], 0.38).albedo_color = theme["frame"]
	for lbl in office.room_sign_labels:
		if is_instance_valid(lbl):
			lbl.modulate = theme["sign"]

func apply_floor_style(color_hex: String, pattern: int, finish: int) -> void:
	office.floor_color_override = color_hex if Color.html_is_valid(color_hex) else ""
	office.floor_pattern_idx = clampi(pattern, 0, OfficeFloor.PATTERNS.size() - 1)
	office.floor_texture_idx = clampi(finish, 0, OfficeFloor.TEXTURES.size() - 1)
	var color := OfficeTheme.floor_color(office.theme_idx) if office.floor_color_override.is_empty() else Color.html(office.floor_color_override)
	OfficeFloor.apply(office.floor_mat, color, office.floor_pattern_idx, office.floor_texture_idx)
	if is_instance_valid(office.floor_color_picker):
		office.floor_color_picker.color = color
		office.floor_pattern_option.select(office.floor_pattern_idx)
		office.floor_texture_option.select(office.floor_texture_idx)

func toggle_lighting() -> void:
	if is_instance_valid(office.game_menu):
		office.game_menu.set_setting("lighting", (office.light_preset_idx + 1) % office.LIGHT_PRESET_NAMES.size())
	else:
		apply_lighting_preset(office.light_preset_idx + 1)
