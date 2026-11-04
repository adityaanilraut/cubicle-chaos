class_name BaseballBat
extends RefCounted

# All poses use the same one metre bat, with its handle at local Y = 0.
# Rendering, hand grips, ribbons and collision samples share this trajectory.
const LENGTH := 1.02
const RADIUS := 0.075
const SAMPLE_TIME := 1.0 / 180.0

static func create_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "BaseballBat"
	_section(root, "Knob", 0.035, 0.035, 0.03, 0.015, Color(0.30, 0.17, 0.08))
	_section(root, "WrappedGrip", 0.022, 0.025, 0.27, 0.16, Color(0.12, 0.16, 0.21))
	for i in range(9):
		_section(root, "GripSeam", 0.0255, 0.0255, 0.007, 0.045 + i * 0.027, Color(0.28, 0.34, 0.39))
	_section(root, "Taper", 0.025, 0.061, 0.38, 0.485, Color(0.70, 0.44, 0.21))
	_section(root, "Barrel", 0.061, 0.065, 0.31, 0.83, Color(0.86, 0.64, 0.36))
	_section(root, "EndCap", 0.065, 0.048, 0.035, 1.002, Color(0.63, 0.37, 0.16))
	return root

static func _section(parent: Node3D, title: String, bottom: float, top: float, height: float, y: float, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = title
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 12
	part.mesh = mesh
	part.position.y = y
	part.material_override = AssetCatalog.get_shared_material("bat_" + title, color, 0.72)
	parent.add_child(part)

static func local_pose(id: String = "", time := 0.0) -> Transform3D:
	var hilt := Vector3(-0.18, 1.03, 0.36)
	var tip := Vector3(-0.43, 1.98, 0.10)
	var move := CombatMoves.get_move(id)
	if not move.is_empty() and move.family == "bat":
		var c := float(move.contact)
		var d := float(move.duration)
		var keys: Array
		if id == "bat_overhead":
			keys = [[0.0, hilt, tip], [c * 0.48, Vector3(-0.10, 1.52, 0.12), Vector3(-0.12, 2.25, -0.57)], [c, Vector3(0, 1.12, 0.56), Vector3(0, 0.83, 1.54)], [c + 0.13, Vector3(0, 0.84, 0.44), Vector3(0, 0.12, 1.16)], [d, hilt, tip]]
		else:
			var side := -1.0 if id == "bat_backhand" else 1.0
			keys = [[0.0, hilt, tip], [c * 0.46, Vector3(-side * 0.34, 1.17, 0.12), Vector3(-side * 1.14, 1.40, -0.43)], [c, Vector3(0, 1.12, 0.60), Vector3(0, 1.15, 1.62)], [c + 0.12, Vector3(side * 0.32, 1.07, 0.25), Vector3(side * 1.26, 0.93, 0.04)], [d, hilt, tip]]
		for i in range(1, keys.size()):
			if time <= float(keys[i][0]):
				var weight := smoothstep(float(keys[i - 1][0]), float(keys[i][0]), time)
				hilt = (keys[i - 1][1] as Vector3).lerp(keys[i][1], weight)
				tip = (keys[i - 1][2] as Vector3).lerp(keys[i][2], weight)
				break
	return Transform3D(Basis(Quaternion(Vector3.UP, (tip - hilt).normalized())), hilt)

static func held_pose(player: OfficePlayer) -> Transform3D:
	var swinging := player.combat.phase == OfficeCombat.Phase.ATTACK and player.combat.kind == "bat"
	if swinging and player.combat.bat_strike.blocked:
		var strike := player.combat.bat_strike
		var stopped := local_pose(player.combat.move_id, strike.blocked_time)
		var recover := smoothstep(strike.blocked_time + 0.08, float(player.combat.current_move().duration), player.combat.phase_time)
		return player.global_transform * stopped.interpolate_with(local_pose(), recover)
	return player.global_transform * local_pose(player.combat.move_id if swinging else "", player.combat.phase_time)
