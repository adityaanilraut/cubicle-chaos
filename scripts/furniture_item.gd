class_name FurnitureItem
extends StaticBody3D

var item_id: String = "desk_pc"
var item_title: String = "Workstation Desk (PC)"
var footprint_size: Vector3 = Vector3.ONE
var is_chair: bool = false
var is_desk: bool = false
var is_water_dispenser: bool = false
var is_break_spot: bool = false
var room_tag: String = ""
var nav_obstacle: bool = true
var is_rug: bool = false
# Shared capabilities, filled from the catalog profile (see AssetCatalog).
var seat_kind: String = ""
var equipment_group: String = ""
var break_tags: Array = []
var cup_round: bool = false
var player_movable: bool = true
var soft_collision: bool = false
var place_rot_y: float = 0.0
var _equipment_actions: Array[String] = []
var _cup_surface_indices: Array = []
var is_preview: bool = false
var being_moved_by: Node3D = null
var _preview_valid: bool = true

var reserved_by: Node = null
var owner_worker: Node = null
var paired_desk: FurnitureItem = null
var desk_number: int = 0

var visual_root: Node3D = null
var collision_shape: CollisionShape3D = null
var selection_box: MeshInstance3D = null
var printer_output: Node3D
var max_health := 0.0
var destructible: DestructibleState
var debris_profile: DestructionProfile
var health: float:
	get: return destructible.health if is_instance_valid(destructible) else max_health
	set(value):
		if is_instance_valid(destructible): destructible.restore_health(value)
var breakable := false
var _damage_shake := 0.0
var _base_visual_pos := Vector3.ZERO
var _cup_surfaces: Array[AABB] = []
var _cup_obstacles: Array[AABB] = []
const CUP_RADIUS := 0.12
const CUP_HEIGHT := 0.22
const CUP_REACH := 1.15

func setup(p_item_id: String) -> void:
	item_id = p_item_id
	var def := AssetCatalog.get_item_def(item_id)
	item_title = def.get("title", item_id.capitalize())
	is_chair = def.get("is_chair", false)
	is_desk = def.get("is_desk", false)
	is_water_dispenser = def.get("is_water_dispenser", false)
	is_break_spot = def.get("is_break_spot", false)
	room_tag = def.get("room_tag", "")
	nav_obstacle = def.get("nav_obstacle", true)
	is_rug = def.get("is_rug", false)
	seat_kind = def.get("seat", "")
	equipment_group = def.get("equipment_group", "")
	break_tags = (def.get("break_tags", []) as Array).duplicate()
	cup_round = def.get("cup_round", false)
	player_movable = def.get("player_movable", true)
	soft_collision = def.get("soft_collision", false)
	place_rot_y = def.get("place_rot_y", 0.0)
	_equipment_actions.clear()
	for action in def.get("equipment", []):
		_equipment_actions.append(String(action))
	_cup_surface_indices = (def.get("cup_surfaces", []) as Array).duplicate()

	add_to_group("furniture")
	if nav_obstacle:
		add_to_group("nav_bake")

	var built := AssetCatalog.build_furniture_visual(item_id)
	visual_root = built["node"]
	footprint_size = built["size"]
	add_child(visual_root)
	_base_visual_pos = visual_root.position
	# Every furniture type uses its family destruction profile.
	debris_profile = DestructionProfile.for_item(item_id)
	breakable = debris_profile.breakable
	if breakable:
		max_health = clampf(22.0 + footprint_size.x * footprint_size.z * 18.0, 25.0, 80.0)
		destructible = DestructibleState.new()
		add_child(destructible)
		destructible.configure(self, visual_root, footprint_size, item_id, max_health, debris_profile)

	collision_shape = CollisionShape3D.new()
	collision_shape.shape = AssetCatalog.get_box_shape(footprint_size)
	collision_shape.position = Vector3(0.0, maxf(footprint_size.y, 0.08) * 0.5, 0.0)
	add_child(collision_shape)

	# Soft objects (rugs, desktop sets) stay selectable without blocking movement.
	if soft_collision:
		collision_layer = 2
		collision_mask = 0
	else:
		collision_layer = 3
		collision_mask = 1

	_cache_cup_surfaces()
	_create_selection_indicator()

func _create_selection_indicator() -> void:
	selection_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(footprint_size.x + 0.14, 0.06, footprint_size.z + 0.14)
	selection_box.mesh = bm
	selection_box.position = Vector3(0.0, 0.03, 0.0)
	selection_box.material_override = AssetCatalog.get_shared_material(
		"selection_highlight",
		Color(0.20, 0.85, 1.0, 0.55),
		0.3,
		true
	)
	selection_box.visible = false
	add_child(selection_box)

func set_selected(selected: bool) -> void:
	if selection_box:
		selection_box.visible = selected

