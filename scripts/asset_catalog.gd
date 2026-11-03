class_name AssetCatalog
extends RefCounted

const FURNITURE_SCALE := 2.0
const GLTF_DIR := "res://kenney_furniture-kit/Models/GLTF format/"

static var _scene_cache: Dictionary = {}
static var _aabb_cache: Dictionary = {}
static var _shape_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _toned_mat_cache: Dictionary = {}
static var _shared_anim_library: AnimationLibrary = null
static var _shared_state_machine: AnimationNodeStateMachine = null
static var _catalog_cache: Array[Dictionary] = []
static var _catalog_index: Dictionary = {}

# Shared capability profiles: every object in a profile gets identical
# behaviour. Adding furniture = one catalog entry + one profile name below;
# no consumer (equipment, cup, seating, NPC breaks) names individual ids.
const PROFILES := {
	"workstation": {"equipment": ["eq_report"], "equipment_group": "workstation"},
	"printer": {"equipment": ["eq_collect", "eq_print"], "equipment_group": "printer"},
	"archive": {"equipment": ["eq_file", "eq_retrieve"], "equipment_group": "archive"},
	"coffee": {"equipment": ["eq_drink_coffee", "eq_coffee"], "equipment_group": "coffee"},
	"fridge": {"equipment": ["eq_eat", "eq_snack"], "equipment_group": "fridge"},
	"kitchen": {"equipment": ["eq_meal", "eq_eat"], "equipment_group": "kitchen"},
	"collab": {"equipment": ["eq_review", "eq_present"], "equipment_group": "collab"},
	"present": {"equipment": ["eq_present"], "equipment_group": "present"},
	"lounge_seat": {"equipment": ["eq_relax"], "equipment_group": "lounge", "seat": "lounge"},
	"desk_chair": {"seat": "desk", "place_rot_y": PI},
	"toilet": {"equipment": ["eq_toilet"], "equipment_group": "toilet"},
	"shower": {"equipment": ["eq_shower"], "equipment_group": "shower"},
	"washbasin": {"equipment": ["eq_wash_hands"], "equipment_group": "washbasin"},
}
# Per-item data that cannot be derived from flags alone (which visual child
# is a cup surface, which profile applies). Data only — no behaviour here.
const ITEM_CAPS := {
	"desk_pc": {"profile": "workstation", "cup_surfaces": [0]},
	"laptop_desk": {"profile": "workstation", "cup_surfaces": [0]},
	"exec_desk": {"profile": "workstation", "cup_surfaces": [0]},
	"desk_plain": {"profile": "workstation", "cup_surfaces": [0]},
	"computer_set": {"profile": "workstation", "player_movable": false, "soft_collision": true},
	"chair_desk": {"profile": "desk_chair"},
	"water_dispenser": {"break_tags": ["water", "break"]},
	"coffee_station": {"profile": "coffee"},
	"printer_station": {"profile": "printer"},
	"filing_cabinet": {"profile": "archive"},
	"bookcase": {"profile": "archive"},
	"bookcase_wide": {"profile": "archive"},
	"fridge": {"profile": "fridge"},
	"kitchen_counter": {"profile": "kitchen", "cup_surfaces": [1]},
	"kitchen_bar": {"profile": "kitchen", "cup_surfaces": [0, 1]},
	"conference_table": {"profile": "collab", "cup_surfaces": [0, 1]},
	"round_table": {"profile": "collab", "cup_surfaces": [0], "cup_round": true},
	"tv_presentation": {"profile": "present"},
	"lounge_sofa": {"profile": "lounge_seat"},
	"lounge_chair": {"profile": "lounge_seat"},
	"reception_desk": {"cup_surfaces": [0, 1]},
	"coffee_table": {"cup_surfaces": [0]},
	"side_table": {"cup_surfaces": [0]},
	"rug": {"player_movable": false, "soft_collision": true},
	"rug_round": {"player_movable": false, "soft_collision": true},
	"wall_half_divider": {"player_movable": false},
	"tech_workbench": {"profile": "workstation"},
	"glass_table": {"profile": "collab", "cup_surfaces": [0]},
	"whiteboard": {"profile": "present"},
	"toilet": {"profile": "toilet"},
	"shower": {"profile": "shower"},
	"bathroom_vanity": {"profile": "washbasin"},
}

