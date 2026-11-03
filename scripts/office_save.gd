class_name OfficeSave
extends RefCounted

const SAVE_PATH := "user://office_shift.cfg"

static func save_game(office: Node3D) -> bool:
	if office == null or not is_instance_valid(office.player):
		return false
	var config := ConfigFile.new()
	var player = office.player
	# In-progress bathroom use resumes outside the fixture after loading.
	var saved_position: Vector3 = player.equipment.bathroom.entry if player.equipment.bathroom != null else player.global_position
	if player.seated and is_instance_valid(player.sitting_chair):
		saved_position = player._stand_destination if player.standing_up else player.sitting_chair.get_chair_approach_pos()
	config.set_value("player", "position", saved_position)
	var saved_yaw: float = player.equipment.bathroom.entry_yaw if player.equipment.bathroom != null else player.global_rotation.y
	config.set_value("player", "rotation_y", saved_yaw)
	config.set_value("player", "quest", player.quest)
	config.set_value("player", "cup_filled", player.cup_filled)
	config.set_value("player", "health", player.combat.health)
	config.set_value("player", "balance", player.combat.balance)
	config.set_value("equipment", "focus", player.equipment.focus)
	config.set_value("equipment", "coffee_ready", player.equipment.coffee_ready)
	config.set_value("equipment", "snacks", player.equipment.snacks)
	for key in player.equipment.stats:
		config.set_value("equipment_stats", String(key), int(player.equipment.stats[key]))
	var furniture_items: Array = []
	for item in office.furniture_container.get_children():
		if item is FurnitureItem and not item.is_preview and not item.is_queued_for_deletion():
			furniture_items.append(item)
	config.set_value("furniture", "count", furniture_items.size())
	for i in range(furniture_items.size()):
		var item: FurnitureItem = furniture_items[i]
		var section := "furniture_%d" % i
		config.set_value(section, "id", item.item_id)
		config.set_value(section, "position", item.global_position)
		config.set_value(section, "rotation_y", item.global_rotation.y)
		config.set_value(section, "health", item.health)
		config.set_value(section, "desk_number", item.desk_number)
		config.set_value(section, "printed_pages", int(item.get_meta("printed_pages", 0)))
	var props: Array = []
	for prop in office.props_container.get_children():
		if prop is PhysicsProp and not prop.is_queued_for_deletion():
			props.append(prop)
	config.set_value("props", "count", props.size())
	for i in range(props.size()):
		var prop: PhysicsProp = props[i]
		config.set_value("prop_%d" % i, "id", prop.prop_id)
		config.set_value("prop_%d" % i, "position", prop.global_position)
		config.set_value("prop_%d" % i, "rotation", prop.global_rotation)
		config.set_value("prop_%d" % i, "velocity", prop.linear_velocity if not prop.is_held() else Vector3.ZERO)
		config.set_value("prop_%d" % i, "angular_velocity", prop.angular_velocity if not prop.is_held() else Vector3.ZERO)
		config.set_value("prop_%d" % i, "was_held", prop.is_held())
		config.set_value("prop_%d" % i, "owner_grace", prop.owner_grace if prop.release_owner == player else 0.0)
		config.set_value("prop_%d" % i, "thrown_by_player", prop.impact.thrower != null and prop.impact.thrower.get_ref() == player)
		config.set_value("prop_%d" % i, "health", prop.health)
	var workers: Array = []
	for worker in office.workers_container.get_children():
		if worker is OfficeWorker and not worker.is_queued_for_deletion():
			workers.append(worker)
	config.set_value("workers", "count", workers.size())
	for i in range(workers.size()):
		var worker := workers[i] as OfficeWorker
		var section := "worker_%d" % i
		config.set_value(section, "position", worker.global_position)
		config.set_value(section, "player_knockdowns", worker.combat.player_knockdowns)
		# A saved second knockdown resumes the departure instead of giving this
		# worker an accidental third round after load.
		config.set_value(section, "leaving", worker.combat.phase == OfficeCombat.Phase.FLEEING or worker.combat.player_knockdowns >= 2)
		config.set_value(section, "retaliating", worker.combat.target == player or worker.combat.recovery_attacker == player and worker.combat.is_down())
	return config.save(SAVE_PATH) == OK

