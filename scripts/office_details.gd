class_name OfficeDetails
extends RefCounted

# Small fixed details are visual architecture, so they never obstruct navigation.
# Each fixture is assembled in local coordinates and can be reused elsewhere.
static func _fixture(parent: Node3D, fixture_name: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = fixture_name
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	return root

static func _box(parent: Node3D, size: Vector3, pos: Vector3, key: String, color: Color) -> MeshInstance3D:
	return ModernAssets.box(parent, size, pos, ModernAssets.material("detail_" + key, color))

static func bathroom_supplies(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := _fixture(parent, "BathroomSupplies", pos, yaw)
	var white := Color(0.91, 0.91, 0.87)
	var dark := Color(0.38, 0.40, 0.38)
	# Wall-mounted soap and paper towel dispensers, with visible outlets.
	_box(root, Vector3(0.19, 0.30, 0.12), Vector3(-0.27, 0, 0), "soap", white)
	_box(root, Vector3(0.10, 0.025, 0.025), Vector3(-0.27, -0.10, 0.07), "outlet", dark)
	_box(root, Vector3(0.32, 0.40, 0.14), Vector3(0.18, 0, 0), "towels", white)
	_box(root, Vector3(0.22, 0.025, 0.025), Vector3(0.18, -0.14, 0.08), "outlet", dark)

static func safety_station(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := _fixture(parent, "SafetyStation", pos, yaw)
	var red := Color(0.69, 0.20, 0.17)
	var white := Color(0.96, 0.94, 0.88)
	var dark := Color(0.25, 0.26, 0.24)
	# A first-aid cabinet and an extinguisher are recognizable at game scale.
	_box(root, Vector3(0.46, 0.38, 0.13), Vector3(0.34, 0.32, 0), "first_aid", white)
	_box(root, Vector3(0.07, 0.23, 0.02), Vector3(0.34, 0.32, 0.075), "safety_red", red)
	_box(root, Vector3(0.23, 0.07, 0.02), Vector3(0.34, 0.32, 0.076), "safety_red", red)
	_box(root, Vector3(0.19, 0.46, 0.16), Vector3(-0.23, -0.04, 0), "safety_red", red)
	_box(root, Vector3(0.13, 0.08, 0.10), Vector3(-0.23, 0.22, 0), "extinguisher_handle", dark)
	_box(root, Vector3(0.14, 0.10, 0.02), Vector3(-0.23, -0.04, 0.09), "first_aid", white)

static func clock(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := _fixture(parent, "OfficeClock", pos, yaw)
	var rim := Color(0.37, 0.39, 0.35)
	var face := Color(0.94, 0.93, 0.87)
	_box(root, Vector3(0.50, 0.50, 0.08), Vector3.ZERO, "clock_rim", rim)
	_box(root, Vector3(0.43, 0.43, 0.025), Vector3(0, 0, 0.05), "clock_face", face)
	_box(root, Vector3(0.025, 0.14, 0.02), Vector3(0, 0.045, 0.075), "clock_rim", rim)
	_box(root, Vector3(0.12, 0.025, 0.02), Vector3(0.05, 0, 0.075), "clock_rim", rim)
