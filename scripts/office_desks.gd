class_name OfficeDesks
extends RefCounted

# Personal desk/chair ownership and break-spot queries.
# State stays on the office and workers; this module only operates on it.
var office: Node3D

func _init(p_office: Node3D) -> void:
	office = p_office

func desk_is_available(desk: FurnitureItem, requester: OfficeWorker = null) -> bool:
	return is_instance_valid(desk) and desk.is_desk and not desk.is_queued_for_deletion() and not desk.is_preview and not is_instance_valid(desk.being_moved_by) and (not is_instance_valid(desk.owner_worker) or desk.owner_worker == requester) and (not is_instance_valid(desk.reserved_by) or desk.reserved_by == requester)

func find_nearby_desk(pos: Vector3, requester: OfficeWorker = null) -> FurnitureItem:
	var best_desk: FurnitureItem = null
	var best_dist := 1.75
	for item in office.furniture_container.get_children():
		if not item is FurnitureItem or not desk_is_available(item, requester):
			continue
		var distance: float = item.global_position.distance_to(pos)
		if distance < best_dist:
			best_dist = distance
			best_desk = item
	return best_desk

func reconcile_desk_assignments() -> void:
	if office.furniture_container == null:
		return
	# Rebuild desk claims from the actual chair/desk geometry. Preserve every
	# valid existing pair before assigning displaced workers to spare desks.
	for item in office.furniture_container.get_children():
		if item is FurnitureItem and item.is_desk:
			if item.desk_number == 0:
				item.desk_number = office._next_desk_number
				office._next_desk_number += 1
			item.owner_worker = null
	if office.workers_container != null:
		for worker in office.workers_container.get_children():
			if not worker is OfficeWorker:
				continue
			var chair: FurnitureItem = worker.assigned_chair
			var desk: FurnitureItem = worker.assigned_desk
			if is_instance_valid(chair) and not chair.is_queued_for_deletion() and desk_is_available(desk, worker) and chair.global_position.distance_to(desk.global_position) < 1.75:
				# Keep ownership while the pair is temporarily being edited.
				desk.owner_worker = worker
				chair.owner_worker = worker
				chair.paired_desk = desk
				chair.desk_number = desk.desk_number
			else:
				worker.assigned_desk = null
		for worker in office.workers_container.get_children():
			if worker is OfficeWorker:
				get_or_assign_personal_chair(worker)
				worker._update_label()
	for item in office.furniture_container.get_children():
		if not item is FurnitureItem or not item.is_chair or item.is_queued_for_deletion():
			continue
		if not is_instance_valid(item.owner_worker):
			item.owner_worker = null
			item.paired_desk = find_nearby_desk(item.global_position)
			item.desk_number = item.paired_desk.desk_number if is_instance_valid(item.paired_desk) else 0

func claim_personal_chair(requester: OfficeWorker, chair: FurnitureItem, desk: FurnitureItem) -> FurnitureItem:
	var previous: FurnitureItem = requester.assigned_chair
	if is_instance_valid(previous) and previous != chair:
		if previous.owner_worker == requester:
			previous.owner_worker = null
		if previous.reserved_by == requester:
			previous.reserved_by = null
	var previous_desk: FurnitureItem = requester.assigned_desk
	if is_instance_valid(previous_desk) and previous_desk != desk and previous_desk.owner_worker == requester:
		previous_desk.owner_worker = null
	chair.owner_worker = requester
	chair.reserved_by = requester
	chair.paired_desk = desk
	desk.owner_worker = requester
	if desk.desk_number == 0:
		desk.desk_number = office._next_desk_number
		office._next_desk_number += 1
	chair.desk_number = desk.desk_number
	requester.assigned_chair = chair
	requester.assigned_desk = desk
	return chair

func get_or_assign_personal_chair(requester: OfficeWorker) -> FurnitureItem:
	var current: FurnitureItem = requester.assigned_chair
	if is_instance_valid(current) and not current.is_queued_for_deletion() and current.is_chair:
		if current.is_preview or is_instance_valid(current.being_moved_by):
			return null
		if not is_instance_valid(current.owner_worker) or current.owner_worker == requester:
			if is_instance_valid(requester.assigned_desk) and (requester.assigned_desk.is_preview or is_instance_valid(requester.assigned_desk.being_moved_by)):
				return null
			var desk := find_nearby_desk(current.global_position, requester)
			if desk != null:
				return claim_personal_chair(requester, current, desk)
			if is_instance_valid(requester.assigned_desk) and requester.assigned_desk.owner_worker == requester:
				requester.assigned_desk.owner_worker = null
			requester.assigned_desk = null
			current.paired_desk = null
			current.desk_number = 0
			return null
	# Never let an owned chair steal a neighbouring workstation after a move.
	for item in office.furniture_container.get_children():
		if not item is FurnitureItem or not item.is_chair or item.is_queued_for_deletion() or item.is_preview or is_instance_valid(item.being_moved_by):
			continue
		if item.is_in_use():
			continue
		if is_instance_valid(item.owner_worker) and item.owner_worker != requester:
			continue
		var desk := find_nearby_desk(item.global_position, requester)
		if desk != null:
			return claim_personal_chair(requester, item, desk)
	return null

func break_spot_available(item: FurnitureItem, requester: OfficeWorker) -> bool:
	return not item.is_queued_for_deletion() and not item.is_preview and not is_instance_valid(item.being_moved_by) and (not is_instance_valid(item.reserved_by) or item.reserved_by == requester)

# One shared spot query: callers differ only by the capability predicate.
func pick_spot(matches: Callable, requester: OfficeWorker = null) -> FurnitureItem:
	var spots: Array[FurnitureItem] = []
	for c in office.furniture_container.get_children():
		if c is FurnitureItem and matches.call(c) and break_spot_available(c, requester):
			spots.append(c)
	return spots[randi() % spots.size()] if not spots.is_empty() else null

func find_water_dispenser(requester: OfficeWorker = null) -> FurnitureItem:
	return pick_spot(func(c: FurnitureItem): return c.has_break_tag("water"), requester)

func find_tagged_spot(tag: String, requester: OfficeWorker = null) -> FurnitureItem:
	return pick_spot(func(c: FurnitureItem): return c.has_break_tag(tag), requester)

func find_break_spot(requester: OfficeWorker = null) -> FurnitureItem:
	return pick_spot(func(c: FurnitureItem): return c.is_break_spot or c.has_break_tag("water"), requester)
