class_name FurniturePlacement
extends RefCounted

# Keep the architectural doorways open, including room to turn into them.
const DOORWAYS := [
	Rect2(-10.0, -2.65, 2.0, 1.30),
	Rect2(-2.0, -2.65, 2.0, 1.30),
	Rect2(7.0, -2.65, 2.0, 1.30),
	Rect2(-5.65, -6.0, 1.30, 2.0),
	Rect2(2.35, -6.0, 1.30, 2.0),
]

static func footprint(item: FurnitureItem, pos: Vector3, yaw: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half := Vector2(item.footprint_size.x, item.footprint_size.z) * 0.5
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		points.append(Vector2(pos.x, pos.z) + corner.rotated(-yaw))
	return points

static func overlaps(a: PackedVector2Array, b: PackedVector2Array, tolerance: float = 0.025) -> bool:
	# Separating axis test: rotated furniture must use its actual footprint.
	for polygon in [a, b]:
		for i in range(2):
			var edge: Vector2 = polygon[i + 1] - polygon[i]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var min_a := INF
			var max_a := -INF
			var min_b := INF
			var max_b := -INF
			for point in a:
				min_a = minf(min_a, point.dot(axis))
				max_a = maxf(max_a, point.dot(axis))
			for point in b:
				min_b = minf(min_b, point.dot(axis))
				max_b = maxf(max_b, point.dot(axis))
			if max_a <= min_b + tolerance or max_b <= min_a + tolerance:
				return false
	return true

static func get_issue(office: Node3D, item: FurnitureItem, pos: Vector3, yaw: float, ignored_actor: Node3D = null) -> String:
	var polygon := footprint(item, pos, yaw)
	for point in polygon:
		if not office.FLOOR_BOUNDS.grow(-0.08).has_point(point):
			return "Keep the whole object inside the office."
	if not item.is_rug:
		for door in DOORWAYS + OfficeExpansion.DOORWAYS + OfficeArrival.DOORWAYS:
			var rect: Rect2 = door
			var corners := PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
			if overlaps(polygon, corners):
				return "Leave the doorway clear."
		for other in office.furniture_container.get_children():
			if not other is FurnitureItem or other == item or other.is_preview or other.is_queued_for_deletion() or other.is_rug:
				continue
			if overlaps(polygon, footprint(other, other.global_position, other.global_rotation.y)):
				return "Blocked by " + other.item_title + "."

	# Architecture is represented by static colliders. Lift the query off the floor.
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(item.footprint_size.x - 0.04, 0.05), maxf(item.footprint_size.y - 0.08, 0.06), maxf(item.footprint_size.z - 0.04, 0.05))
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * (shape.size.y * 0.5 + 0.05))
	query.collision_mask = 1
	query.exclude = [item.get_rid()]
	for hit in office.get_world_3d().direct_space_state.intersect_shape(query, 128):
		if hit.collider is FurnitureItem:
			continue
		return "Blocked by a wall."

	if not item.is_rug:
		var actors: Array[Node] = office.get_tree().get_nodes_in_group("workers")
		if is_instance_valid(office.player):
			actors.append(office.player)
		var inverse := Basis(Vector3.UP, yaw).inverse()
		var half := item.footprint_size * 0.5
		for actor in actors:
			if actor == ignored_actor:
				continue
			var local: Vector3 = inverse * (actor.global_position - pos)
			var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.z, -half.z, half.z))
			if closest.distance_to(Vector2(local.x, local.z)) < 0.29:
				return "Give people room to move."
	return ""