static func load_game(office: Node3D) -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	if office == null or not is_instance_valid(office.player):
		return false
	# Clear current furniture, workers and props, then rebuild from the file.
	office.player.equipment.cancel("")
	office.player.mouse_controls.cancel()
	office.player.prop_handling.reset()
	office.player.release_furniture()
	office.player.held_prop = null
	office.player.combat.reset()
	# Effects are transient, and must not survive into a restored shift.
	for effect in office.get_tree().get_nodes_in_group("destruction_debris") + office.get_tree().get_nodes_in_group("material_effects"):
		effect.free()
	for item in office.furniture_container.get_children():
		office.furniture_container.remove_child(item)
		item.free()
	for worker in office.workers_container.get_children():
		office.workers_container.remove_child(worker)
		worker.free()
	for prop in office.props_container.get_children():
		office.props_container.remove_child(prop)
		prop.free()
	var furniture_count := int(config.get_value("furniture", "count", 0))
	for i in range(furniture_count):
		var section := "furniture_%d" % i
		var item: FurnitureItem = office.place_furniture_item(String(config.get_value(section, "id", "desk_pc")), config.get_value(section, "position", Vector3.ZERO) as Vector3, float(config.get_value(section, "rotation_y", 0.0)), false)
		item.health = float(config.get_value(section, "health", item.health))
		item.desk_number = int(config.get_value(section, "desk_number", 0))
		var printed := int(config.get_value(section, "printed_pages", 0))
		if printed > 0:
			item.set_printed_pages(printed)
		if item.health <= 0.0 and item.breakable:
			item.health = item.max_health
	office._reconcile_desk_assignments()
	office._request_navmesh_rebake()
	var worker_count := int(config.get_value("workers", "count", 6))
	for i in range(worker_count):
		var worker: OfficeWorker = office.spawn_worker(config.get_value("worker_%d" % i, "position", Vector3(-3.0 + float(i), 0.0, 3.0)) as Vector3)
		worker._enter_idle(1.0)
		var section := "worker_%d" % i
		worker.combat.player_knockdowns = maxi(0, int(config.get_value(section, "player_knockdowns", 0)))
		worker.combat.recovery_attacker = office.player
		if bool(config.get_value(section, "leaving", false)):
			worker.combat.begin_escape()
		elif bool(config.get_value(section, "retaliating", false)):
			worker.combat.target = office.player
			worker.combat.anger_time = 20.0
			worker.combat.revenge_pending = worker.combat.player_knockdowns == 1
	var prop_count := int(config.get_value("props", "count", 0))
	if not config.has_section_key("props", "count"):
		office._spawn_props()
	else:
		for i in range(prop_count):
			var prop: PhysicsProp = office.spawn_prop(String(config.get_value("prop_%d" % i, "id", "book")), config.get_value("prop_%d" % i, "position", Vector3.ZERO) as Vector3)
			prop.health = float(config.get_value("prop_%d" % i, "health", prop.health))
			prop.global_rotation = config.get_value("prop_%d" % i, "rotation", Vector3.ZERO)
			prop.linear_velocity = config.get_value("prop_%d" % i, "velocity", Vector3.ZERO)
			prop.angular_velocity = config.get_value("prop_%d" % i, "angular_velocity", Vector3.ZERO)
			var was_held := bool(config.get_value("prop_%d" % i, "was_held", false))
			prop.impact.reset(prop.linear_velocity, 0.4 if was_held else 0.0)
			var grace := 0.4 if was_held else float(config.get_value("prop_%d" % i, "owner_grace", 0.0))
			if grace > 0.0:
				prop.release_owner = office.player
				prop.owner_grace = grace
				prop.add_collision_exception_with(office.player)
			if bool(config.get_value("prop_%d" % i, "thrown_by_player", false)):
				prop.impact.thrower = weakref(office.player)
	var player = office.player
	player.seated = false
	player.standing_up = false
	player.sitting_chair = null
	player.busy = 0.0
	player.collision_shape.set_deferred("disabled", false)
	player.play_anim("idle")
	player.global_position = config.get_value("player", "position", player.global_position) as Vector3
	player.global_rotation.y = float(config.get_value("player", "rotation_y", 0.0))
	player.quest = int(config.get_value("player", "quest", 0))
	player.cup_filled = bool(config.get_value("player", "cup_filled", false))
	player.combat.health = float(config.get_value("player", "health", 100.0))
	player.combat.balance = float(config.get_value("player", "balance", 100.0))
	player.equipment.focus = float(config.get_value("equipment", "focus", 100.0))
	player.equipment.coffee_ready = bool(config.get_value("equipment", "coffee_ready", false))
	player.equipment.snacks = int(config.get_value("equipment", "snacks", 0))
	for key in player.equipment.stats:
		player.equipment.stats[key] = int(config.get_value("equipment_stats", String(key), int(player.equipment.stats[key])))
	player._update_objective()
	office._refresh_ui()
	return true
