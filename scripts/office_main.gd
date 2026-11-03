extends Node3D

@export var start_in_menu := true
var levels: OfficeLevels
var game_menu: OfficeMenus
var intro: OfficeIntro
var hud: CanvasLayer
var editor_root: Control
var editor_toggle: Button
var editor_visible := false

enum EditMode {
	SELECT,
	PLACE_NEW,
	MOVE_EXISTING
}

const FLOOR_BOUNDS := Rect2(-13.0, -10.0, 34.0, 30.0)
const GRID_SNAP := 0.25

const WORKER_NAMES: Array[String] = [
	"Alex", "Maya", "Jordan", "Sam", "Taylor", "Morgan",
	"Casey", "Riley", "Jamie", "Avery", "Quinn", "Skyler",
	"Devon", "Reese", "Parker", "Blake", "Hayden", "Rowan",
	"Emerson", "Finley", "Dakota", "Charlie", "Sawyer", "Peyton"
]

var iso_camera: IsometricCamera = null
var player: OfficePlayer = null
var nav_region: NavigationRegion3D = null
var furniture_container: Node3D = null
var workers_container: Node3D = null
var props_container: Node3D = null
var audio: OfficeAudio = null
var environment: OfficeEnvironment
var desks: OfficeDesks
var editor_ui: OfficeEditorUi
var ceiling_fans: Array[Node3D] = []

# Environment & Lighting references
var world_env: WorldEnvironment = null
var sun_light: DirectionalLight3D = null
var fill_light: DirectionalLight3D = null
var room_omni_lights: Array[OmniLight3D] = []
var light_preset_idx: int = 0
const LIGHT_PRESET_NAMES: Array[String] = ["Daylight", "Soft Daylight", "Golden Afternoon"]
var theme_idx: int = 0
var floor_mat: StandardMaterial3D = null
var floor_color_override := ""
var floor_pattern_idx := 0
var floor_texture_idx := 0
var floor_color_picker: ColorPickerButton
var floor_pattern_option: OptionButton
var floor_texture_option: OptionButton
var plinth_mat: StandardMaterial3D = null
var room_sign_labels: Array[Label3D] = []

var edit_mode: EditMode = EditMode.SELECT
var selected_furniture: FurnitureItem = null
var preview_furniture: FurnitureItem = null
var placing_item_id: String = ""
var move_original_pos: Vector3 = Vector3.ZERO
var move_original_rot_y: float = 0.0
var preview_rot_y: float = 0.0

var show_worker_labels: bool = true
var sim_speed_idx: int = 0
const SIM_SPEEDS: Array[float] = [1.0, 2.0, 3.0]
var _next_desk_number: int = 1

# UI references
var stats_label: Label = null
var mode_status_label: Label = null
var inspector_title_label: Label = null
var inspector_owner_label: Label = null
var inspector_hint_label: Label = null
var btn_move: Button = null
var btn_rotate: Button = null
var btn_delete: Button = null
var btn_cancel: Button = null
var btn_light: Button = null
var build_buttons: Dictionary = {}

var _nav_rebake_pending: bool = false
var _ui_refresh_timer: float = 0.0
var placement_issue: String = ""
var _drag_rebake_timer: float = 0.0
var _last_drag_bake_pos := Vector3.INF

func _ready() -> void:
	randomize()
	environment = OfficeEnvironment.new(self)
	desks = OfficeDesks.new(self)
	editor_ui = OfficeEditorUi.new(self)
	audio = OfficeAudio.new()
	audio.name = "OfficeAudio"
	add_child(audio)
	_setup_environment_and_lights()
	_setup_camera()
	_setup_navigation_and_room()
	_build_initial_office()
	_reconcile_desk_assignments()
	_setup_ui()
	_request_navmesh_rebake()

	# Spawn 6 initial workers after first frame so NavigationMesh is baked & ready
	await get_tree().process_frame
	var initial_spawns: Array[Vector3] = [
		Vector3(-1.0, 0.0, -4.6), # Alex near Executive Office
		Vector3(-8.5, 0.0, 2.6),  # Maya in Open Floor West
		Vector3(-4.5, 0.0, 2.6),  # Jordan in Open Floor Center
		Vector3(6.8, 0.0, -5.0),  # Sam in Break Room & Kitchen
		Vector3(-8.5, 0.0, 7.2),  # Taylor in Open Floor South
		Vector3(7.6, 0.0, 2.2),   # Morgan in Lounge Area
	]
	for sp in initial_spawns:
		spawn_worker(sp)
	_spawn_player_and_cup()
	_spawn_props()
	_refresh_ui()
	levels = OfficeLevels.new()
	add_child(levels)
	levels.setup(self)
	intro = OfficeIntro.new()
	add_child(intro)
	intro.setup(self)
	game_menu = OfficeMenus.new()
	add_child(game_menu)
	game_menu.setup(self, start_in_menu)

func spawn_prop(prop_id: String, world_pos: Vector3) -> PhysicsProp:
	var prop := PhysicsProp.new()
	prop.setup(prop_id)
	props_container.add_child(prop)
	prop.global_position = Vector3(world_pos.x, world_pos.y, world_pos.z)
	return prop

