class_name OfficeArrival
extends RefCounted

# An eight-meter extension gives public arrival its own footprint. The 2.4 m
# entrance and security portals share a straight, protected east-west route.
const ENTRANCE := Vector3(20, 0, 7)
const SECURITY := Vector3(13, 0, 7)
const DOORWAYS := [
	Rect2(12.0, 5.8, 9.0, 2.4), # Arrival route, including the exterior landing
	Rect2(15.5, -2.75, 2.0, 1.5), # Visitor meeting room
	Rect2(15.5, 11.25, 2.0, 1.5), # IT support room
]

static func _portal(parent: Node3D, pos: Vector3, width: float, security := false) -> void:
	var frame := ModernAssets.material("frame", OfficeTheme.get_theme(0)["frame"])
	var accent := ModernAssets.material("accent", OfficeTheme.get_theme(0)["accent"])
	for side in [-1.0, 1.0]:
		var foot := pos + Vector3(0, 0, side * (width * 0.5 + 0.09))
		ModernAssets.box(parent, Vector3(0.24, 2.40, 0.18), foot + Vector3.UP * 1.20, frame)
		OfficeExpansion._collider(parent, Vector3(0.24, 2.40, 0.18), foot)
		if security:
			ModernAssets.box(parent, Vector3(0.255, 0.62, 0.06), foot + Vector3(0, 1.28, -side * 0.10), accent)
	ModernAssets.box(parent, Vector3(0.24, 0.12, width + 0.36), pos + Vector3.UP * 2.38, frame)
	# Flush thresholds and lane marks have no collision or raised nav geometry.
	ModernAssets.box(parent, Vector3(0.30, 0.018, width), pos + Vector3.UP * 0.012, accent)

static func _room_front(parent: Node3D, z: float) -> void:
	for span in [[13.0, 15.5], [17.5, 20.0]]:
		OfficeExpansion._glass(parent, Vector2(span[0], z), Vector2(span[1], z))
	var frame := ModernAssets.material("frame", OfficeTheme.get_theme(0)["frame"])
	ModernAssets.box(parent, Vector3(2.0, 0.10, 0.14), Vector3(16.5, 2.30, z), frame)

static func build_architecture(office: Node3D, parent: Node3D) -> void:
	var wing := Node3D.new()
	wing.name = "EastArrivalWing"
	parent.add_child(wing)
	# Public/private divider: security is the only opening into the staff floor.
	for span in [[-10.0, -2.0], [-2.0, 2.0], [2.0, 5.8], [8.2, 12.0]]:
		OfficeExpansion._glass(wing, Vector2(13, span[0]), Vector2(13, span[1]))
	# The existing bathroom side wall continues the divider south of z=12.
	_room_front(wing, -2.0)
	_room_front(wing, 12.0)
	# East facade is inset one meter from the floor edge to leave an arrival
	# landing outside the door, reachable by the player's normal walking bounds.
	for span in [[-10.0, -6.0], [-6.0, -2.0], [-2.0, 2.0], [2.0, 5.8]]:
		OfficeExpansion._glass(wing, Vector2(20, span[0]), Vector2(20, span[1]))
	# Lower foreground walls preserve the isometric view into the new rooms.
	for span in [[8.2, 12.0], [12.0, 16.0], [16.0, 20.0]]:
		OfficeExpansion._solid(wing, Vector3(0.12, 0.65, span[1] - span[0]), Vector3(20, 0, (span[0] + span[1]) * 0.5))
	OfficeExpansion._solid(wing, Vector3(7, 0.55, 0.12), Vector3(16.5, 0, 19.94))
	_portal(wing, ENTRANCE, 2.4)
	_portal(wing, SECURITY, 2.4, true)
	# Reader and status indicator attach to the arch, outside its clear width.
	var reader := ModernAssets.material("security_reader", Color(0.32, 0.34, 0.29))
	var status := ModernAssets.material("security_status", Color(0.57, 0.72, 0.51), true)
	ModernAssets.box(wing, Vector3(0.08, 0.27, 0.18), Vector3(13.16, 1.18, 5.71), reader)
	ModernAssets.box(wing, Vector3(0.012, 0.04, 0.13), Vector3(13.207, 1.25, 5.71), status)
	ModernAssets.box(wing, Vector3(0.255, 0.045, 0.50), Vector3(13, 2.29, 7), status)
	var color: Color = OfficeTheme.get_theme(0)["sign"]
	office._add_room_sign(wing, "WELCOME", Vector3(17, 2.7, 4.8), color)
	office._add_room_sign(wing, "ENTRANCE", ENTRANCE + Vector3(0, 2.75, 0), color)
	office._add_room_sign(wing, "STAFF / SECURITY", SECURITY + Vector3(0, 2.75, 0), color)
	office._add_room_sign(wing, "06 / VISITOR MEETING", Vector3(16.5, 2.65, -2), color)
	office._add_room_sign(wing, "07 / IT SUPPORT", Vector3(16.5, 2.65, 12), color)
	# A subdued sage runner and chevrons make the arrival path legible.
	var runner := ModernAssets.material("arrival_runner", Color(0.64, 0.68, 0.56))
	ModernAssets.box(wing, Vector3(6.6, 0.014, 1.6), Vector3(16.6, 0.008, 7), runner)
	var marks := ModernAssets.material("arrival_wayfinding", Color(0.90, 0.87, 0.75))
	for x in [14.6, 16.6, 18.6]:
		for side in [-1.0, 1.0]:
			var mark := ModernAssets.box(wing, Vector3(0.34, 0.012, 0.055), Vector3(x, 0.023, 7 + side * 0.11), marks)
			mark.rotation.y = -side * PI * 0.25
	# Compact directory sits beside the lane instead of blocking the arch.
	var directory := Vector3(14.3, 0, 9.3)
	var board := ModernAssets.material("directory", Color(0.36, 0.39, 0.31))
	ModernAssets.box(wing, Vector3(1.35, 1.40, 0.12), directory + Vector3.UP * 0.94, board)
	ModernAssets.box(wing, Vector3(1.45, 0.08, 0.40), directory + Vector3.UP * 0.04, board)
	OfficeExpansion._collider(wing, Vector3(1.45, 1.64, 0.40), directory)
	office._add_room_sign(wing, "CUBICLE CHAOS\n\nRECEPTION\nVISITOR MEETING\nSTAFF / SECURITY\nIT SUPPORT", directory + Vector3(0, 1.15, 0.09), color)
	var label: Label3D = office.room_sign_labels.back()
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.font_size = 23
	label.outline_size = 3
	label.pixel_size = 0.004

