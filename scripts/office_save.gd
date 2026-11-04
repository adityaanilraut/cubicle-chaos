class_name OfficeSave
extends RefCounted

const SAVE_PATH := "user://office_shift.cfg"

static func _valid_fields(config: ConfigFile, section: String, fields: Dictionary) -> bool:
	for key in fields:
		if not config.has_section_key(section, key): continue
		var value = config.get_value(section, key)
		var expected: int = fields[key]
		if expected == TYPE_FLOAT and (value is float or value is int):
			if not is_finite(float(value)): return false
		elif typeof(value) != expected:
			return false
		elif value is Vector3 and not value.is_finite():
			return false
	return true

# Reject malformed structural data before touching the live office. Older saves
# may omit props and workers, but a furniture count is part of every shift save.
static func _valid_save(config: ConfigFile) -> bool:
	if not config.has_section_key("furniture", "count"):
		return false
	var furniture_ids := {}
	for item in AssetCatalog.get_catalog_items(): furniture_ids[String(item.id)] = true
	for group in ["furniture", "workers", "props"]:
		if not config.has_section_key(group, "count"): continue
		var count = config.get_value(group, "count")
		if not count is int or count < 0 or count > 5000: return false
		var prefix := {"furniture": "furniture", "workers": "worker", "props": "prop"}[group] as String
		for i in range(count):
			var section := "%s_%d" % [prefix, i]
			var fields: Dictionary = {
				"furniture": {"rotation_y": TYPE_FLOAT, "health": TYPE_FLOAT, "desk_number": TYPE_INT, "printed_pages": TYPE_INT, "meeting_anchor": TYPE_STRING, "shared_ideas": TYPE_BOOL},
				"workers": {"name": TYPE_STRING, "index": TYPE_INT, "meeting_role": TYPE_STRING, "in_meeting": TYPE_BOOL, "player_knockdowns": TYPE_INT, "leaving": TYPE_BOOL, "retaliating": TYPE_BOOL},
				"props": {"rotation": TYPE_VECTOR3, "velocity": TYPE_VECTOR3, "angular_velocity": TYPE_VECTOR3, "health": TYPE_FLOAT, "owner_grace": TYPE_FLOAT, "was_held": TYPE_BOOL, "level_task": TYPE_BOOL, "thrown_by_player": TYPE_BOOL},
			}[group]
			if not _valid_fields(config, section, fields): return false
			var pos = config.get_value(section, "position", null)
			if not pos is Vector3 or not pos.is_finite(): return false
			if group != "workers":
				var id = config.get_value(section, "id", null)
				if not id is String: return false
				if group == "furniture" and not furniture_ids.has(id): return false
				if group == "props" and not PhysicsProp.HANDLING.has(id): return false
	var player_pos = config.get_value("player", "position", Vector3.ZERO)
	if not player_pos is Vector3 or not player_pos.is_finite(): return false
	if not _valid_fields(config, "player", {"rotation_y": TYPE_FLOAT, "quest": TYPE_INT, "cup_filled": TYPE_BOOL, "health": TYPE_FLOAT, "balance": TYPE_FLOAT}): return false
	if not _valid_fields(config, "equipment", {"focus": TYPE_FLOAT, "coffee_ready": TYPE_BOOL, "snacks": TYPE_INT}): return false
	if not _valid_fields(config, "level", {"number": TYPE_INT, "unlocked": TYPE_INT, "done": TYPE_ARRAY, "has_coffee": TYPE_BOOL, "stat_baseline": TYPE_DICTIONARY}): return false
	if config.has_section("equipment_stats"):
		for key in config.get_section_keys("equipment_stats"):
			if not config.get_value("equipment_stats", key) is int: return false
	var saved_done = config.get_value("level", "done", [false, false, false])
	if saved_done.size() != 3: return false
	for value in saved_done:
		if not value is bool: return false
	for value in config.get_value("level", "stat_baseline", {}).values():
		if not value is int: return false
	return true

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
	if is_instance_valid(office.levels):
		config.set_value("level", "number", office.levels.level)
		config.set_value("level", "unlocked", office.levels.unlocked)
		config.set_value("level", "done", office.levels.done.duplicate())
		config.set_value("level", "has_coffee", office.levels.has_coffee)
		config.set_value("level", "stat_baseline", office.levels.stat_baseline.duplicate())
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
		config.set_value(section, "meeting_anchor", item.get_meta("meeting_anchor", ""))
		config.set_value(section, "shared_ideas", bool(item.get_meta("shared_ideas", false)))
	var props: Array = []
	for prop in office.props_container.get_children():
		if prop is PhysicsProp and not prop.is_queued_for_deletion():
			props.append(prop)
	config.set_value("props", "count", props.size())
	for i in range(props.size()):
		var prop: PhysicsProp = props[i]
		config.set_value("prop_%d" % i, "id", prop.prop_id)
		config.set_value("prop_%d" % i, "level_task", is_instance_valid(office.levels) and prop == office.levels.task_prop)
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
		config.set_value(section, "name", worker.worker_name)
		config.set_value(section, "index", worker.worker_index)
		config.set_value(section, "meeting_role", worker.meeting_role)
		config.set_value(section, "in_meeting", is_instance_valid(worker.meeting))
		config.set_value(section, "player_knockdowns", worker.combat.player_knockdowns)
		# A saved second knockdown resumes the departure instead of giving this
		# worker an accidental third round after load.
		config.set_value(section, "leaving", worker.combat.phase == OfficeCombat.Phase.FLEEING or worker.combat.player_knockdowns >= 2)
		config.set_value(section, "retaliating", worker.combat.target == player or worker.combat.recovery_attacker == player and worker.combat.is_down())
	return config.save(SAVE_PATH) == OK