func _spawn_props() -> void:
	var spawns: Array = [
		["book", Vector3(-6.5, 0.05, 1.2)],
		["box", Vector3(4.8, 0.05, -3.4)],
		["plant", Vector3(-3.2, 0.05, 5.8)],
		["laptop", Vector3(0.5, 0.05, 7.6)],
		["radio", Vector3(7.2, 0.05, 6.4)],
		["speaker", Vector3(-10.5, 0.05, 4.6)],
		["keyboard", Vector3(-1.5, 0.05, 1.0)],
		["bear", Vector3(10.8, 0.05, 5.6)],
		["monitor", Vector3(1.4, 0.05, 8.4)],
		["laptop", Vector3(-2.0, 0.05, 15.0)],
		["box", Vector3(-3.8, 0.05, 18.7)],
	]
	for entry in spawns:
		var prop := spawn_prop(String(entry[0]), entry[1] as Vector3)
		# Props should begin in reachable gaps, not embedded in coarse desk boxes.
		if not prop.fits_at(prop.global_position, 0.0):
			var placed := false
			for radius in [0.6, 1.2, 1.8, 2.4]:
				for direction in range(8):
					var angle := float(direction) * TAU / 8
					var point: Vector3 = entry[1] + Vector3(cos(angle), 0, sin(angle)) * radius
					if FLOOR_BOUNDS.grow(-0.6).has_point(Vector2(point.x, point.z)) and prop.fits_at(point, 0.0):
						prop.global_position = point
						placed = true
						break
				if placed: break

func on_furniture_destroyed(item: FurnitureItem) -> void:
	_notify_workers_furniture_changed(item, true)
	if is_instance_valid(player):
		player.on_furniture_destroyed(item)
	if selected_furniture == item:
		select_furniture(null)
	call_deferred("_reconcile_desk_assignments")
	_request_navmesh_rebake()
	_refresh_ui()

func save_shift() -> bool:
	var ok := OfficeSave.save_game(self)
	if is_instance_valid(player):
		player.message.text = "Shift saved." if ok else "Could not save this shift."
		if ok:
			OfficeAudio.play_at(get_tree(), "ding")
	return ok

func load_shift() -> bool:
	var ok := OfficeSave.load_game(self)
	if is_instance_valid(player):
		player.message.text = "Shift loaded." if ok else "No saved shift found."
		if ok:
			OfficeAudio.play_at(get_tree(), "ding")
	return ok

func _spawn_player_and_cup() -> void:
	player = OfficePlayer.new()
	player.setup_player(self)
	add_child(player)
	player.global_position = Vector3(-7.5, 0.0, 4.5)
	iso_camera.follow_player = true
	iso_camera.target_zoom = 12.0
	var cup := Node3D.new()
	cup.name = "WaterCup"
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.10
	mesh.bottom_radius = 0.07
	mesh.height = 0.22
	visual.mesh = mesh
	visual.position.y = 0.11
	visual.material_override = AssetCatalog.get_shared_material("water_cup", Color(0.95, 0.8, 0.35), 0.4)
	cup.add_child(visual)
	cup.add_to_group("player_interactable")
	add_child(cup)
	cup.global_position = Vector3(9.2, 0.0, -7.3)

func _setup_environment_and_lights() -> void:
	environment.setup_environment_and_lights()

func _apply_lighting_preset(idx: int) -> void:
	environment.apply_lighting_preset(idx)

func _apply_theme(idx: int) -> void:
	environment.apply_theme(idx)

func _apply_floor_style(color_hex: String, pattern: int, finish: int) -> void:
	environment.apply_floor_style(color_hex, pattern, finish)

func _on_toggle_lighting() -> void:
	environment.toggle_lighting()

func _setup_camera() -> void:
	iso_camera = IsometricCamera.new()
	iso_camera.pan_bounds = FLOOR_BOUNDS.grow(2.0)
	iso_camera.name = "IsometricCamera"
	add_child(iso_camera)