static func _normalize_def(def: Dictionary) -> Dictionary:
	var debris := DestructionProfile.for_item(String(def["id"]))
	def["debris_family"] = debris.family_id
	def["breakable"] = debris.breakable
	def["seat"] = def.get("seat", "desk" if def.get("is_chair", false) else "")
	def["equipment"] = def.get("equipment", [])
	def["equipment_group"] = def.get("equipment_group", "")
	def["cup_surfaces"] = def.get("cup_surfaces", [])
	def["cup_round"] = def.get("cup_round", false)
	def["place_rot_y"] = def.get("place_rot_y", 0.0)
	def["player_movable"] = def.get("player_movable", not def.get("is_rug", false))
	def["soft_collision"] = def.get("soft_collision", def.get("is_rug", false) or def.get("is_computer", false))
	var tags: Array = []
	var room_tag: String = def.get("room_tag", "")
	if room_tag != "":
		tags.append(room_tag)
	for tag in def.get("break_tags", []):
		if tag not in tags:
			tags.append(tag)
	def["break_tags"] = tags
	return def

static func _catalog() -> Array[Dictionary]:
	if not _catalog_cache.is_empty():
		return _catalog_cache
	for raw in _raw_catalog_items():
		var def: Dictionary = raw.duplicate(true)
		var caps: Dictionary = ITEM_CAPS.get(def["id"], {})
		for key in caps:
			if key == "profile":
				for profile_key in PROFILES[caps[key]]:
					def[profile_key] = PROFILES[caps[key]][profile_key]
			else:
				def[key] = caps[key]
		_catalog_cache.append(_normalize_def(def))
		_catalog_index[def["id"]] = _catalog_cache[_catalog_cache.size() - 1]
	return _catalog_cache

# Definitions for placeable office furniture & room objects
static func get_catalog_items() -> Array[Dictionary]:
	return _catalog().duplicate(true)

static func _raw_catalog_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{
			"id": "desk_pc",
			"title": "Workstation Desk (PC)",
			"short": "Desk+PC",
			"hotkey": "1",
			"is_desk": true,
			"has_pc": true,
			"nav_obstacle": true
		},
		{
			"id": "laptop_desk",
			"title": "Laptop Workstation",
			"short": "Laptop Desk",
			"hotkey": "2",
			"is_desk": true,
			"has_pc": true,
			"nav_obstacle": true
		},
		{
			"id": "exec_desk",
			"title": "Executive Corner Desk",
			"short": "Exec Desk",
			"hotkey": "3",
			"is_desk": true,
			"has_pc": true,
			"nav_obstacle": true
		},
		{
			"id": "chair_desk",
			"title": "Office Desk Chair",
			"short": "Desk Chair",
			"hotkey": "4",
			"is_chair": true,
			"nav_obstacle": true
		},
		{
			"id": "partition",
			"title": "Cubicle Partition",
			"short": "Partition",
			"hotkey": "5",
			"nav_obstacle": true
		},
		{
			"id": "water_dispenser",
			"title": "Water Dispenser",
			"short": "Water Cooler",
			"hotkey": "6",
			"is_water_dispenser": true,
			"room_tag": "break",
			"nav_obstacle": true
		},
		{
			"id": "coffee_station",
			"title": "Coffee Espresso Bar",
			"short": "Coffee Bar",
			"hotkey": "7",
			"is_break_spot": true,
			"room_tag": "kitchen",
			"nav_obstacle": true
		},
		{
			"id": "printer_station",
			"title": "Printer & Copier Hub",
			"short": "Printer Hub",
			"hotkey": "8",
			"is_break_spot": true,
			"room_tag": "errand",
			"nav_obstacle": true
		},
		{
			"id": "conference_table",
			"title": "Conference Table",
			"short": "Conf Table",
			"hotkey": "9",
			"is_break_spot": true,
			"room_tag": "conference",
			"nav_obstacle": true
		},
		{
			"id": "lounge_sofa",
			"title": "Lounge Sofa",
			"short": "Sofa",
			"hotkey": "0",
			"is_break_spot": true,
			"room_tag": "lounge",
			"nav_obstacle": true
		},
		{
			"id": "lounge_chair",
			"title": "Designer Lounge Chair",
			"short": "Armchair",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "lounge",
			"nav_obstacle": true
		},
		{
			"id": "tv_presentation",
			"title": "Media / Presentation TV",
			"short": "TV Screen",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "conference",
			"nav_obstacle": true
		},
		{
			"id": "fridge",
			"title": "Breakroom Fridge",
			"short": "Fridge",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "kitchen",
			"nav_obstacle": true
		},
		{
			"id": "kitchen_counter",
			"title": "Kitchen Sink & Microwave",
			"short": "Kitchenette",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "kitchen",
			"nav_obstacle": true
		},
		{
			"id": "kitchen_bar",
			"title": "Pantry Bar & Stools",
			"short": "Pantry Bar",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "kitchen",
			"nav_obstacle": true
		},
		{
			"id": "round_table",
			"title": "Round Collaboration Table",
			"short": "Round Table",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "lounge",
			"nav_obstacle": true
		},
		{
			"id": "reception_desk",
			"title": "Reception Counter",
			"short": "Reception",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "errand",
			"nav_obstacle": true
		},
		{
			"id": "filing_cabinet",
			"title": "Filing Cabinet",
			"short": "Filing Cab",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "errand",
			"nav_obstacle": true
		},
		{
			"id": "bookcase",
			"title": "Open Bookcase",
			"short": "Bookcase",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "lounge",
			"nav_obstacle": true
		},
		{
			"id": "bookcase_wide",
			"title": "Wide Archive Shelf",
			"short": "Wide Shelf",
			"hotkey": "",
			"is_break_spot": true,
			"room_tag": "lounge",
			"nav_obstacle": true
		},
		{
			"id": "potted_plant",
			"title": "Indoor Potted Plant",
			"short": "Plant",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "coffee_table",
			"title": "Coffee Table",
			"short": "Coffee Tbl",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "side_table",
			"title": "Credenza Side Table",
			"short": "Credenza",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "floor_lamp",
			"title": "Warm Floor Lamp",
			"short": "Lamp",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "coat_rack",
			"title": "Standing Coat Rack",
			"short": "Coat Rack",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "speaker_tower",
			"title": "Studio Speaker Tower",
			"short": "Speaker",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "storage_boxes",
			"title": "Archive Storage Boxes",
			"short": "Boxes",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "trashcan",
			"title": "Office Trash Can",
			"short": "Trash",
			"hotkey": "",
			"nav_obstacle": true
		},
		{
			"id": "rug",
			"title": "Area Rug (Rect)",
			"short": "Rug",
			"hotkey": "",
			"is_rug": true,
			"nav_obstacle": false
		},
		{
			"id": "rug_round",
			"title": "Area Rug (Round)",
			"short": "Round Rug",
			"hotkey": "",
			"is_rug": true,
			"nav_obstacle": false
		},
		{
			"id": "desk_plain",
			"title": "Plain Desk",
			"short": "Plain Desk",
			"hotkey": "",
			"is_desk": true,
			"has_pc": false,
			"nav_obstacle": true
		},
		{
			"id": "computer_set",
			"title": "Computer Set",
			"short": "Computer",
			"hotkey": "",
			"is_computer": true,
			"nav_obstacle": false
		},
		{
			"id": "wall_half_divider",
			"title": "Low Room Divider Wall",
			"short": "Half Wall",
			"hotkey": "",
			"nav_obstacle": true
		}
	]

	items.append_array(ModernAssets.catalog_items())
	return items