static func load_game(office: Node3D) -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK or not _valid_save(config):
		return false
	if office == null or not is_instance_valid(office.player):
		return false
	# Older saves have no level section and retain the current session's level.
	if is_instance_valid(office.levels) and config.has_section_key("level", "number"):
		var levels: OfficeLevels = office.levels
		levels.level = clampi(int(config.get_value("level", "number", 1)), 1, 5)
		levels.unlocked = clampi(int(config.get_value("level", "unlocked", 1)), levels.level, 5)
		var saved_done = config.get_value("level", "done", [])
		levels.done = [false, false, false]
		if saved_done is Array and saved_done.size() == 3:
			for i in range(3): levels.done[i] = bool(saved_done[i])
		levels.has_coffee = bool(config.get_value("level", "has_coffee", false)) if levels.level == 2 else false
		var baseline = config.get_value("level", "stat_baseline", {})
		levels.stat_baseline = baseline if baseline is Dictionary else {}
		levels.repair_time = 0.0
		levels.mouse_holding = false
		levels.server.visible = levels.level == 2
		levels.delivery_spot.visible = levels.level == 1
		levels._refresh()
	# End paired sessions before their participants are freed.
	var routines := office.get_node_or_null("OfficeRoutines")
	if routines != null:
		for id in routines.social_sessions.keys(): routines.finish_social(id, false)
	office.player.dialogue.close()
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
	if is_instance_valid(office.levels):
		office.levels.task_prop = null
	for prop in office.props_container.get_children():
		office.props_container.remove_child(prop)
		prop.free()
	var furniture_count := int(config.get_value("furniture", "count", 0))
	for i in range(furniture_count):
		var section := "furniture_%d" % i
		var item: FurnitureItem = office.place_furniture_item(String(config.get_value(section, "id", "desk_pc")), config.get_value(section, "position", Vector3.ZERO) as Vector3, float(config.get_value(section, "rotation_y", 0.0)), false)
		item.set_meta("meeting_anchor", config.get_value(section, "meeting_anchor", ""))
		item.set_meta("shared_ideas", config.get_value(section, "shared_ideas", false))
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
	var meeting_members: Array[OfficeWorker] = []
	for i in range(worker_count):
		var role := String(config.get_value("worker_%d" % i, "meeting_role", ""))
		var identity := {}
		if config.has_section_key("worker_%d" % i, "name"):
			identity = {"name": config.get_value("worker_%d" % i, "name"), "index": config.get_value("worker_%d" % i, "index", i)}
		var worker: OfficeWorker = office.spawn_worker(config.get_value("worker_%d" % i, "position", Vector3(-3.0 + float(i), 0.0, 3.0)) as Vector3, role, identity)
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
		if bool(config.get_value(section, "in_meeting", false)) and not worker.combat.is_engaged():
			meeting_members.append(worker)
	if is_instance_valid(office.life): office.life.restore(meeting_members)
	var prop_count := int(config.get_value("props", "count", 0))
	var held_bat: PhysicsProp
	if not config.has_section_key("props", "count"):
		office._spawn_props()
	else:
		for i in range(prop_count):
			var prop: PhysicsProp = office.spawn_prop(String(config.get_value("prop_%d" % i, "id", "book")), config.get_value("prop_%d" % i, "position", Vector3.ZERO) as Vector3)
			if is_instance_valid(office.levels) and office.levels.level == 1 and bool(config.get_value("prop_%d" % i, "level_task", false)):
				office.levels.task_prop = prop
				office.levels._world_label(prop, "BOX", Vector3(0, 1.0, 0), Color.WHITE, 28)
			prop.health = float(config.get_value("prop_%d" % i, "health", prop.health))
			prop.global_rotation = config.get_value("prop_%d" % i, "rotation", Vector3.ZERO)
			prop.linear_velocity = config.get_value("prop_%d" % i, "velocity", Vector3.ZERO)
			prop.angular_velocity = config.get_value("prop_%d" % i, "angular_velocity", Vector3.ZERO)
			var was_held := bool(config.get_value("prop_%d" % i, "was_held", false))
			if was_held and prop.prop_id == "baseball_bat" and not is_instance_valid(held_bat):
				held_bat = prop
				continue
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
	if is_instance_valid(held_bat):
		held_bat.pick_up(player)
		player.held_prop = held_bat
		held_bat.global_transform = BaseballBat.held_pose(player)
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