func _setup_navigation_and_room() -> void:
	var nav_map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(nav_map, 0.10)
	NavigationServer3D.map_set_cell_height(nav_map, 0.10)

	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = &"nav_bake"
	nav_mesh.cell_size = 0.10
	nav_mesh.cell_height = 0.10
	nav_mesh.agent_height = 1.70
	nav_mesh.agent_radius = 0.30
	nav_mesh.agent_max_climb = 0.20
	nav_mesh.agent_max_slope = 30.0
	nav_region.navigation_mesh = nav_mesh
	nav_region.bake_finished.connect(func():
		if _nav_rebake_pending:
			call_deferred("_do_navmesh_rebake")
	)
	add_child(nav_region)

	var room_root := Node3D.new()
	room_root.name = "OfficeRoom"
	nav_region.add_child(room_root)

	# One continuous navigable floor for the original office and modern south wing
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.add_to_group("nav_bake")
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(FLOOR_BOUNDS.size.x, 0.2, FLOOR_BOUNDS.size.y)
	floor_col.shape = floor_box
	floor_col.position = Vector3(FLOOR_BOUNDS.get_center().x, -0.1, FLOOR_BOUNDS.get_center().y)
	floor_body.add_child(floor_col)
	room_root.add_child(floor_body)

	# Architectural plinth frame under floor (light, matches the theme)
	plinth_mat = AssetCatalog.get_shared_material("room_plinth", OfficeTheme.get_theme(theme_idx)["plinth"], 0.88)
	var base_mi := MeshInstance3D.new()
	var base_bm := BoxMesh.new()
	base_bm.size = Vector3(FLOOR_BOUNDS.size.x + 0.45, 0.24, FLOOR_BOUNDS.size.y + 0.45)
	base_mi.mesh = base_bm
	base_mi.position = Vector3(FLOOR_BOUNDS.get_center().x, -0.13, FLOOR_BOUNDS.get_center().y)
	base_mi.material_override = plinth_mat
	room_root.add_child(base_mi)

	# One shared floor finish across all rooms, customized from the editor.
	floor_mat = AssetCatalog.get_shared_material("office_floor_unified", OfficeTheme.floor_color(theme_idx), 0.75)

	var tiles_root := Node3D.new()
	tiles_root.name = "FloorTiles"
	room_root.add_child(tiles_root)

	var tile_step := 2.0
	var nx := int(round(FLOOR_BOUNDS.size.x / tile_step))
	var nz := int(round(FLOOR_BOUNDS.size.y / tile_step))
	for ix in range(nx):
		for iz in range(nz):
			var td := AssetCatalog.instantiate_centered_glb("floorFull.glb", 2.0)
			var t_node: Node3D = td["node"]
			var px := FLOOR_BOUNDS.position.x + tile_step * 0.5 + float(ix) * tile_step
			var pz := FLOOR_BOUNDS.position.y + tile_step * 0.5 + float(iz) * tile_step
			t_node.position = Vector3(px, -0.09, pz)

			AssetCatalog.apply_material_recursive(t_node, floor_mat)
			tiles_root.add_child(t_node)

	# Outer Cutaway Back Walls along North (-Z) and West (-X) edges
	var walls_root := Node3D.new()
	walls_root.name = "ArchitectureWalls"
	room_root.add_child(walls_root)

	for ix in range(nx):
		var wx := FLOOR_BOUNDS.position.x + tile_step * 0.5 + float(ix) * tile_step
		var w_file := "wall.glb"
		if ix in [1, 2, 5, 6, 9, 11]:
			w_file = "wallWindow.glb"
		elif ix == 10:
			w_file = "wallDoorway.glb"
		var wd := AssetCatalog.instantiate_centered_glb(w_file, 2.0)
		var w_node: Node3D = wd["node"]
		w_node.position = Vector3(wx, 0.0, FLOOR_BOUNDS.position.y)
		walls_root.add_child(w_node)

	for iz in range(nz):
		var wz := FLOOR_BOUNDS.position.y + tile_step * 0.5 + float(iz) * tile_step
		var w_file := "wallWindow.glb" if (iz in [1, 2, 5, 7]) else "wall.glb"
		var wd := AssetCatalog.instantiate_centered_glb(w_file, 2.0)
		var w_node: Node3D = wd["node"]
		w_node.position = Vector3(FLOOR_BOUNDS.position.x, 0.0, wz)
		w_node.rotation.y = PI * 0.5
		walls_root.add_child(w_node)

	# Build Interior Room Walls & Doorways separating:
	# 1) Conference Room (NW), 2) Executive Office (NC), 3) Break Room & Kitchen (NE), and 4) Open Floor (Center/South)
	_build_interior_rooms_architecture(walls_root)
	OfficeExpansion.build_architecture(self, walls_root)
	OfficeArrival.build_architecture(self, walls_root)

	furniture_container = Node3D.new()
	furniture_container.name = "FurnitureContainer"
	nav_region.add_child(furniture_container)

	workers_container = Node3D.new()
	workers_container.name = "WorkersContainer"
	add_child(workers_container)

	props_container = Node3D.new()
	props_container.name = "PropsContainer"
	add_child(props_container)

func _add_wall_segment(parent: Node3D, glb_file: String, pos: Vector3, rot_y: float, scale_vec: Vector3 = Vector3.ONE, is_obstacle: bool = true) -> void:
	var wd := AssetCatalog.instantiate_centered_glb(glb_file, 2.0)
	var w_node: Node3D = wd["node"]
	w_node.position = pos
	w_node.rotation.y = rot_y
	w_node.scale = scale_vec
	parent.add_child(w_node)

	if is_obstacle:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		sb.add_to_group("nav_bake")
		sb.position = pos
		sb.rotation.y = rot_y
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var raw_sz: Vector3 = wd["size"] * scale_vec
		box.size = Vector3(maxf(raw_sz.x, 0.18), maxf(raw_sz.y, 0.5), maxf(raw_sz.z, 0.22))
		col.shape = box
		col.position = Vector3(0.0, box.size.y * 0.5, 0.0)
		sb.add_child(col)
		parent.add_child(sb)

func _add_room_sign(parent: Node3D, text: String, pos: Vector3, color: Color = Color(0.92, 0.88, 0.78)) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	lbl.pixel_size = 0.0052
	lbl.font_size = 36
	lbl.outline_size = 12
	lbl.modulate = color
	lbl.outline_modulate = Color(0.25, 0.22, 0.18, 0.92)
	room_sign_labels.append(lbl)
	parent.add_child(lbl)