func set_preview_mode(preview: bool, is_valid: bool = true) -> void:
	if is_preview == preview and (not preview or _preview_valid == is_valid):
		return
	is_preview = preview
	_preview_valid = is_valid
	if collision_shape:
		collision_shape.disabled = is_preview
	if is_preview:
		remove_from_group("nav_bake")
		var mat := AssetCatalog.get_shared_material(
			"preview_valid" if is_valid else "preview_invalid",
			Color(0.25, 0.92, 0.55, 0.55) if is_valid else Color(0.95, 0.25, 0.25, 0.55),
			0.4,
			true
		)
		AssetCatalog.apply_material_recursive(visual_root, mat)
	else:
		AssetCatalog.apply_material_recursive(visual_root, null)
		AssetCatalog._tone_node_materials(visual_root)
		if is_instance_valid(destructible): destructible.apply_materials()
		if nav_obstacle and not is_in_group("nav_bake"):
			add_to_group("nav_bake")

func _process(delta: float) -> void:
	if _damage_shake > 0.0 and is_instance_valid(visual_root):
		_damage_shake = maxf(0.0, _damage_shake - delta)
		visual_root.position = _base_visual_pos + Vector3(randf_range(-0.02, 0.02), 0.0, randf_range(-0.02, 0.02)) * (_damage_shake * 8.0)
		if _damage_shake <= 0.0:
			visual_root.position = _base_visual_pos

func damage_ratio() -> float:
	return destructible.ratio() if is_instance_valid(destructible) else 0.0

func take_damage(amount: float, direction: Vector3 = Vector3.ZERO, _hit_pos: Vector3 = Vector3.ZERO) -> bool:
	if not breakable or is_preview or health <= 0.0:
		return false
	if amount <= 0.0 or is_queued_for_deletion(): return false
	var lethal := destructible.apply_damage(amount, direction, _hit_pos)
	_damage_shake = 0.18
	if is_instance_valid(visual_root):
		visual_root.rotation.z = damage_ratio() * 0.07
	if lethal:
		break_apart(direction)
		return true
	return false

func break_apart(direction: Vector3 = Vector3.ZERO) -> void:
	if is_queued_for_deletion() or not breakable or destructible.broken:
		return
	# Exclude this object from assignment/interaction queries during cleanup.
	queue_free()
	# Tell the office before freeing so workers release chairs/desks safely.
	var node: Node = self
	while node != null:
		if node.has_method("on_furniture_destroyed"):
			node.call("on_furniture_destroyed", self)
			break
		node = node.get_parent()
	destructible.spawn_fracture(direction)

func is_seat() -> bool:
	return seat_kind != ""

func is_lounge_seat() -> bool:
	return seat_kind == "lounge"

func equipment_actions() -> Array[String]:
	return _equipment_actions.duplicate()

func has_break_tag(tag: String) -> bool:
	return room_tag == tag or tag in break_tags

func can_player_move() -> bool:
	return player_movable and not is_preview and not is_instance_valid(being_moved_by)

func is_in_use() -> bool:
	if not is_inside_tree():
		return false
	if is_instance_valid(reserved_by) and reserved_by is OfficePlayer:
		return true
	for worker in get_tree().get_nodes_in_group("combatants"):
		if worker is OfficePlayer and worker.seated and worker.sitting_chair == self:
			return true
		if worker.is_seated and (worker.assigned_chair == self or worker.assigned_desk == self or (is_instance_valid(worker.meeting) and worker.target_furniture == self)):
			return true
	return false

func closest_surface_point(from: Vector3) -> Vector3:
	var local := to_local(from)
	var half := footprint_size * 0.5
	local.x = clampf(local.x, -half.x, half.x)
	local.z = clampf(local.z, -half.z, half.z)
	local.y = 0.0
	return to_global(local)

func get_owner_summary() -> String:
	if is_instance_valid(owner_worker) and "worker_name" in owner_worker:
		if desk_number > 0:
			return "Desk #%d — Owned by %s" % [desk_number, owner_worker.worker_name]
		return "Owned by %s" % owner_worker.worker_name
	if desk_number > 0:
		return "Desk #%d — Unassigned" % desk_number
	return "Unassigned"

# Local +Z is the front of every Kenney furniture model
func get_forward_dir() -> Vector3:
	return global_transform.basis.z.normalized()

# Where the worker walks on the floor to approach a chair before sitting
func get_chair_approach_pos() -> Vector3:
	var exit = get_chair_exit_pos()
	return exit if exit != null else global_position + get_forward_dir() * (footprint_size.z * 0.5 + 0.45)

func get_chair_exit_pos(actor: OfficeWorker = null) -> Variant:
	# Leave through the open front; a desk can block it, so try either side.
	# Never send a person through the backrest or into nearby furniture.
	var offsets := [Vector3(0, 0, footprint_size.z * 0.5 + 0.45), Vector3(footprint_size.x * 0.5 + 0.45, 0, 0), Vector3(-footprint_size.x * 0.5 - 0.45, 0, 0)]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.collision_shape.shape if is_instance_valid(actor) else capsule
	query.collision_mask = (1 | 4 | 8) if is_instance_valid(actor) else (1 | 8)
	var exclusions: Array[RID] = [get_rid()]
	if is_instance_valid(actor): exclusions.append(actor.get_rid())
	query.exclude = exclusions
	var space := get_world_3d().direct_space_state
	for offset in offsets:
		var point := to_global(offset)
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.845)
		if not space.intersect_shape(query, 1).is_empty(): continue
		query.transform.origin = get_seat_world_pos() + Vector3.UP * 0.845
		query.motion = point - get_seat_world_pos()
		var sweep := space.cast_motion(query)
		query.motion = Vector3.ZERO
		if sweep[0] >= 1.0: return point
	return null

