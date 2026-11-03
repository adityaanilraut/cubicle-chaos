class_name ModernAssets
extends RefCounted

# Geometry shares the office's low-poly style and needs no external textures.
const ITEMS := [
	["server_rack", "Server Rack", "Server Rack"],
	["network_rack", "Network Rack", "Network Rack"],
	["cooling_unit", "Data Center Cooling Unit", "Cooling"],
	["ups_battery", "UPS Battery", "UPS"],
	["tech_workbench", "Focus Workbench", "Focus Bench"],
	["glass_partition", "Framed Glass Partition", "Glass Wall"],
	["frosted_partition", "Frosted Privacy Glass", "Privacy Glass"],
	["toilet", "Bathroom Toilet", "Toilet"],
	["bathroom_vanity", "Vanity, Sink & Mirror", "Vanity"],
	["restroom_divider", "Bathroom Stall Partition", "Stall Wall"],
	["hand_dryer", "Hand Sanitizer & Dryer Stand", "Hand Dryer"],
	["shower", "Glass Shower Enclosure", "Shower"],
	["glass_table", "Glass Collaboration Table", "Glass Table"],
	["whiteboard", "Rolling Planning Whiteboard", "Whiteboard"],
]

static func catalog_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in ITEMS:
		var id: String = entry[0]
		var def := {"id": id, "title": entry[1], "short": entry[2], "hotkey": "", "nav_obstacle": true}
		if id in ["glass_partition", "frosted_partition", "restroom_divider", "toilet", "bathroom_vanity", "shower"]:
			def["player_movable"] = false
		result.append(def)
	return result

static func material(key: String, color: Color, glow := false) -> StandardMaterial3D:
	var mat := AssetCatalog.get_shared_material("modern_" + key, color, 0.38, color.a < 1.0)
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 1.8
	return mat

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	node.mesh = mesh
	node.position = pos
	# Preview overrides can be cleared without losing glass or status lights.
	node.set_meta("preserve_material", true)
	parent.add_child(node)
	return node

static func glass_panel(width := 2.0, height := 2.35, frosted := false) -> Node3D:
	var root := Node3D.new()
	root.name = "FrostedGlass" if frosted else "ClearGlass"
	var frame := material("frame", OfficeTheme.get_theme(0)["frame"])
	var glass := material("frosted" if frosted else "glass", Color(0.88, 0.90, 0.86, 0.48) if frosted else OfficeTheme.get_theme(0)["glass_tint"])
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	box(root, Vector3(width - 0.10, height - 0.12, 0.045), Vector3(0, height * 0.5, 0), glass)
	for x in [-width * 0.5 + 0.035, width * 0.5 - 0.035]:
		box(root, Vector3(0.07, height, 0.10), Vector3(x, height * 0.5, 0), frame)
	for y in [0.045, height - 0.045]:
		box(root, Vector3(width, 0.09, 0.10), Vector3(0, y, 0), frame)
	# A safety stripe makes the transparent barrier legible from both sides.
	box(root, Vector3(width - 0.10, 0.045, 0.055), Vector3(0, 1.05, 0), material("safety_stripe", Color(0.62, 0.72, 0.60, 0.6)))
	return root