static func get_item_def(item_id: String) -> Dictionary:
	_catalog()
	if _catalog_index.has(item_id):
		return (_catalog_index[item_id] as Dictionary).duplicate(true)
	return _normalize_def({
		"id": item_id,
		"title": item_id.capitalize(),
		"short": item_id,
		"hotkey": "",
		"nav_obstacle": true
	})

static func load_gltf_scene(file_name: String) -> PackedScene:
	if not _scene_cache.has(file_name):
		var path := GLTF_DIR + file_name
		_scene_cache[file_name] = load(path)
	return _scene_cache[file_name]

static func instantiate_centered_glb(file_name: String, scale_factor: float = FURNITURE_SCALE) -> Dictionary:
	var ps := load_gltf_scene(file_name)
	var inst: Node3D = ps.instantiate()
	_tone_node_materials(inst)

	var raw_aabb: AABB
	if _aabb_cache.has(file_name):
		raw_aabb = _aabb_cache[file_name]
	else:
		raw_aabb = compute_node_aabb(inst)
		_aabb_cache[file_name] = raw_aabb

	var wrapper := Node3D.new()
	wrapper.name = file_name.get_basename()
	inst.scale = Vector3.ONE * scale_factor
	# Center horizontally on X and Z while keeping bottom on Y = 0
	var cx := (raw_aabb.position.x + raw_aabb.size.x * 0.5) * scale_factor
	var cz := (raw_aabb.position.z + raw_aabb.size.z * 0.5) * scale_factor
	var by := raw_aabb.position.y * scale_factor
	inst.position = Vector3(-cx, -by, -cz)
	wrapper.add_child(inst)

	var scaled_size := raw_aabb.size * scale_factor
	return {
		"node": wrapper,
		"size": scaled_size
	}

