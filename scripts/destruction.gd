class_name Destruction
extends RefCounted

const MAX_DEBRIS := 80
const MAX_EFFECTS := 24

# Family recipes produce bounded, recognizable low-poly parts. Only the
# larger pieces simulate physics; chips, soil and sparks are visual effects.

static func debris_color_for(item_id: String) -> Color:
	return DestructionProfile.for_item(item_id).color

static func spawn_debris(parent: Node, origin: Vector3, footprint: Vector3, color: Color, count: int, direction: Vector3 = Vector3.ZERO) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var remaining := MAX_DEBRIS - parent.get_tree().get_nodes_in_group("destruction_debris").size()
	for i in range(mini(count, remaining)):
		var chunk := DebrisChunk.new()
		var size := Vector3(
			randf_range(0.08, maxf(0.16, footprint.x * 0.35)),
			randf_range(0.06, maxf(0.14, footprint.y * 0.30)),
			randf_range(0.08, maxf(0.16, footprint.z * 0.35))
		)
		var varied := color.lightened(randf_range(-0.12, 0.18))
		var velocity := direction * randf_range(1.0, 2.4) + Vector3(randf_range(-1.6, 1.6), randf_range(1.6, 3.4), randf_range(-1.6, 1.6))
		parent.add_child(chunk)
		chunk.global_position = origin + Vector3(randf_range(-0.25, 0.25), randf_range(0.05, 0.45), randf_range(-0.25, 0.25))
		chunk.setup(size, varied, velocity)

static func spawn_chips(parent: Node, origin: Vector3, color: Color, direction: Vector3 = Vector3.ZERO) -> void:
	spawn_debris(parent, origin, Vector3(0.22, 0.18, 0.22), color, 2, direction)

static func spawn_material_effect(parent: Node, origin: Vector3, profile: DestructionProfile, broken: bool, direction: Vector3) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return
	if parent.get_tree().get_nodes_in_group("material_effects").size() >= MAX_EFFECTS: return
	var effect := MaterialBurst.new()
	parent.add_child(effect)
	effect.global_position = origin
	effect.setup(profile, broken, direction)

static func spawn_fracture(parent: Node, transform: Transform3D, size: Vector3, profile: DestructionProfile, direction: Vector3) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return
	spawn_material_effect(parent, transform.origin + Vector3.UP * size.y * 0.4, profile, true, direction)
	var parts := _fracture_parts(size, profile)
	var remaining := MAX_DEBRIS - parent.get_tree().get_nodes_in_group("destruction_debris").size()
	for i in range(mini(parts.size(), remaining)):
		var part: Dictionary = parts[i]
		var chunk := DebrisChunk.new()
		chunk.part_name = part.name
		chunk.name = part.name
		parent.add_child(chunk)
		chunk.global_transform = transform * Transform3D(Basis(Vector3.UP, part.get("yaw", 0.0)), part.at)
		var velocity: Vector3 = direction * randf_range(0.9, 1.6) + transform.basis * part.at.normalized() * randf_range(0.4, 1.2) + Vector3.UP * randf_range(1.0, 2.2)
		chunk.setup(part.size, part.color, velocity, part.get("mesh"), profile, part.get("material", ""))

static func _fracture_parts(size: Vector3, profile: DestructionProfile) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	match profile.fracture_id:
		"plant":
			var radius := minf(size.x, size.z) * 0.38
			var height := maxf(size.y * 0.32, 0.09)
			for i in range(6):
				var angle := float(i) / 6.0 * TAU
				parts.append({"name": "PotShard", "size": Vector3(radius * 0.25, height, radius), "at": Vector3(cos(angle) * radius * 0.8, height * 0.5, sin(angle) * radius * 0.8), "yaw": -angle, "color": profile.color.lightened(float(i % 3) * 0.08), "mesh": _pot_shard(radius, height)})
			parts.append({"name": "PotBase", "size": Vector3(radius * 1.4, 0.035, radius * 1.4), "at": Vector3(0, 0.03, 0), "color": profile.color})
			parts.append({"name": "PlantStem", "size": Vector3(0.04, size.y * 0.55, 0.04), "at": Vector3(0, size.y * 0.56, 0), "color": Color(0.25, 0.42, 0.16), "material": "wood"})
		"table":
			parts.append({"name": "TabletopLeft", "size": Vector3(size.x * 0.5, 0.07, size.z), "at": Vector3(-size.x * 0.25, size.y * 0.94, 0), "color": profile.color.lightened(0.15)})
			parts.append({"name": "TabletopRight", "size": Vector3(size.x * 0.5, 0.07, size.z), "at": Vector3(size.x * 0.25, size.y * 0.94, 0), "color": profile.color.lightened(0.1)})
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					parts.append({"name": "TableLeg", "size": Vector3(0.075, size.y * 0.78, 0.075), "at": Vector3(x * size.x * 0.40, size.y * 0.40, z * size.z * 0.36), "color": profile.color})
			if profile.item_id == "side_table":
				for y in [0.35, 0.65]:
					parts.append({"name": "DrawerPanel", "size": Vector3(size.x * 0.85, size.y * 0.22, 0.045), "at": Vector3(0, size.y * y, size.z * 0.46), "color": profile.color.lightened(0.06)})
		"monitor":
			parts.append({"name": "ScreenPanel", "size": Vector3(size.x * 0.84, size.y * 0.52, 0.025), "at": Vector3(0, size.y * 0.62, size.z * 0.42), "color": Color(0.10, 0.24, 0.28)})
			parts.append({"name": "MonitorBack", "size": Vector3(size.x, size.y * 0.62, 0.04), "at": Vector3(0, size.y * 0.62, 0), "color": profile.color})
			parts.append({"name": "MonitorStand", "size": Vector3(size.x * 0.14, size.y * 0.32, 0.07), "at": Vector3(0, size.y * 0.21, 0), "color": profile.color})
			parts.append({"name": "MonitorBase", "size": Vector3(size.x * 0.48, 0.04, size.z), "at": Vector3(0, 0.03, 0), "color": profile.color})
			parts.append({"name": "CircuitBoard", "size": Vector3(size.x * 0.40, size.y * 0.29, 0.02), "at": Vector3(size.x * 0.12, size.y * 0.6, -0.04), "color": Color(0.13, 0.40, 0.22)})
			parts[0]["material"] = "glass"
			parts[2]["material"] = "metal"
			parts[3]["material"] = "metal"
		_:
			parts = DebrisFamilies.parts_for(size, profile)
	return parts

static func _pot_shard(radius: float, height: float) -> Mesh:
	# A curved section of a hollow pot, rather than a solid generic box.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in range(3):
		var a := lerpf(-PI / 6, PI / 6, float(step) / 3)
		var b := lerpf(-PI / 6, PI / 6, float(step + 1) / 3)
		var points: Array[Vector3] = []
		for r in [radius, radius * 0.80]:
			for y in [-height * 0.5, height * 0.5]:
				for angle in [a, b]: points.append(Vector3(cos(angle) * r - radius * 0.8, y, sin(angle) * r))
		for face in [[0, 1, 3, 2], [5, 4, 6, 7], [4, 5, 1, 0], [2, 3, 7, 6], [4, 0, 2, 6], [1, 5, 7, 3]]:
			for index in [face[0], face[1], face[2], face[0], face[2], face[3]]: tool.add_vertex(points[index])
	tool.generate_normals()
	return tool.commit()