static func build(item_id: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "VisualRoot"
	var dark := material("cabinet", Color(0.42, 0.38, 0.33))
	var steel := material("steel", Color(0.68, 0.64, 0.58))
	var porcelain := material("porcelain", Color(0.93, 0.92, 0.89))
	var warm := material("warm_light", Color(0.98, 0.85, 0.60), true)
	var green := material("sage_light", Color(0.62, 0.74, 0.58), true)
	var size := Vector3.ONE
	match item_id:
		"server_rack", "network_rack":
			size = Vector3(1.05, 2.25, 1.10)
			var patch_lead := material("patch_lead", Color(0.59, 0.68, 0.51))
			box(root, size, Vector3(0, 1.125, 0), dark)
			for y in [0.10, 2.15]:
				box(root, Vector3(1.10, 0.10, 1.14), Vector3(0, y, 0), steel)
			for x in [-0.48, 0.48]:
				box(root, Vector3(0.035, 1.98, 0.025), Vector3(x, 1.12, 0.56), steel)
			for i in range(9):
				var y := 0.30 + float(i) * 0.20
				box(root, Vector3(0.86, 0.15, 0.05), Vector3(0, y, 0.565), steel)
				for j in range(5):
					box(root, Vector3(0.08, 0.025, 0.015), Vector3(-0.31 + j * 0.12, y, 0.60), dark)
				box(root, Vector3(0.045, 0.045, 0.015), Vector3(0.34, y, 0.60), green if i % 3 else warm)
				if item_id == "network_rack":
					box(root, Vector3(0.34, 0.018, 0.02), Vector3(-0.08, y + 0.045, 0.61), warm)
					# Patch leads distinguish switches from the compute rack bays.
					for j in range(3):
						box(root, Vector3(0.018, 0.10, 0.025), Vector3(-0.25 + j * 0.18, y - 0.025, 0.625), patch_lead)
			var caption := Label3D.new()
			caption.text = "NETWORK" if item_id == "network_rack" else "COMPUTE"
			caption.font_size = 24
			caption.pixel_size = 0.002
			caption.outline_size = 2
			caption.position = Vector3(0, 2.13, 0.585)
			root.add_child(caption)
			# Rear vents remain visible from the service side of each bank.
			for y in [0.4, 0.8, 1.2, 1.6, 2.0]:
				box(root, Vector3(0.72, 0.04, 0.025), Vector3(0, y, -0.56), steel)
		"cooling_unit":
			size = Vector3(1.15, 2.10, 0.80)
			box(root, size, Vector3(0, 1.05, 0), steel)
			for i in range(13):
				box(root, Vector3(0.92, 0.045, 0.035), Vector3(0, 0.35 + i * 0.115, 0.415), dark)
			box(root, Vector3(0.42, 0.14, 0.03), Vector3(0, 1.91, 0.42), warm)
		"ups_battery":
			size = Vector3(0.90, 1.25, 0.75)
			box(root, size, Vector3(0, 0.625, 0), dark)
			box(root, Vector3(0.40, 0.20, 0.035), Vector3(0, 0.98, 0.39), green)
			for i in range(4):
				box(root, Vector3(0.70, 0.025, 0.03), Vector3(0, 0.22 + i * 0.13, 0.39), steel)
		"tech_workbench":
			size = Vector3(2.4, 1.65, 1.05)
			box(root, Vector3(2.4, 0.10, 1.05), Vector3(0, 0.92, 0), steel)
			for x in [-0.92, 0.92]:
				box(root, Vector3(0.38, 0.87, 0.80), Vector3(x, 0.435, 0), dark)
			AssetCatalog._part(root, "computerScreen.glb", Vector3(-0.5, 0.97, -0.2))
			AssetCatalog._part(root, "computerKeyboard.glb", Vector3(-0.5, 0.97, 0.22))
			box(root, Vector3(0.55, 0.08, 0.40), Vector3(0.52, 1.01, 0.05), dark)
			for i in range(4):
				box(root, Vector3(0.05, 0.02, 0.16), Vector3(0.34 + i * 0.12, 1.06, 0.05), green)
		"glass_partition", "frosted_partition":
			size = Vector3(2.0, 2.35, 0.10)
			root.add_child(glass_panel(2.0, 2.35, item_id == "frosted_partition"))
		"toilet":
			size = AssetCatalog._part(root, "toiletSquare.glb", Vector3.ZERO, 0, 1.65)["size"]
		"bathroom_vanity":
			size = Vector3(1.20, 2.05, 0.65)
			box(root, Vector3(1.20, 0.82, 0.62), Vector3(0, 0.41, 0), steel)
			box(root, Vector3(1.20, 0.08, 0.65), Vector3(0, 0.86, 0), porcelain)
			box(root, Vector3(0.65, 0.015, 0.36), Vector3(0, 0.907, 0.04), material("basin", Color(0.72, 0.76, 0.74)))
			box(root, Vector3(0.04, 0.23, 0.04), Vector3(0, 1.01, -0.21), steel)
			box(root, Vector3(0.04, 0.04, 0.18), Vector3(0, 1.105, -0.14), steel)
			box(root, Vector3(1.12, 0.83, 0.07), Vector3(0, 1.60, -0.27), dark)
			box(root, Vector3(1.02, 0.73, 0.015), Vector3(0, 1.60, -0.225), material("mirror", Color(0.82, 0.87, 0.86)))
			box(root, Vector3(1.12, 0.035, 0.08), Vector3(0, 2.03, -0.24), warm)
		"restroom_divider":
			size = Vector3(1.60, 1.85, 0.12)
			box(root, Vector3(1.60, 1.62, 0.10), Vector3(0, 1.04, 0), material("stall", Color(0.68, 0.66, 0.60)))
			for x in [-0.74, 0.74]:
				box(root, Vector3(0.06, 1.85, 0.12), Vector3(x, 0.925, 0), steel)
		"hand_dryer":
			size = Vector3(0.46, 1.18, 0.40)
			box(root, Vector3(0.46, 0.08, 0.40), Vector3(0, 0.04, 0), dark)
			box(root, Vector3(0.10, 0.70, 0.10), Vector3(0, 0.40, 0), steel)
			box(root, Vector3(0.40, 0.44, 0.28), Vector3(0, 0.96, 0), porcelain)
			box(root, Vector3(0.27, 0.12, 0.04), Vector3(0, 0.90, 0.15), dark)
			box(root, Vector3(0.08, 0.02, 0.02), Vector3(0, 1.08, 0.16), green)
		"shower":
			size = AssetCatalog._part(root, "shower.glb", Vector3.ZERO, 0, 1.65)["size"]
		"glass_table":
			size = Vector3(2.60, 0.90, 1.40)
			box(root, Vector3(2.60, 0.09, 1.40), Vector3(0, 0.855, 0), material("table_glass", Color(0.84, 0.88, 0.86, 0.48)))
			for x in [-1.05, 1.05]:
				for z in [-0.48, 0.48]:
					box(root, Vector3(0.07, 0.81, 0.07), Vector3(x, 0.405, z), steel)
		"whiteboard":
			size = Vector3(1.80, 1.95, 0.60)
			box(root, Vector3(1.80, 1.08, 0.10), Vector3(0, 1.40, 0), steel)
			box(root, Vector3(1.68, 0.96, 0.02), Vector3(0, 1.40, 0.06), porcelain)
			for x in [-0.66, 0.66]:
				box(root, Vector3(0.06, 0.90, 0.06), Vector3(x, 0.45, 0), steel)
				box(root, Vector3(0.10, 0.06, 0.60), Vector3(x, 0.03, 0), dark)
			for i in range(3):
				box(root, Vector3(0.6 - i * 0.12, 0.025, 0.01), Vector3(-0.30, 1.65 - i * 0.17, 0.078), steel)
			box(root, Vector3(0.32, 0.30, 0.01), Vector3(0.48, 1.50, 0.078), warm)
	# Include trim, handles and LEDs in the collision/placement footprint.
	var bounds := AssetCatalog.compute_node_aabb(root)
	size = Vector3(maxf(absf(bounds.position.x), absf(bounds.end.x)) * 2.0, bounds.end.y, maxf(absf(bounds.position.z), absf(bounds.end.z)) * 2.0)
	return {"node": root, "size": size}