func _build_interior_rooms_architecture(walls_root: Node3D) -> void:
	# East Wall of Conference Room along X = -5.0 (Z from -10 to -2)
	for wz in [-9.0, -7.0, -3.0]:
		var f := "wallWindow.glb" if wz == -7.0 else "wall.glb"
		_add_wall_segment(walls_root, f, Vector3(-5.0, 0.0, wz), PI * 0.5, Vector3(1.0, 0.85, 1.0), true)
	# Wide doorway between Conference Room & Executive Office at Z = -5.0 (visual frame, open walk-through)
	_add_wall_segment(walls_root, "wallDoorwayWide.glb", Vector3(-5.0, 0.0, -5.0), PI * 0.5, Vector3(1.0, 0.85, 1.0), false)

	# East Wall of Executive Office along X = +3.0 (Z from -10 to -2)
	for wz in [-9.0, -7.0, -3.0]:
		var f := "wallWindow.glb" if wz == -7.0 else "wall.glb"
		_add_wall_segment(walls_root, f, Vector3(3.0, 0.0, wz), PI * 0.5, Vector3(1.0, 0.85, 1.0), true)
	# Wide doorway between Executive Office & Break Room at Z = -5.0
	_add_wall_segment(walls_root, "wallDoorwayWide.glb", Vector3(3.0, 0.0, -5.0), PI * 0.5, Vector3(1.0, 0.85, 1.0), false)

	# South Divider Wall along Z = -2.0 separating the 3 North Rooms from the Open Floor
	# Uses cutaway half-height walls (scale.y = 0.48) so isometric view is clear, with 3 wide 2.0m doorways:
	# - Conference Room doorway at X = -9.0 (open from -10.0 to -8.0)
	# - Executive Office doorway at X = -1.0 (open from -2.0 to 0.0)
	# - Break Room & Kitchen doorway at X = +8.0 (open from +7.0 to +9.0)
	var half_wall_xs := [
		-12.5, -11.5, -10.5, # West of Conf doorway
		-7.5, -6.5, -5.5,    # East of Conf doorway
		-4.5, -3.5, -2.5,    # West of Exec doorway
		0.5, 1.5, 2.5,       # East of Exec doorway
		3.5, 4.5, 5.5, 6.5,  # West of Kitchen doorway
		9.5, 10.5, 11.5, 12.5 # East of Kitchen doorway
	]
	for hx in half_wall_xs:
		_add_wall_segment(walls_root, "wallHalf.glb", Vector3(hx, 0.0, -2.0), 0.0, Vector3(1.0, 0.48, 1.0), true)

	# Subtle low divider between Open Floor Bullpen and SE Lounge along X = 5.0 (Z from 0.5 to 3.5)
	for hz in [1.0, 2.0, 3.0]:
		_add_wall_segment(walls_root, "wallHalf.glb", Vector3(5.0, 0.0, hz), PI * 0.5, Vector3(1.0, 0.42, 1.0), true)

	# Room Header Signs — one sign colour everywhere for a consistent theme
	var sign_color: Color = OfficeTheme.get_theme(theme_idx)["sign"]
	_add_room_sign(walls_root, "📊 CONFERENCE ROOM", Vector3(-9.0, 2.55, -9.6), sign_color)
	_add_room_sign(walls_root, "⭐ EXECUTIVE OFFICE", Vector3(-1.0, 2.55, -9.6), sign_color)
	_add_room_sign(walls_root, "☕ BREAK ROOM & KITCHEN", Vector3(8.0, 2.55, -9.6), sign_color)
	_add_room_sign(walls_root, "💻 OPEN FLOOR BULLPEN", Vector3(-5.5, 2.35, -1.6), sign_color)
	_add_room_sign(walls_root, "🛋️ STAFF LOUNGE", Vector3(9.0, 2.35, -1.6), sign_color)

	# Add 5 slowly rotating ceiling fans high up for ambient life
	var fan_positions := [
		Vector3(-9.0, 2.85, -6.0),
		Vector3(-1.0, 2.85, -6.0),
		Vector3(8.0, 2.85, -6.0),
		Vector3(-5.0, 2.85, 3.5),
		Vector3(9.0, 2.85, 3.5),
	]
	for fp in fan_positions:
		var fd := AssetCatalog.instantiate_centered_glb("ceilingFan.glb", 2.2)
		var fan_node: Node3D = fd["node"]
		fan_node.position = fp
		walls_root.add_child(fan_node)
		ceiling_fans.append(fan_node)

func _create_workstation(desk_type: String, pos: Vector3, rot_y: float = 0.0, with_partition: bool = true) -> void:
	var desk := place_furniture_item(desk_type, pos, rot_y, false)
	var forward := Vector3(sin(rot_y), 0.0, cos(rot_y))
	var chair_pos := pos + forward * (desk.footprint_size.z * 0.5 + 0.38)
	var chair := place_furniture_item("chair_desk", chair_pos, rot_y + PI, false)

	var d_num := _next_desk_number
	_next_desk_number += 1
	desk.desk_number = d_num
	chair.desk_number = d_num
	desk.paired_desk = desk
	chair.paired_desk = desk

	if with_partition:
		var part_pos := pos - forward * 0.54
		place_furniture_item("partition", part_pos, rot_y, false)