static func furnish(office: Node3D) -> void:
	var items := [
		# Reception and waiting furniture stay north of the protected lane.
		["reception_desk", Vector3(15.4, 0, 4.6), 0.0],
		["chair_desk", Vector3(15.4, 0, 3.4), 0.0],
		["rug", Vector3(17.0, 0, 1.3), 0.0],
		["lounge_sofa", Vector3(17.0, 0, 0.0), 0.0],
		["lounge_chair", Vector3(18.9, 0, 2.0), -PI * 0.5],
		["coffee_table", Vector3(17.1, 0, 1.7), 0.0],
		["potted_plant", Vector3(19.1, 0, 4.7), 0.0],
		["potted_plant", Vector3(13.8, 0, -0.9), 0.0],
		["coat_rack", Vector3(19.2, 0, -0.9), 0.0],
		["side_table", Vector3(18.7, 0, 10.7), 0.0],
		["lounge_chair", Vector3(17.0, 0, 10.7), PI],
		["potted_plant", Vector3(19.2, 0, 9.1), 0.0],
		# Visitor meeting room: clients can meet without crossing security.
		["conference_table", Vector3(16.5, 0, -5.9), 0.0],
		["tv_presentation", Vector3(16.8, 0, -9.1), 0.0],
		["bookcase", Vector3(14.0, 0, -9.1), 0.0],
		["potted_plant", Vector3(19.1, 0, -9.1), 0.0],
		["whiteboard", Vector3(14.0, 0, -3.5), PI * 0.5],
		# IT support has desks and storage, separate from the server aisle.
		["tech_workbench", Vector3(16.5, 0, 18.7), PI],
		["desk_pc", Vector3(14.2, 0, 14.3), 0.0],
		["chair_desk", Vector3(14.2, 0, 15.5), PI],
		["filing_cabinet", Vector3(19.0, 0, 14.3), -PI * 0.5],
		["storage_boxes", Vector3(19.0, 0, 17.5), 0.0],
		["whiteboard", Vector3(14.0, 0, 17.7), PI * 0.5],
		["potted_plant", Vector3(19.1, 0, 19.0), 0.0],
	]
	for entry in items:
		office.place_furniture_item(entry[0], entry[1], entry[2], false)