# Exact floor point of the chair seat where the worker's root sits
func get_seat_world_pos() -> Vector3:
	return Vector3(global_position.x, 0.0, global_position.z)

# Where the worker stands in front of a water dispenser, coffee station, conference table, or bookcase
func get_interact_world_pos() -> Vector3:
	var dist: float = maxf(footprint_size.z * 0.5 + 0.52, 0.72)
	return global_position + get_forward_dir() * dist

# World Y angle so a character whose mesh faces +Z looks at this object
func get_look_at_object_yaw(from_pos: Vector3) -> float:
	var to_obj := global_position - from_pos
	to_obj.y = 0.0
	if to_obj.length_squared() < 0.001:
		return global_rotation.y + PI
	return atan2(to_obj.x, to_obj.z)

# Printed output belongs to the individual printer, so it remains discoverable
# if the player walks away before collecting it.
func set_printed_pages(count: int) -> void:
	count = maxi(0, count)
	set_meta("printed_pages", count)
	if is_instance_valid(printer_output):
		remove_child(printer_output)
		printer_output.queue_free()
	printer_output = null
	if count == 0: return
	printer_output = Node3D.new()
	printer_output.name = "PrintedReportTray"
	add_child(printer_output)
	var pages := MeshInstance3D.new()
	var paper := BoxMesh.new()
	paper.size = Vector3(0.38, 0.018 * minf(float(count), 5.0), 0.28)
	pages.mesh = paper
	pages.position = Vector3(0.0, footprint_size.y + 0.025, 0.08)
	pages.material_override = AssetCatalog.get_shared_material("printed_paper", Color(0.97, 0.96, 0.91), 0.8)
	printer_output.add_child(pages)
	var label := Label3D.new()
	label.text = "%d report%s ready" % [count, "s" if count != 1 else ""]
	label.position = pages.position + Vector3.UP * 0.22
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0035
	label.font_size = 28
	label.outline_size = 8
	label.modulate = Color(0.96, 0.88, 0.61)
	printer_output.add_child(label)

# Use the actual table/counter models, not the full furniture collision box:
# conference-table boxes include chairs, and counters include appliances.
func _cache_cup_surfaces() -> void:
	# Which visual children are flat cup surfaces is catalog data per item.
	var bases: Array = _cup_surface_indices
	for index in range(visual_root.get_child_count()):
		var child := visual_root.get_child(index) as Node3D
		if child == null: continue
		var bounds := AssetCatalog.compute_node_aabb(child)
		if bounds.size == Vector3.ZERO: continue
		if index in bases:
			_cup_surfaces.append(bounds)
		else:
			_cup_obstacles.append(bounds)

func can_hold_cup() -> bool:
	return not _cup_surfaces.is_empty() and not is_preview and not is_queued_for_deletion() and not is_instance_valid(being_moved_by)

func get_cup_spot(from: Vector3) -> Dictionary:
	if not can_hold_cup() or closest_surface_point(from).distance_to(from) > CUP_REACH:
		return {}
	var local := to_local(from)
	var best := CUP_REACH + 0.001
	var result := {}
	for surface in _cup_surfaces:
		var low := surface.position + Vector3(CUP_RADIUS, 0, CUP_RADIUS)
		var high := surface.end - Vector3(CUP_RADIUS, 0, CUP_RADIUS)
		if low.x > high.x or low.z > high.z: continue
		var candidates: Array[Vector3] = [Vector3(clampf(local.x, low.x, high.x), surface.end.y, clampf(local.z, low.z, high.z))]
		for x in range(5):
			for z in range(5):
				candidates.append(Vector3(lerpf(low.x, high.x, x / 4.0), surface.end.y, lerpf(low.z, high.z, z / 4.0)))
		for point in candidates:
			if cup_round and Vector2(point.x - surface.get_center().x, point.z - surface.get_center().z).length() > minf(surface.size.x, surface.size.z) * 0.5 - CUP_RADIUS:
				continue
			var cup_bounds := AABB(point + Vector3(-CUP_RADIUS, 0.01, -CUP_RADIUS), Vector3(CUP_RADIUS * 2, CUP_HEIGHT, CUP_RADIUS * 2))
			var blocked := false
			for obstacle in _cup_obstacles:
				if cup_bounds.intersects(obstacle):
					blocked = true
					break
			if blocked: continue
			var world := to_global(point)
			var distance := Vector2(world.x - from.x, world.z - from.z).length()
			if distance >= best or world.y > from.y + 1.45: continue
			best = distance
			result = {"item": self, "local_point": point, "position": world}
	return result