# Tone down overly-bright Kenney GLTF vertex/surface albedos (which default to 0.95-1.0)
# so surfaces look rich, grounded, and never blown out under indoor lighting.
static func _tone_node_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh and not node.get_meta("preserve_material", false):
		var mi: MeshInstance3D = node
		var surf_count := mi.mesh.get_surface_count()
		for s in range(surf_count):
			var orig_mat := mi.mesh.surface_get_material(s)
			if orig_mat is BaseMaterial3D:
				var bm: BaseMaterial3D = orig_mat
				var key := "%s_%s" % [bm.resource_name, bm.albedo_color.to_html()]
				if not _toned_mat_cache.has(key):
					var new_mat := StandardMaterial3D.new()
					var col := bm.albedo_color
					if bm.resource_name == "_defaultMat" or (col.r > 0.92 and col.g > 0.92 and col.b > 0.92):
						# Warm white walls/surfaces — bright and airy, same tone everywhere
						new_mat.albedo_color = Color(0.93, 0.90, 0.84, col.a)
						new_mat.roughness = 0.85
					elif bm.resource_name == "wood":
						# Light oak wood, matching the single-colour floor theme
						new_mat.albedo_color = Color(0.78, 0.65, 0.48, col.a)
						new_mat.roughness = 0.78
					elif bm.resource_name == "glass" or col.a < 0.95:
						new_mat.albedo_color = Color(col.r * 0.75, col.g * 0.78, col.b * 0.82, clampf(col.a, 0.35, 0.65))
						new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						new_mat.roughness = 0.25
					else:
						new_mat.albedo_color = Color(col.r * 0.88, col.g * 0.88, col.b * 0.88, col.a)
						new_mat.roughness = 0.82
					_toned_mat_cache[key] = new_mat
				mi.set_surface_override_material(s, _toned_mat_cache[key])
	for c in node.get_children():
		_tone_node_materials(c)