func _build_initial_office() -> void:
	# ========================================================================
	# 1. ROOM 1: NORTH-WEST CONFERENCE & STRATEGY ROOM (X: -13..-5, Z: -10..-2)
	# ========================================================================
	place_furniture_item("rug", Vector3(-9.0, 0.0, -5.8), 0.0, false)
	place_furniture_item("conference_table", Vector3(-9.0, 0.0, -5.8), 0.0, false)
	place_furniture_item("tv_presentation", Vector3(-9.0, 0.0, -9.2), 0.0, false)
	place_furniture_item("bookcase_wide", Vector3(-12.1, 0.0, -6.0), PI * 0.5, false)
	place_furniture_item("side_table", Vector3(-6.4, 0.0, -9.2), 0.0, false)
	place_furniture_item("potted_plant", Vector3(-12.1, 0.0, -9.0), 0.0, false)
	place_furniture_item("potted_plant", Vector3(-12.1, 0.0, -3.0), 0.0, false)
	place_furniture_item("floor_lamp", Vector3(-6.0, 0.0, -3.0), 0.0, false)

	# ========================================================================
	# 2. ROOM 2: NORTH-CENTER EXECUTIVE OFFICE (X: -5..+3, Z: -10..-2)
	# ========================================================================
	# Desk #1: Executive Desk for Worker #1 (Alex)
	_create_workstation("exec_desk", Vector3(-1.0, 0.0, -7.2), 0.0, false)
	place_furniture_item("rug_round", Vector3(-1.0, 0.0, -4.4), 0.0, false)
	place_furniture_item("lounge_chair", Vector3(-2.8, 0.0, -4.4), PI * 0.5, false)
	place_furniture_item("lounge_chair", Vector3(0.8, 0.0, -4.4), -PI * 0.5, false)
	place_furniture_item("coffee_table", Vector3(-1.0, 0.0, -4.4), 0.0, false)
	place_furniture_item("bookcase_wide", Vector3(-3.3, 0.0, -9.2), 0.0, false)
	place_furniture_item("bookcase", Vector3(1.6, 0.0, -9.2), 0.0, false)
	place_furniture_item("coat_rack", Vector3(-4.2, 0.0, -3.0), 0.0, false)
	place_furniture_item("floor_lamp", Vector3(2.1, 0.0, -8.8), 0.0, false)
	place_furniture_item("potted_plant", Vector3(2.1, 0.0, -3.0), 0.0, false)

	# ========================================================================
	# 3. ROOM 3: NORTH-EAST BREAK ROOM & KITCHENETTE (X: +3..+13, Z: -10..-2)
	# ========================================================================
	place_furniture_item("fridge", Vector3(4.3, 0.0, -9.1), 0.0, false)
	place_furniture_item("kitchen_counter", Vector3(6.2, 0.0, -9.1), 0.0, false)
	place_furniture_item("coffee_station", Vector3(8.2, 0.0, -9.1), 0.0, false)
	place_furniture_item("water_dispenser", Vector3(9.6, 0.0, -9.1), 0.0, false)
	place_furniture_item("kitchen_bar", Vector3(11.0, 0.0, -6.2), -PI * 0.5, false)
	place_furniture_item("round_table", Vector3(5.6, 0.0, -5.4), 0.0, false)
	place_furniture_item("round_table", Vector3(8.4, 0.0, -5.4), 0.0, false)
	place_furniture_item("trashcan", Vector3(3.8, 0.0, -7.2), 0.0, false)
	place_furniture_item("potted_plant", Vector3(12.1, 0.0, -9.0), 0.0, false)
	place_furniture_item("potted_plant", Vector3(12.1, 0.0, -3.0), 0.0, false)

	# ========================================================================
	# 4. MAIN OPEN FLOOR BULLPEN (WEST & CENTER, X: -13..+5, Z: -2..+10)
	# ========================================================================
	# Row 1 of Open Floor Workstations (Desks #2, #3, #4, #5)
	var row1_xs := [-9.8, -6.2, -2.6, 1.0]
	for i in range(row1_xs.size()):
		var dtype := "laptop_desk" if (i % 2 == 1) else "desk_pc"
		_create_workstation(dtype, Vector3(row1_xs[i], 0.0, 1.0), 0.0, true)

	# Row 2 of Open Floor Workstations (Desks #6, #7, #8)
	var row2_xs := [-9.8, -6.2, -2.6]
	for i in range(row2_xs.size()):
		var dtype := "desk_pc" if (i % 2 == 0) else "laptop_desk"
		_create_workstation(dtype, Vector3(row2_xs[i], 0.0, 5.4), 0.0, true)

	# Shared Open-Floor Equipment: Printer Hub, Filing Cabinets, Water Cooler #2, Reception
	place_furniture_item("filing_cabinet", Vector3(-12.1, 0.0, 0.2), PI * 0.5, false)
	place_furniture_item("printer_station", Vector3(-12.1, 0.0, 2.8), PI * 0.5, false)
	place_furniture_item("water_dispenser", Vector3(-12.1, 0.0, 5.2), PI * 0.5, false)
	place_furniture_item("filing_cabinet", Vector3(-12.1, 0.0, 7.0), PI * 0.5, false)
	place_furniture_item("storage_boxes", Vector3(-12.0, 0.0, 8.8), PI * 0.5, false)

	place_furniture_item("trashcan", Vector3(-8.0, 0.0, 0.9), 0.0, false)
	place_furniture_item("trashcan", Vector3(-0.8, 0.0, 0.9), 0.0, false)
	place_furniture_item("trashcan", Vector3(-4.4, 0.0, 5.3), 0.0, false)

	# Shared coffee nook; reception now has its own east-wing lobby.
	place_furniture_item("coffee_station", Vector3(3.8, 0.0, 5.4), -PI * 0.5, false)
	place_furniture_item("potted_plant", Vector3(-0.4, 0.0, 8.6), 0.0, false)
	place_furniture_item("potted_plant", Vector3(3.8, 0.0, 8.6), 0.0, false)

	# ========================================================================
	# 5. SOUTH-EAST OPEN LOUNGE & MEDIA ZONE (X: +5..+13, Z: -2..+10)
	# ========================================================================
	place_furniture_item("rug", Vector3(9.0, 0.0, 1.8), 0.0, false)
	place_furniture_item("lounge_sofa", Vector3(9.0, 0.0, 0.4), 0.0, false)
	place_furniture_item("lounge_chair", Vector3(11.4, 0.0, 1.8), -PI * 0.5, false)
	place_furniture_item("coffee_table", Vector3(9.0, 0.0, 1.8), 0.0, false)
	place_furniture_item("tv_presentation", Vector3(9.0, 0.0, 3.5), PI, false)
	place_furniture_item("speaker_tower", Vector3(7.7, 0.0, 3.5), PI, false)
	place_furniture_item("speaker_tower", Vector3(10.3, 0.0, 3.5), PI, false)
	place_furniture_item("floor_lamp", Vector3(6.6, 0.0, 0.4), 0.0, false)

	place_furniture_item("potted_plant", Vector3(6.2, 0.0, -0.8), 0.0, false)

	OfficeExpansion.furnish(self)
	OfficeArrival.furnish(self)

