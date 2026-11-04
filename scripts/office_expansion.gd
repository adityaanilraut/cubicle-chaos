class_name OfficeExpansion
extends RefCounted

const OfficeDetails = preload("res://scripts/office_details.gd")

# South wing: a 2 m circulation spine connects five independently entered rooms.
const DOORWAYS := [
	Rect2(-10.0, 11.35, 2.0, 1.30),
	Rect2(-3.0, 11.35, 2.0, 1.30),
	Rect2(3.0, 11.35, 2.0, 1.30),
	Rect2(7.8, 11.35, 1.4, 1.30),
	Rect2(10.8, 11.35, 1.4, 1.30),
]

static func floor_material(_x: float, _z: float, _even: bool) -> Material:
	# Kept for compatibility: the whole office now uses one floor colour.
	return AssetCatalog.get_shared_material("office_floor_unified", OfficeTheme.floor_color(0), 0.75)

static func _collider(parent: Node3D, size: Vector3, pos: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("nav_bake")
	body.position = pos
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	shape.shape = AssetCatalog.get_box_shape(size)
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	parent.add_child(body)

static func _glass(parent: Node3D, a: Vector2, b: Vector2, frosted := false) -> void:
	var width := a.distance_to(b)
	var pos := Vector3((a.x + b.x) * 0.5, 0, (a.y + b.y) * 0.5)
	var yaw := -atan2(b.y - a.y, b.x - a.x)
	var panel := ModernAssets.glass_panel(width, 2.35, frosted)
	panel.position = pos
	panel.rotation.y = yaw
	parent.add_child(panel)
	_collider(parent, Vector3(width, 2.35, 0.10), pos, yaw)

static func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	ModernAssets.box(parent, size, pos + Vector3.UP * size.y * 0.5, ModernAssets.material("architecture", OfficeTheme.get_theme(0)["architecture"]))
	_collider(parent, size, pos)

static func _door_frame(parent: Node3D, x: float, width: float) -> void:
	var mat := ModernAssets.material("frame", OfficeTheme.get_theme(0)["frame"])
	ModernAssets.box(parent, Vector3(width, 0.10, 0.14), Vector3(x, 2.30, 12), mat)
	# No glass or collision spans the opening; this is a walk-through portal.
	ModernAssets.box(parent, Vector3(width, 0.035, 0.18), Vector3(x, 0.018, 12), ModernAssets.material("accent", OfficeTheme.get_theme(0)["accent"]))

static func build_architecture(office: Node3D, parent: Node3D) -> void:
	var wing := Node3D.new()
	wing.name = "SouthWing"
	parent.add_child(wing)
	# Clear fronts face the circulation spine. Full-height glass keeps sightlines.
	for span in [[-13.0, -10.0], [-8.0, -5.0], [-5.0, -3.0], [-1.0, 1.0], [1.0, 3.0], [5.0, 7.0]]:
		_glass(wing, Vector2(span[0], 12), Vector2(span[1], 12))
	for x in [-5.0, 1.0]:
		_glass(wing, Vector2(x, 12), Vector2(x, 16))
		_glass(wing, Vector2(x, 16), Vector2(x, 20))
	# Privacy side wall and cutaway bathroom walls keep the fixtures visible.
	_glass(wing, Vector2(7, 12), Vector2(7, 20), true)
	_solid(wing, Vector3(0.12, 1.25, 8), Vector3(10, 0, 16))
	_solid(wing, Vector3(0.12, 1.25, 8), Vector3(12.94, 0, 16))
	for span in [[7.0, 7.8], [9.2, 10.0], [10.0, 10.8], [12.2, 13.0]]:
		_solid(wing, Vector3(span[1] - span[0], 1.25, 0.12), Vector3((span[0] + span[1]) * 0.5, 0, 12))
	for entry in [[-9.0, 2.0], [-2.0, 2.0], [4.0, 2.0], [8.5, 1.4], [11.5, 1.4]]:
		_door_frame(wing, entry[0], entry[1])
	# A low rear parapet preserves the office's isometric cutaway presentation.
	_solid(wing, Vector3(26, 0.55, 0.12), Vector3(0, 0, 19.94))
	var sign_color: Color = OfficeTheme.get_theme(0)["sign"]
	office._add_room_sign(wing, "01 / DATA CENTER", Vector3(-9, 2.65, 12), sign_color)
	office._add_room_sign(wing, "02 / FOCUS ROOM", Vector3(-2, 2.65, 12), sign_color)
	office._add_room_sign(wing, "03 / COLLABORATION STUDIO", Vector3(4, 2.65, 12), sign_color)
	office._add_room_sign(wing, "04 / WC", Vector3(8.5, 2.65, 12), sign_color)
	office._add_room_sign(wing, "05 / WC + SHOWER", Vector3(11.5, 2.65, 12), sign_color)
	# Fixed details sit on the walls, outside entrances and activity areas.
	OfficeDetails.bathroom_supplies(wing, Vector3(7.10, 1.35, 15.0), PI * 0.5)
	OfficeDetails.bathroom_supplies(wing, Vector3(10.10, 1.35, 15.0), PI * 0.5)
	OfficeDetails.safety_station(wing, Vector3(-12.85, 1.15, 18.1), PI * 0.5)
	OfficeDetails.clock(wing, Vector3(-2.0, 1.85, 12.10), 0.0)
	var tray := ModernAssets.material("cable_tray", Color(0.56, 0.52, 0.45))
	for x in [-11.3, -6.7]:
		ModernAssets.box(wing, Vector3(0.22, 0.08, 4.8), Vector3(x, 2.58, 15.6), tray)
		for z in [13.6, 15.6, 17.6]:
			ModernAssets.box(wing, Vector3(0.38, 0.035, 0.06), Vector3(x, 2.63, z), tray)


static func furnish(office: Node3D) -> void:
	var items := [
		# Opposing rack banks face a generous central service aisle.
		["server_rack", Vector3(-11.3, 0, 14.0), PI * 0.5],
		["network_rack", Vector3(-11.3, 0, 15.6), PI * 0.5],
		["server_rack", Vector3(-11.3, 0, 17.2), PI * 0.5],
		["server_rack", Vector3(-6.7, 0, 14.0), -PI * 0.5],
		["network_rack", Vector3(-6.7, 0, 15.6), -PI * 0.5],
		["server_rack", Vector3(-6.7, 0, 17.2), -PI * 0.5],
		["cooling_unit", Vector3(-12.1, 0, 18.9), PI * 0.5],
		["ups_battery", Vector3(-5.9, 0, 18.9), -PI * 0.5],
		["tech_workbench", Vector3(-9.0, 0, 19.0), PI],
		# Quiet focus room — tech work stays in the dedicated IT support room
		["laptop_desk", Vector3(-2, 0, 18.3), PI],
		["desk_plain", Vector3(-3.6, 0, 14.2), 0.0],
		["chair_desk", Vector3(-3.6, 0, 15.1), PI],
		["filing_cabinet", Vector3(-0.1, 0, 14.1), -PI * 0.5],
		["whiteboard", Vector3(-3.7, 0, 16.2), PI * 0.5],
		["potted_plant", Vector3(0.2, 0, 18.8), 0.0],
		# Collaboration Studio (glass meeting, rethemed) — table, seating, board
		["glass_table", Vector3(4, 0, 16.2), 0.0],
		["whiteboard", Vector3(4, 0, 19.1), PI],
		["lounge_chair", Vector3(2.6, 0, 14.3), 0.0],
		["lounge_chair", Vector3(5.4, 0, 14.3), 0.0],
		["potted_plant", Vector3(6, 0, 18.9), 0.0],
		["toilet", Vector3(8.5, 0, 18.7), PI],
		["bathroom_vanity", Vector3(7.55, 0, 14.5), PI * 0.5],
		["hand_dryer", Vector3(9.4, 0, 13.3), 0.0],
		["restroom_divider", Vector3(8.0, 0, 17.2), 0.0],
		["trashcan", Vector3(7.6, 0, 13.3), 0.0],
		["toilet", Vector3(11.5, 0, 18.8), PI],
		["bathroom_vanity", Vector3(10.55, 0, 14.5), PI * 0.5],
		["shower", Vector3(11.1, 0, 16.6), PI],
		["hand_dryer", Vector3(12.4, 0, 13.3), 0.0],
		["trashcan", Vector3(10.6, 0, 13.3), 0.0],
		["potted_plant", Vector3(-12, 0, 10.9), 0.0],
		["potted_plant", Vector3(6.8, 0, 10.9), 0.0],
	]
	for entry in items:
		office.place_furniture_item(entry[0], entry[1], entry[2], false)