static func _make_screen_glow(w: float, h: float, color: Color = Color(0.55, 0.68, 0.60)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(w, h, 0.015)
	mi.mesh = qm
	var key := "screen_glow_" + color.to_html()
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.55
		mat.roughness = 0.3
		_material_cache[key] = mat
	mi.material_override = _material_cache[key]
	return mi

# Add one GLB part to a furniture visual root; returns its instantiate data.
static func _part(root: Node3D, file_name: String, pos := Vector3.ZERO, rot_y := 0.0, scale_factor: float = FURNITURE_SCALE) -> Dictionary:
	var data := instantiate_centered_glb(file_name, scale_factor)
	var node: Node3D = data["node"]
	node.position = pos
	node.rotation.y = rot_y
	root.add_child(node)
	return data

static func build_furniture_visual(item_id: String) -> Dictionary:
	for entry in ModernAssets.ITEMS:
		if entry[0] == item_id:
			return ModernAssets.build(item_id)
	var root := Node3D.new()
	root.name = "VisualRoot"
	var size := Vector3(1.0, 1.0, 1.0)

	match item_id:
		"desk_pc":
			var desk_data := _part(root, "desk.glb")
			size = desk_data["size"]
			var top_y: float = size.y
			_part(root, "computerScreen.glb", Vector3(0.0, top_y, -0.16))
			var glow := _make_screen_glow(0.42, 0.26, Color(0.20, 0.52, 0.82))
			glow.position = Vector3(0.0, top_y + 0.31, -0.12)
			root.add_child(glow)
			_part(root, "computerKeyboard.glb", Vector3(-0.06, top_y, 0.16))
			_part(root, "computerMouse.glb", Vector3(0.32, top_y, 0.16))
			_part(root, "plantSmall1.glb", Vector3(-0.50, top_y, -0.16))

		"laptop_desk":
			var desk_data := _part(root, "desk.glb")
			size = desk_data["size"]
			var top_y: float = size.y
			_part(root, "laptop.glb", Vector3(-0.04, top_y, 0.04))
			_part(root, "books.glb", Vector3(0.44, top_y, -0.14))
			_part(root, "plantSmall2.glb", Vector3(-0.48, top_y, -0.15))

		"exec_desk":
			var desk_data := instantiate_centered_glb("desk.glb")
			var d_node: Node3D = desk_data["node"]
			d_node.scale = Vector3(1.22, 1.0, 1.12)
			root.add_child(d_node)
			size = Vector3(desk_data["size"].x * 1.22, desk_data["size"].y, desk_data["size"].z * 1.12)
			var top_y: float = size.y
			for sx in [-0.26, 0.26]:
				_part(root, "computerScreen.glb", Vector3(sx, top_y, -0.18), -sx * 0.35)
			_part(root, "computerKeyboard.glb", Vector3(-0.04, top_y, 0.18))
			_part(root, "computerMouse.glb", Vector3(0.32, top_y, 0.18))
			_part(root, "lampRoundTable.glb", Vector3(-0.66, top_y, -0.18))
			_part(root, "books.glb", Vector3(0.64, top_y, -0.16))

		"desk_plain":
			size = _part(root, "desk.glb")["size"]

		"computer_set":
			_part(root, "computerScreen.glb", Vector3(0.0, 0.0, -0.14))
			_part(root, "computerKeyboard.glb", Vector3(-0.05, 0.0, 0.14))
			_part(root, "computerMouse.glb", Vector3(0.30, 0.0, 0.14))
			size = Vector3(0.85, 0.60, 0.55)

		"chair_desk":
			var chair_data := instantiate_centered_glb("chairDesk.glb")
			root.add_child(chair_data["node"])
			size = chair_data["size"]

		"partition":
			var p1 := instantiate_centered_glb("paneling.glb")
			var p2 := instantiate_centered_glb("paneling.glb")
			var w: float = p1["size"].x
			p1["node"].position = Vector3(-w * 0.5, 0.0, 0.0)
			p2["node"].position = Vector3(w * 0.5, 0.0, 0.0)
			p1["node"].scale.y = 1.15
			p2["node"].scale.y = 1.15
			root.add_child(p1["node"])
			root.add_child(p2["node"])
			size = Vector3(w * 2.0, p1["size"].y * 1.15, maxf(p1["size"].z, 0.12))

		"wall_half_divider":
			var w1 := instantiate_centered_glb("wallHalf.glb")
			var w2 := instantiate_centered_glb("wallHalf.glb")
			w1["node"].position = Vector3(-0.5, 0.0, 0.0)
			w2["node"].position = Vector3(0.5, 0.0, 0.0)
			w1["node"].scale.y = 0.52
			w2["node"].scale.y = 0.52
			root.add_child(w1["node"])
			root.add_child(w2["node"])
			size = Vector3(2.0, 1.35, 0.16)

		"water_dispenser":
			var base_data := instantiate_centered_glb("kitchenFridgeSmall.glb", 1.35)
			var base_node: Node3D = base_data["node"]
			base_node.scale = Vector3(0.85, 1.35, 0.95)
			root.add_child(base_node)
			var base_top_y: float = base_data["size"].y * 1.35

			var tap_data := instantiate_centered_glb("kitchenCoffeeMachine.glb", 1.25)
			var tap_node: Node3D = tap_data["node"]
			tap_node.position = Vector3(0.0, base_top_y - 0.02, 0.02)
			root.add_child(tap_node)

			var jug_data := instantiate_centered_glb("trashcan.glb", 1.35)
			var jug_node: Node3D = jug_data["node"]
			jug_node.position = Vector3(0.0, base_top_y + tap_data["size"].y * 0.88, -0.02)
			apply_material_recursive(jug_node, get_shared_material("water_jug", Color(0.22, 0.58, 0.82, 1.0), 0.25))
			root.add_child(jug_node)
			size = Vector3(0.65, 1.65, 0.65)

		"coffee_station":
			var cab_data := instantiate_centered_glb("kitchenCabinet.glb")
			root.add_child(cab_data["node"])
			var cab_size: Vector3 = cab_data["size"]
			var cm_data := instantiate_centered_glb("kitchenCoffeeMachine.glb")
			var cm_node: Node3D = cm_data["node"]
			cm_node.position = Vector3(-0.14, cab_size.y, 0.05)
			root.add_child(cm_node)
			var toaster_data := instantiate_centered_glb("toaster.glb")
			toaster_data["node"].position = Vector3(0.20, cab_size.y, 0.05)
			root.add_child(toaster_data["node"])
			size = Vector3(cab_size.x, cab_size.y + cm_data["size"].y, cab_size.z)

		"fridge":
			var fr_data := instantiate_centered_glb("kitchenFridgeLarge.glb")
			root.add_child(fr_data["node"])
			size = fr_data["size"]

		"kitchen_counter":
			var sink_data := instantiate_centered_glb("kitchenSink.glb")
			var cab_data := instantiate_centered_glb("kitchenCabinetDrawer.glb")
			var w: float = sink_data["size"].x
			sink_data["node"].position = Vector3(-w * 0.5, 0.0, 0.0)
			cab_data["node"].position = Vector3(w * 0.5, 0.0, 0.0)
			root.add_child(sink_data["node"])
			root.add_child(cab_data["node"])
			var top_y: float = cab_data["size"].y
			var mw_data := instantiate_centered_glb("kitchenMicrowave.glb")
			mw_data["node"].position = Vector3(w * 0.5, top_y, -0.05)
			root.add_child(mw_data["node"])
			size = Vector3(w * 2.0, top_y + mw_data["size"].y, sink_data["size"].z)

		"kitchen_bar":
			var b1 := instantiate_centered_glb("kitchenBar.glb")
			var b2 := instantiate_centered_glb("kitchenBar.glb")
			var bw: float = b1["size"].x
			b1["node"].position = Vector3(-bw * 0.5, 0.0, 0.0)
			b2["node"].position = Vector3(bw * 0.5, 0.0, 0.0)
			root.add_child(b1["node"])
			root.add_child(b2["node"])
			var blender := instantiate_centered_glb("kitchenBlender.glb")
			blender["node"].position = Vector3(-0.35, b1["size"].y, 0.0)
			root.add_child(blender["node"])
			for sx in [-0.42, 0.42]:
				var st := instantiate_centered_glb("stoolBar.glb")
				st["node"].position = Vector3(sx, 0.0, 0.52)
				root.add_child(st["node"])
			size = Vector3(bw * 2.0, b1["size"].y + 0.3, 1.05)

		"printer_station":
			var c1 := instantiate_centered_glb("kitchenCabinetDrawer.glb")
			var c2 := instantiate_centered_glb("kitchenCabinet.glb")
			var cw: float = c1["size"].x
			c1["node"].position = Vector3(-cw * 0.5, 0.0, 0.0)
			c2["node"].position = Vector3(cw * 0.5, 0.0, 0.0)
			root.add_child(c1["node"])
			root.add_child(c2["node"])
			var top_y: float = c1["size"].y
			# Copier/scanner unit on top
			var copier := instantiate_centered_glb("kitchenMicrowave.glb", 2.3)
			copier["node"].position = Vector3(-cw * 0.45, top_y, 0.0)
			root.add_child(copier["node"])
			var books := instantiate_centered_glb("books.glb")
			books["node"].position = Vector3(cw * 0.45, top_y, 0.0)
			root.add_child(books["node"])
			size = Vector3(cw * 2.0, top_y + copier["size"].y, c1["size"].z)

		"conference_table":
			var t1 := instantiate_centered_glb("tableCrossCloth.glb")
			var t2 := instantiate_centered_glb("tableCrossCloth.glb")
			var tw: float = t1["size"].x
			t1["node"].position = Vector3(-tw * 0.5, 0.0, 0.0)
			t2["node"].position = Vector3(tw * 0.5, 0.0, 0.0)
			root.add_child(t1["node"])
			root.add_child(t2["node"])
			var top_y: float = t1["size"].y
			for lx in [-0.85, 0.75]:
				var lap := instantiate_centered_glb("laptop.glb")
				lap["node"].position = Vector3(lx, top_y, 0.12)
				lap["node"].rotation.y = PI
				root.add_child(lap["node"])
			var plant := instantiate_centered_glb("plantSmall3.glb")
			plant["node"].position = Vector3(0.0, top_y, 0.0)
			root.add_child(plant["node"])
			# Add 4 conference chairs tucked smoothly around the table
			for cx in [-0.85, 0.85]:
				var ch_n := instantiate_centered_glb("chairModernCushion.glb")
				ch_n["node"].position = Vector3(cx, 0.0, -0.68)
				ch_n["node"].rotation.y = 0.0
				root.add_child(ch_n["node"])
				var ch_s := instantiate_centered_glb("chairModernCushion.glb")
				ch_s["node"].position = Vector3(cx, 0.0, 0.68)
				ch_s["node"].rotation.y = PI
				root.add_child(ch_s["node"])
			size = Vector3(tw * 2.0, top_y + 0.35, 1.75)

		"reception_desk":
			var b1 := instantiate_centered_glb("kitchenBar.glb")
			var b2 := instantiate_centered_glb("kitchenBar.glb")
			var bw: float = b1["size"].x
			b1["node"].position = Vector3(-bw * 0.5, 0.0, 0.0)
			b2["node"].position = Vector3(bw * 0.5, 0.0, 0.0)
			root.add_child(b1["node"])
			root.add_child(b2["node"])
			var top_y: float = b1["size"].y
			var scr := instantiate_centered_glb("computerScreen.glb")
			scr["node"].position = Vector3(-0.28, top_y, 0.0)
			root.add_child(scr["node"])
			var lamp := instantiate_centered_glb("lampSquareTable.glb")
			lamp["node"].position = Vector3(0.42, top_y, 0.0)
			root.add_child(lamp["node"])
			var pl := instantiate_centered_glb("plantSmall1.glb")
			pl["node"].position = Vector3(-0.65, top_y, 0.0)
			root.add_child(pl["node"])
			size = Vector3(bw * 2.0, top_y + 0.45, 0.65)

		"tv_presentation":
			var cab := instantiate_centered_glb("cabinetTelevisionDoors.glb")
			root.add_child(cab["node"])
			var top_y: float = cab["size"].y
			var tv := instantiate_centered_glb("televisionModern.glb")
			tv["node"].position = Vector3(0.0, top_y, 0.0)
			root.add_child(tv["node"])
			var glow := _make_screen_glow(1.16, 0.62, Color(0.18, 0.46, 0.76))
			glow.position = Vector3(0.0, top_y + 0.50, 0.06)
			root.add_child(glow)
			size = Vector3(cab["size"].x, top_y + tv["size"].y, cab["size"].z)

		"filing_cabinet":
			var fc := instantiate_centered_glb("bookcaseClosedDoors.glb")
			root.add_child(fc["node"])
			size = fc["size"]

		"potted_plant":
			var plant_data := instantiate_centered_glb("pottedPlant.glb")
			root.add_child(plant_data["node"])
			size = plant_data["size"]

		"bookcase":
			var bc_data := instantiate_centered_glb("bookcaseOpen.glb")
			root.add_child(bc_data["node"])
			size = bc_data["size"]
			for shelf_y in [0.46, 0.90, 1.32]:
				var books_data := instantiate_centered_glb("books.glb")
				var b_node: Node3D = books_data["node"]
				b_node.position = Vector3(0.0, shelf_y, 0.0)
				root.add_child(b_node)

		"bookcase_wide":
			var bc_data := instantiate_centered_glb("bookcaseClosedWide.glb")
			root.add_child(bc_data["node"])
			size = bc_data["size"]
			for sx in [-0.36, 0.36]:
				for sy in [0.46, 0.90]:
					var books_data := instantiate_centered_glb("books.glb")
					books_data["node"].position = Vector3(sx, sy, 0.0)
					root.add_child(books_data["node"])

		"lounge_sofa":
			var sofa_data := instantiate_centered_glb("loungeSofa.glb")
			root.add_child(sofa_data["node"])
			size = sofa_data["size"]

		"lounge_chair":
			var ch_data := instantiate_centered_glb("loungeDesignChair.glb")
			root.add_child(ch_data["node"])
			size = ch_data["size"]

		"round_table":
			var rt_data := instantiate_centered_glb("tableRound.glb")
			root.add_child(rt_data["node"])
			size = rt_data["size"]
			var pl := instantiate_centered_glb("plantSmall3.glb")
			pl["node"].position = Vector3(0.0, size.y, 0.0)
			root.add_child(pl["node"])

		"coffee_table":
			var tbl_data := instantiate_centered_glb("tableCoffee.glb")
			root.add_child(tbl_data["node"])
			size = tbl_data["size"]

		"side_table":
			var st_data := instantiate_centered_glb("sideTableDrawers.glb")
			root.add_child(st_data["node"])
			size = st_data["size"]
			var rad := instantiate_centered_glb("radio.glb")
			rad["node"].position = Vector3(-0.18, size.y, 0.0)
			root.add_child(rad["node"])
			var lmp := instantiate_centered_glb("lampRoundTable.glb")
			lmp["node"].position = Vector3(0.24, size.y, 0.0)
			root.add_child(lmp["node"])

		"floor_lamp":
			var lamp_data := instantiate_centered_glb("lampRoundFloor.glb")
			root.add_child(lamp_data["node"])
			size = lamp_data["size"]
			# Warm localized point light on floor lamps
			var omni := OmniLight3D.new()
			omni.light_color = Color(1.0, 0.82, 0.54)
			omni.light_energy = 0.45
			omni.omni_range = 4.8
			omni.position = Vector3(0.0, 1.52, 0.0)
			root.add_child(omni)

		"coat_rack":
			var cr_data := instantiate_centered_glb("coatRackStanding.glb")
			root.add_child(cr_data["node"])
			size = cr_data["size"]

		"speaker_tower":
			var sp_data := instantiate_centered_glb("speaker.glb")
			root.add_child(sp_data["node"])
			size = sp_data["size"]

		"storage_boxes":
			var b1 := instantiate_centered_glb("cardboardBoxClosed.glb")
			var b2 := instantiate_centered_glb("cardboardBoxOpen.glb")
			var b3 := instantiate_centered_glb("cardboardBoxClosed.glb")
			b1["node"].position = Vector3(-0.28, 0.0, 0.0)
			b2["node"].position = Vector3(0.28, 0.0, 0.04)
			b3["node"].position = Vector3(-0.26, b1["size"].y, 0.0)
			b3["node"].rotation.y = 0.25
			root.add_child(b1["node"])
			root.add_child(b2["node"])
			root.add_child(b3["node"])
			size = Vector3(1.15, b1["size"].y * 2.0, 0.55)

		"trashcan":
			var tc_data := instantiate_centered_glb("trashcan.glb", 1.5)
			root.add_child(tc_data["node"])
			size = tc_data["size"]

		"rug":
			var rug_data := instantiate_centered_glb("rugRectangle.glb")
			root.add_child(rug_data["node"])
			size = rug_data["size"]

		"rug_round":
			var rug_data := instantiate_centered_glb("rugRound.glb")
			root.add_child(rug_data["node"])
			size = rug_data["size"]

		_:
			var fallback := instantiate_centered_glb("desk.glb")
			root.add_child(fallback["node"])
			size = fallback["size"]

	return {
		"node": root,
		"size": size
	}

static func get_box_shape(size: Vector3) -> BoxShape3D:
	var key := "%0.2f_%0.2f_%0.2f" % [size.x, size.y, size.z]
	if not _shape_cache.has(key):
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(size.x, 0.2), maxf(size.y, 0.05), maxf(size.z, 0.2))
		_shape_cache[key] = shape
	return _shape_cache[key]