func place_furniture_item(item_id: String, world_pos: Vector3, rot_y: float = 0.0, rebake: bool = true) -> FurnitureItem:
	var item := FurnitureItem.new()
	item.setup(item_id)
	furniture_container.add_child(item)
	item.global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	item.global_rotation = Vector3(0.0, rot_y, 0.0)
	if rebake:
		_reconcile_desk_assignments()
		_request_navmesh_rebake()
	return item

func spawn_worker(spawn_pos: Vector3 = Vector3.INF) -> OfficeWorker:
	var idx := workers_container.get_child_count()
	var w_name: String = WORKER_NAMES[idx % WORKER_NAMES.size()]
	if idx >= WORKER_NAMES.size():
		w_name += " #" + str(idx + 1)

	var worker := OfficeWorker.new()
	worker.setup(self, idx, w_name, idx)
	workers_container.add_child(worker)

	if spawn_pos == Vector3.INF:
		# Spawn near their assigned desk if they have one, otherwise in the open bullpen
		if is_instance_valid(worker.assigned_chair):
			spawn_pos = worker.assigned_chair.get_chair_approach_pos() + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(0.3, 0.7))
		else:
			var angle := float(idx) * 1.15
			var radius := 0.9 + float(idx % 4) * 0.5
			spawn_pos = Vector3(cos(angle) * radius - 3.5, 0.0, sin(angle) * radius + 3.2)
	worker.global_position = spawn_pos
	if worker.status_label:
		worker.status_label.visible = editor_visible and show_worker_labels

	_refresh_ui()
	return worker

func _request_navmesh_rebake() -> void:
	if _nav_rebake_pending:
		return
	_nav_rebake_pending = true
	call_deferred("_do_navmesh_rebake")

func _do_navmesh_rebake() -> void:
	if not is_inside_tree() or not is_instance_valid(nav_region) or not nav_region.is_inside_tree():
		_nav_rebake_pending = false
		return
	if nav_region and not nav_region.is_baking():
		_nav_rebake_pending = false
		nav_region.bake_navigation_mesh()

func get_placement_issue(item: FurnitureItem, pos: Vector3, yaw: float, ignored_actor: Node3D = null) -> String:
	return FurniturePlacement.get_issue(self, item, pos, yaw, ignored_actor)

func finish_player_furniture_move(item: FurnitureItem) -> void:
	item.being_moved_by = null
	item.set_selected(item == selected_furniture)
	_reconcile_desk_assignments()
	_notify_workers_furniture_changed(item, false)
	_request_navmesh_rebake()
	_last_drag_bake_pos = Vector3.INF

# ============================================================================
# Strict Personal Desk & Chair Ownership Logic
# Every worker is assigned their own personal desk & chair and ONLY sits there.
# ============================================================================

func _desk_is_available(desk: FurnitureItem, requester: OfficeWorker = null) -> bool:
	return desks.desk_is_available(desk, requester)

func _find_nearby_desk(pos: Vector3, requester: OfficeWorker = null) -> FurnitureItem:
	return desks.find_nearby_desk(pos, requester)

func _reconcile_desk_assignments() -> void:
	desks.reconcile_desk_assignments()

func _claim_personal_chair(requester: OfficeWorker, chair: FurnitureItem, desk: FurnitureItem) -> FurnitureItem:
	return desks.claim_personal_chair(requester, chair, desk)

func get_or_assign_personal_chair(requester: OfficeWorker) -> FurnitureItem:
	return desks.get_or_assign_personal_chair(requester)

func _break_spot_available(item: FurnitureItem, requester: OfficeWorker) -> bool:
	return desks.break_spot_available(item, requester)

func _pick_spot(matches: Callable, requester: OfficeWorker = null) -> FurnitureItem:
	return desks.pick_spot(matches, requester)

func find_water_dispenser(requester: OfficeWorker = null) -> FurnitureItem:
	return desks.find_water_dispenser(requester)

func find_tagged_spot(tag: String, requester: OfficeWorker = null) -> FurnitureItem:
	return desks.find_tagged_spot(tag, requester)

func find_break_spot(requester: OfficeWorker = null) -> FurnitureItem:
	return desks.find_break_spot(requester)

func _unhandled_input(event: InputEvent) -> void:
	if not editor_visible:
		return
	if is_instance_valid(player):
		var dialogue = player.get("dialogue")
		var equipment = player.get("equipment")
		if (dialogue != null and dialogue.is_open) or (equipment != null and equipment.is_active()):
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event
		if ke.keycode == KEY_ESCAPE:
			cancel_current_action()
			return
		elif ke.keycode == KEY_R:
			rotate_active_or_selected()
			return
		elif ke.keycode == KEY_M:
			if edit_mode == EditMode.SELECT and is_instance_valid(selected_furniture):
				start_moving_selected()
			return
		elif ke.keycode == KEY_L:
			_on_toggle_lighting()
			return
		elif ke.keycode == KEY_DELETE or ke.keycode == KEY_BACKSPACE or ke.keycode == KEY_X:
			if edit_mode == EditMode.SELECT and is_instance_valid(selected_furniture):
				delete_selected_furniture()
			return
		else:
			# Hotkeys 1..9, 0 for quick furniture placement
			for item_def in AssetCatalog.get_catalog_items():
				var hk: String = item_def.get("hotkey", "")
				if hk != "" and OS.get_keycode_string(ke.keycode) == hk:
					start_placing_catalog_item(item_def["id"])
					return

	elif event is InputEventMouseMotion:
		if edit_mode == EditMode.PLACE_NEW or edit_mode == EditMode.MOVE_EXISTING:
			_update_preview_position_from_mouse()

	elif event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if edit_mode != EditMode.SELECT:
				cancel_current_action()

func _process(delta: float) -> void:
	if edit_mode != EditMode.SELECT:
		_update_preview_position_from_mouse()
	if is_instance_valid(player) and is_instance_valid(player.grabbed_furniture):
		_drag_rebake_timer += delta
		if _drag_rebake_timer >= 0.5:
			_drag_rebake_timer = 0.0
			var pos: Vector3 = player.grabbed_furniture.global_position
			if pos.distance_to(_last_drag_bake_pos) > 0.15:
				_last_drag_bake_pos = pos
				_request_navmesh_rebake()
	# Spin ceiling fans smoothly for ambient life
	for fan in ceiling_fans:
		if is_instance_valid(fan):
			fan.rotation.y = fmod(fan.rotation.y + delta * 1.8, TAU)

	_ui_refresh_timer += delta / maxf(Engine.time_scale, 0.1)
	if _ui_refresh_timer >= 0.25:
		_ui_refresh_timer = 0.0
		_refresh_ui()

func _get_mouse_floor_hit() -> Variant:
	if iso_camera == null or iso_camera.camera == null:
		return null
	var cam := iso_camera.camera
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir := cam.project_ray_normal(mouse_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return null
	var p: Vector3 = hit
	p.x = snappedf(p.x, GRID_SNAP)
	p.z = snappedf(p.z, GRID_SNAP)
	p.y = 0.0
	return p

func _raycast_furniture_at_mouse() -> FurnitureItem:
	if iso_camera == null or iso_camera.camera == null:
		return null
	var cam := iso_camera.camera
	var mouse_pos := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse_pos)
	var to := from + cam.project_ray_normal(mouse_pos) * 140.0

	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var collider = result.get("collider")
	if collider is FurnitureItem:
		return collider
	return null

func _update_preview_position_from_mouse() -> void:
	var hit = _get_mouse_floor_hit()
	if hit == null:
		placement_issue = "Point at the office floor."
		return
	var pos: Vector3 = hit
	if edit_mode == EditMode.PLACE_NEW and is_instance_valid(preview_furniture):
		preview_furniture.global_position = pos
		preview_furniture.global_rotation = Vector3(0.0, preview_rot_y, 0.0)
	elif edit_mode == EditMode.MOVE_EXISTING and is_instance_valid(selected_furniture):
		selected_furniture.global_position = pos
		selected_furniture.global_rotation = Vector3(0.0, preview_rot_y, 0.0)
	var item := preview_furniture if edit_mode == EditMode.PLACE_NEW else selected_furniture
	if is_instance_valid(item):
		placement_issue = get_placement_issue(item, pos, preview_rot_y)
		item.set_preview_mode(true, placement_issue.is_empty())

func _handle_left_click() -> void:
	match edit_mode:
		EditMode.SELECT:
			var hit_item := _raycast_furniture_at_mouse()
			select_furniture(hit_item)

		EditMode.PLACE_NEW:
			_update_preview_position_from_mouse()
			if not placement_issue.is_empty():
				_refresh_ui()
				return
			var hit = _get_mouse_floor_hit()
			if hit != null and placing_item_id != "":
				var new_item := place_furniture_item(placing_item_id, hit, preview_rot_y, true)
				if not Input.is_key_pressed(KEY_SHIFT):
					_clear_preview()
					edit_mode = EditMode.SELECT
					select_furniture(new_item)
				_refresh_ui()

		EditMode.MOVE_EXISTING:
			_update_preview_position_from_mouse()
			if not placement_issue.is_empty():
				_refresh_ui()
				return
			if is_instance_valid(selected_furniture):
				selected_furniture.set_preview_mode(false)
				selected_furniture.set_selected(true)
				_reconcile_desk_assignments()
				_notify_workers_furniture_changed(selected_furniture, false)
				_request_navmesh_rebake()
			edit_mode = EditMode.SELECT
			_refresh_ui()

func select_furniture(item: FurnitureItem) -> void:
	if is_instance_valid(selected_furniture):
		selected_furniture.set_selected(false)
	selected_furniture = item
	if is_instance_valid(selected_furniture):
		selected_furniture.set_selected(true)
	_refresh_ui()