static func get_shared_material(key: String, color: Color, roughness: float = 0.7, transparency: bool = false) -> StandardMaterial3D:
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = roughness
		if transparency:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material_cache[key] = mat
	return _material_cache[key]

static func apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for c in node.get_children():
		apply_material_recursive(c, mat)

static func compute_node_aabb(node: Node3D, xform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var aabb := AABB()
	var first := true
	var cur_xform := xform * node.transform
	if node is MeshInstance3D and node.mesh:
		aabb = cur_xform * node.get_aabb()
		first = false
	for c in node.get_children():
		if c is Node3D:
			var sub := compute_node_aabb(c, cur_xform)
			if sub.size != Vector3.ZERO:
				if first:
					aabb = sub
					first = false
				else:
					aabb = aabb.merge(sub)
	return aabb

static func get_worker_animation_library() -> AnimationLibrary:
	if _shared_anim_library != null:
		return _shared_anim_library

	_shared_anim_library = OfficeAnimations.build_library()

	_add_furniture_motion_animations(_shared_anim_library)
	_add_standing_work_animation(_shared_anim_library)
	PlayerAnimations.add_animations(_shared_anim_library)
	return _shared_anim_library

static func _add_standing_work_animation(library: AnimationLibrary) -> void:
	# Retain a standing lower body while using the typing clip's hands and arms.
	# Keep the lower body upright during short workstation activities.
	var idle: Animation = library.get_animation("idle")
	var typing: Animation = library.get_animation("typing")
	var animation: Animation = idle.duplicate()
	var pace := typing.length / maxf(idle.length, 0.001)
	animation.length = typing.length
	animation.loop_mode = Animation.LOOP_LINEAR
	for track in range(animation.get_track_count()):
		for key in range(animation.track_get_key_count(track) - 1, -1, -1):
			animation.track_remove_key(track, key)
		for key in range(idle.track_get_key_count(track)):
			animation.track_insert_key(track, idle.track_get_key_time(track, key) * pace, idle.track_get_key_value(track, key), idle.track_get_key_transition(track, key))
	for track in range(typing.get_track_count()):
		var path := typing.track_get_path(track)
		var bone := String(path).get_slice(":", 1).trim_prefix("office_")
		if not (bone.begins_with("Spine") or bone in ["Neck", "Head"] or "Shoulder" in bone or "Arm" in bone or "Hand" in bone):
			continue
		var target := animation.find_track(path, typing.track_get_type(track))
		if target < 0:
			target = animation.add_track(typing.track_get_type(track))
			animation.track_set_path(target, path)
		for key in range(animation.track_get_key_count(target) - 1, -1, -1):
			animation.track_remove_key(target, key)
		for key in range(typing.track_get_key_count(track)):
			animation.track_insert_key(target, typing.track_get_key_time(track, key), typing.track_get_key_value(track, key), typing.track_get_key_transition(track, key))
	library.add_animation("work_standing", animation)

static func _add_furniture_motion_animations(library: AnimationLibrary) -> void:
	for motion in ["grip", "push", "pull"]:
		var source: Animation = library.get_animation("idle" if motion == "grip" else "walk")
		var animation: Animation = source.duplicate()
		var pace := 1.0 if motion == "grip" else 1.65
		animation.length = source.length * pace
		# Reverse the walking cycle for backward steps while pulling.
		for track in range(animation.get_track_count()):
			for key in range(animation.track_get_key_count(track) - 1, -1, -1):
				animation.track_remove_key(track, key)
			for key in range(source.track_get_key_count(track)):
				var time := source.track_get_key_time(track, key)
				if motion == "pull":
					time = source.length - time
				animation.track_insert_key(track, time * pace, source.track_get_key_value(track, key), source.track_get_key_transition(track, key))
		animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(motion, animation)

static func get_worker_state_machine() -> AnimationNodeStateMachine:
	if _shared_state_machine != null:
		return _shared_state_machine

	var lib := get_worker_animation_library()
	var sm := AnimationNodeStateMachine.new()
	var anim_names := lib.get_animation_list()

	for a_name in anim_names:
		var node_anim := AnimationNodeAnimation.new()
		node_anim.animation = StringName("office/" + String(a_name))
		sm.add_node(a_name, node_anim)

	for a1 in anim_names:
		for a2 in anim_names:
			if a1 != a2:
				var tr := AnimationNodeStateMachineTransition.new()
				tr.xfade_time = 0.25
				tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				sm.add_transition(a1, a2, tr)

	_shared_state_machine = sm
	return _shared_state_machine