func start_placing_catalog_item(item_id: String) -> void:
	if is_instance_valid(player):
		var dialogue = player.get("dialogue")
		if dialogue != null:
			dialogue.close()
		var equipment = player.get("equipment")
		if equipment != null:
			equipment.cancel()
		player.release_furniture()
	cancel_current_action()
	edit_mode = EditMode.PLACE_NEW
	placing_item_id = item_id
	preview_rot_y = float(AssetCatalog.get_item_def(item_id).get("place_rot_y", 0.0))

	preview_furniture = FurnitureItem.new()
	preview_furniture.setup(item_id)
	preview_furniture.set_preview_mode(true, true)
	add_child(preview_furniture)
	_update_preview_position_from_mouse()
	_refresh_ui()

func start_moving_selected() -> void:
	if not is_instance_valid(selected_furniture):
		return
	if _editing_blocked_by_activity():
		return
	if _selected_is_occupied():
		return
	if is_instance_valid(player):
		player.release_furniture()
	if edit_mode != EditMode.SELECT:
		cancel_current_action()
	edit_mode = EditMode.MOVE_EXISTING
	move_original_pos = selected_furniture.global_position
	move_original_rot_y = selected_furniture.global_rotation.y
	preview_rot_y = move_original_rot_y
	selected_furniture.set_selected(false)
	selected_furniture.set_preview_mode(true, true)
	_notify_workers_furniture_changed(selected_furniture, false)
	_update_preview_position_from_mouse()
	_refresh_ui()

func rotate_active_or_selected() -> void:
	if _editing_blocked_by_activity():
		return
	if edit_mode == EditMode.PLACE_NEW and is_instance_valid(preview_furniture):
		preview_rot_y = fmod(preview_rot_y + PI * 0.5, TAU)
		preview_furniture.global_rotation.y = preview_rot_y
	elif edit_mode == EditMode.MOVE_EXISTING and is_instance_valid(selected_furniture):
		preview_rot_y = fmod(preview_rot_y + PI * 0.5, TAU)
		selected_furniture.global_rotation.y = preview_rot_y
	elif edit_mode == EditMode.SELECT and is_instance_valid(selected_furniture):
		if _selected_is_occupied():
			return
		if is_instance_valid(selected_furniture.being_moved_by):
			return
		var yaw := fmod(selected_furniture.global_rotation.y + PI * 0.5, TAU)
		placement_issue = get_placement_issue(selected_furniture, selected_furniture.global_position, yaw)
		if not placement_issue.is_empty():
			_refresh_ui()
			return
		selected_furniture.global_rotation.y = yaw
		_notify_workers_furniture_changed(selected_furniture, false)
		_request_navmesh_rebake()
	if edit_mode != EditMode.SELECT:
		_update_preview_position_from_mouse()
	_refresh_ui()

func delete_selected_furniture() -> void:
	if not is_instance_valid(selected_furniture):
		return
	if _editing_blocked_by_activity():
		return
	if _selected_is_occupied():
		return
	if is_instance_valid(player):
		player.release_furniture()
	var to_del := selected_furniture
	selected_furniture = null
	edit_mode = EditMode.SELECT
	_notify_workers_furniture_changed(to_del, true)
	to_del.queue_free()
	call_deferred("_reconcile_desk_assignments")
	_request_navmesh_rebake()
	_refresh_ui()

func _editing_blocked_by_activity() -> bool:
	if not is_instance_valid(player):
		return false
	var dialogue = player.get("dialogue")
	var equipment = player.get("equipment")
	if (dialogue != null and dialogue.is_open) or (equipment != null and equipment.is_active()):
		placement_issue = "Finish or close your current activity before changing the office."
		_refresh_ui()
		return true
	return false

func _selected_is_occupied() -> bool:
	var occupied := selected_furniture.is_in_use()
	if is_instance_valid(player) and player.seated and player.sitting_chair == selected_furniture:
		occupied = true
	if occupied:
		placement_issue = "Wait until this furniture is no longer in use."
		_refresh_ui()
	return occupied

func cancel_current_action() -> void:
	placement_issue = ""
	if edit_mode == EditMode.PLACE_NEW:
		_clear_preview()
		edit_mode = EditMode.SELECT
	elif edit_mode == EditMode.MOVE_EXISTING:
		if is_instance_valid(selected_furniture):
			selected_furniture.global_position = move_original_pos
			selected_furniture.global_rotation.y = move_original_rot_y
			selected_furniture.set_preview_mode(false)
			selected_furniture.set_selected(true)
			_request_navmesh_rebake()
		edit_mode = EditMode.SELECT
	else:
		select_furniture(null)
	_refresh_ui()

func _clear_preview() -> void:
	if is_instance_valid(preview_furniture):
		preview_furniture.queue_free()
	preview_furniture = null
	placing_item_id = ""

func _notify_workers_furniture_changed(item: FurnitureItem, was_deleted: bool) -> void:
	for w in workers_container.get_children():
		if w is OfficeWorker:
			w.on_furniture_removed_or_moved(item, was_deleted)

# ============================================================================
# User Interface (Top HUD, Left Worker Roster, Right Inspector, Bottom Catalog)
# ============================================================================

func _make_panel_style(bg: Color, border: Color = Color(0.28, 0.34, 0.44, 0.85)) -> StyleBoxFlat:
	return editor_ui.make_panel_style(bg, border)

func _setup_ui() -> void:
	editor_ui.setup_ui()

func _setup_floor_controls(parent: VBoxContainer) -> void:
	editor_ui.setup_floor_controls(parent)

func set_editor_visible(enabled: bool) -> void:
	editor_ui.set_editor_visible(enabled)

func _refresh_ui() -> void:
	editor_ui.refresh_ui()
