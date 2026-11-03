class_name OfficeEquipment
extends Node

# Completion is atomic: interrupted activities never consume supplies or award
# work. All timers run through the player's paused physics loop.
# Derived from catalog profiles, not a hand-maintained id list (kept as a
# named list for callers/tests that enumerate supported equipment).
static var SUPPORTED: Array[String] = _supported_ids()

static func _supported_ids() -> Array[String]:
	var ids: Array[String] = []
	for def in AssetCatalog.get_catalog_items():
		if not (def.get("equipment", []) as Array).is_empty():
			ids.append(String(def["id"]))
	return ids

const DEFINITIONS := {
	"eq_report": {"label": "Write report", "duration": 7.0, "animation": "work_standing", "working": "Writing a report", "cooldown": 2.0},
	"eq_print": {"label": "Print report", "duration": 3.0, "animation": "idle_breath", "working": "Printing a report", "cooldown": 1.0},
	"eq_collect": {"label": "Collect pages", "duration": 1.0, "animation": "work_standing", "working": "Collecting printed pages", "cooldown": 0.0},
	"eq_file": {"label": "File report", "duration": 2.5, "animation": "work_standing", "working": "Filing a report", "cooldown": 1.0},
	"eq_retrieve": {"label": "Retrieve file", "duration": 2.0, "animation": "work_standing", "working": "Retrieving a filed report", "cooldown": 1.0},
	"eq_coffee": {"label": "Brew coffee", "duration": 3.5, "animation": "watercooler", "working": "Brewing fresh coffee", "cooldown": 15.0},
	"eq_drink_coffee": {"label": "Drink coffee", "duration": 2.5, "animation": "drink", "working": "Enjoying fresh coffee", "cooldown": 0.0},
	"eq_snack": {"label": "Take snack", "duration": 2.0, "animation": "work_standing", "working": "Getting a snack", "cooldown": 12.0},
	"eq_eat": {"label": "Eat snack", "duration": 2.5, "animation": "drink", "working": "Taking a snack break", "cooldown": 0.0},
	"eq_meal": {"label": "Prepare meal", "duration": 4.5, "animation": "watercooler", "working": "Preparing and enjoying a meal", "cooldown": 8.0},
	"eq_review": {"label": "Review notes", "duration": 4.0, "animation": "work_standing", "working": "Preparing presentation notes", "cooldown": 1.0},
	"eq_present": {"label": "Present report", "duration": 5.0, "animation": "talk", "working": "Presenting your report", "cooldown": 3.0},
	"eq_relax": {"label": "Sit & relax", "duration": 6.0, "animation": "stand_to_sit", "working": "Resting in the lounge", "cooldown": 8.0},
	"eq_toilet": {"label": "Use toilet", "duration": 9.0, "animation": "stand_to_sit", "working": "Using the toilet", "cooldown": 12.0},
	"eq_shower": {"label": "Take shower", "duration": 10.0, "animation": "shower", "working": "Taking a shower", "cooldown": 15.0},
	"eq_wash_hands": {"label": "Wash hands", "duration": 5.0, "animation": "wash_hands", "working": "Washing your hands", "cooldown": 3.0}
}

var player: OfficePlayer
var active_item: FurnitureItem
var active_action := ""
var duration := 0.0
var remaining := 0.0
var focus := 100.0
var coffee_ready := false
var snacks := 0
var stats := {
	"reports_written": 0, "reports_ready": 0, "pages_printed": 0,
	"pages_held": 0, "reports_filed": 0, "reports_archived": 0,
	"notes_ready": 0, "presentations": 0, "coffees_made": 0,
	"coffees_drank": 0, "snacks_taken": 0, "snacks_eaten": 0,
	"meals_prepared": 0, "rest_breaks": 0,
	"toilet_breaks": 0, "showers_taken": 0, "hands_washed": 0
}
var cooldowns: Dictionary = {}
var _item_transform := Transform3D.IDENTITY
var _player_position := Vector3.ZERO
var _seated_for_relax := false
var bathroom: BathroomActivity

func setup(owner_player: OfficePlayer) -> void:
	player = owner_player

func handles(item: FurnitureItem) -> bool:
	return is_instance_valid(item) and not item.equipment_actions().is_empty()

func is_active() -> bool:
	return not active_action.is_empty()

func _item_actions(item: FurnitureItem) -> Array[String]:
	return item.equipment_actions() if handles(item) else []

func _available(item: FurnitureItem) -> bool:
	if not handles(item) or item.is_queued_for_deletion() or item.is_preview or is_instance_valid(item.being_moved_by):
		return false
	if item.is_desk and is_instance_valid(item.owner_worker):
		return false
	if is_instance_valid(item.reserved_by) and item.reserved_by != player:
		return false
	if item.is_in_use() and item.reserved_by != player:
		return false
	return player._can_reach_interaction(item)

func _requirement(action: String, item: FurnitureItem) -> String:
	if float(cooldowns.get(action, 0.0)) > 0.0:
		return "Ready again in %ds." % ceili(float(cooldowns[action]))
	if BathroomActivity.handles(action):
		return BathroomActivity.entry_issue(player, item)
	match action:
		"eq_report":
			if focus < 15.0: return "Take a coffee, meal, or lounge break to regain focus."
			if int(stats.reports_ready) >= 8: return "Print a finished report before writing another."
		"eq_print":
			if int(stats.reports_ready) <= 0: return "Write a report at a desk or computer first."
			if int(item.get_meta("printed_pages", 0)) > 0: return "Collect the pages in this printer's tray first."
		"eq_collect":
			if int(item.get_meta("printed_pages", 0)) <= 0: return "This printer's tray is empty."
			if int(stats.pages_held) >= 8: return "File or present a report to free space for more pages."
		"eq_file":
			if int(stats.pages_held) <= 0: return "Print and collect a report first."
		"eq_retrieve":
			if int(stats.reports_archived) <= 0: return "File a report before retrieving one."
			if int(stats.pages_held) >= 8: return "File or present a report to free space for more pages."
		"eq_coffee":
			if coffee_ready: return "Drink your freshly brewed coffee first."
		"eq_drink_coffee":
			if not coffee_ready: return "Brew a coffee first."
		"eq_snack":
			if snacks >= 3: return "Eat a snack or prepare a meal before taking more."
		"eq_eat", "eq_meal":
			if snacks <= 0: return "Take a snack from the fridge first."
		"eq_review":
			if int(stats.pages_held) <= 0: return "Bring a printed report from the printer or archive."
			if int(stats.notes_ready) >= int(stats.pages_held): return "Your notes are ready. Present this report at a table or TV."
		"eq_present":
			if int(stats.pages_held) <= 0: return "Bring a printed report from the printer or archive."
			if int(stats.notes_ready) <= 0: return "Review the report at a collaboration or conference table first."
	return ""

func get_actions(item: FurnitureItem) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_active() or not _available(item) or player.combat.is_busy() or player.busy > 0.0 or player.seated or is_instance_valid(player.carried_cup) or is_instance_valid(player.grabbed_furniture) or is_instance_valid(player.held_prop):
		return actions
	for id in _item_actions(item):
		if _requirement(id, item).is_empty():
			actions.append({"id": id, "key": OfficeInput.key_name("interact") if actions.is_empty() else OfficeInput.key_name("secondary"), "label": DEFINITIONS[id].label, "hint": "%s • %.1fs" % [DEFINITIONS[id].label, DEFINITIONS[id].duration]})
	return actions

func get_hint(item: FurnitureItem) -> String:
	if not handles(item): return ""
	if item.is_desk and is_instance_valid(item.owner_worker): return "This is %s’s personal desk. Use an unassigned workstation." % item.owner_worker.worker_name
	if is_instance_valid(item.reserved_by) and item.reserved_by != player: return "Someone is using or heading to " + item.item_title + "."
	if item.is_in_use() and item.reserved_by != player: return "Wait until this workstation is free."
	if is_instance_valid(player.carried_cup): return "Put down the water cup first; this activity needs free hands."
	if is_instance_valid(player.held_prop): return "Put down the prop first; this activity needs free hands."
	var actions := get_actions(item)
	if not actions.is_empty():
		var hints: Array[String] = []
		for action in actions:
			hints.append("[%s] %s" % [action.key, action.label])
		return "   •   ".join(hints)
	var candidates := _item_actions(item)
	# Explain the next step in each object's progression rather than an empty
	# secondary action (e.g. an empty printer tray before printing is possible).
	var preferred := candidates[0] if not candidates.is_empty() else ""
	# Hint preference is shared by every object in the same equipment group.
	match item.equipment_group:
		"printer": preferred = "eq_print"
		"coffee": preferred = "eq_drink_coffee" if coffee_ready else "eq_coffee"
		"fridge": preferred = "eq_eat" if snacks > 0 else "eq_snack"
		"archive": preferred = "eq_retrieve" if int(stats.reports_archived) > 0 else "eq_file"
	return _requirement(preferred, item) if not preferred.is_empty() else ""

func perform(action_id: String, item: FurnitureItem) -> bool:
	var allowed := false
	for action in get_actions(item):
		if action.id == action_id: allowed = true
	if not allowed or player.office.edit_mode != player.office.EditMode.SELECT:
		player.message.text = get_hint(item)
		return false
	active_item = item
	active_action = action_id
	duration = float(DEFINITIONS[action_id].duration)
	remaining = duration
	_item_transform = item.global_transform
	_player_position = player.global_position
	item.reserved_by = player
	var offset := item.global_position - player.global_position
	if offset.length_squared() > 0.01:
		player.rotation.y = atan2(offset.x, offset.z)
	player.velocity = Vector3.ZERO
	player.nav_agent.velocity = Vector3.ZERO
	player.play_anim(DEFINITIONS[action_id].animation)
	if action_id == "eq_relax":
		_seated_for_relax = true
		player.seated = true
		player.sitting_chair = item
		player.global_position = item.get_seat_world_pos()
		player.rotation.y = item.global_rotation.y
		player.collision_shape.set_deferred("disabled", true)
		_player_position = player.global_position
	if BathroomActivity.handles(action_id):
		bathroom = BathroomActivity.new()
		bathroom.begin(player, item, action_id)
	player.message.text = DEFINITIONS[action_id].working + "… [F] Cancel"
	return true

func tick(delta: float) -> bool:
	for id in cooldowns.keys():
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)
	if not is_active(): return false
	if not is_instance_valid(active_item) or active_item.is_queued_for_deletion() or active_item.is_preview or is_instance_valid(active_item.being_moved_by) or active_item.reserved_by != player:
		cancel("The object is no longer available. Activity cancelled.")
		return false
	if not active_item.global_transform.is_equal_approx(_item_transform) or player.global_position.distance_to(_player_position) > 0.15 or player.combat.is_engaged() or player.office.edit_mode != player.office.EditMode.SELECT:
		cancel("Activity interrupted. Nothing was consumed.")
		return false
	player.velocity = Vector3.ZERO
	player.nav_agent.velocity = Vector3.ZERO
	remaining = maxf(0.0, remaining - delta)
	if bathroom != null:
		bathroom.update(duration - remaining, remaining)
		if not is_active(): return false
		_player_position = player.global_position
	if _seated_for_relax and duration - remaining > 2.1:
		player.play_anim("sitting_idle")
	if remaining <= 0.0:
		_complete()
		return false
	return true

func get_progress_text() -> String:
	if not is_active(): return ""
	return "%s • %d%% • %.1fs remaining • [F] Cancel" % [DEFINITIONS[active_action].working, roundi(100.0 * (1.0 - remaining / duration)), remaining]

func get_summary() -> String:
	return "WORK  Drafts %d  •  Pages %d  •  Filed %d  •  Notes %d  •  Presented %d\nBREAK  Focus %d  •  Snacks %d  •  Coffee %s" % [int(stats.reports_ready), int(stats.pages_held), int(stats.reports_archived), int(stats.notes_ready), int(stats.presentations), roundi(focus), snacks, "ready" if coffee_ready else "—"]

func _restore(health: float, balance: float, attention: float) -> void:
	player.combat.health = minf(100.0, player.combat.health + health)
	player.combat.balance = minf(100.0, player.combat.balance + balance)
	focus = minf(100.0, focus + attention)

func _complete() -> void:
	var id := active_action
	var item := active_item
	var result := ""
	match id:
		"eq_report":
			stats.reports_written += 1; stats.reports_ready += 1; focus = maxf(0.0, focus - 15.0)
			result = "Report finished. Print it at the printer hub."
		"eq_print":
			stats.reports_ready -= 1; stats.pages_printed += 1
			item.set_printed_pages(int(item.get_meta("printed_pages", 0)) + 1)
			result = "Your report is in this printer's tray. [F] Collect pages."
		"eq_collect":
			item.set_printed_pages(int(item.get_meta("printed_pages", 0)) - 1); stats.pages_held += 1
			result = "Pages collected. File the report, or review it at a table."
		"eq_file":
			stats.pages_held -= 1; stats.reports_archived += 1; stats.reports_filed += 1
			stats.notes_ready = mini(int(stats.notes_ready), int(stats.pages_held))
			result = "Report filed. You can retrieve it from the archive later."
		"eq_retrieve":
			stats.reports_archived -= 1; stats.pages_held += 1
			result = "Report retrieved. Review it at a table to prepare a presentation."
		"eq_coffee":
			coffee_ready = true; stats.coffees_made += 1
			result = "Coffee brewed. [F] Drink coffee to restore focus."
		"eq_drink_coffee":
			coffee_ready = false; stats.coffees_drank += 1; _restore(5, 15, 30)
			result = "Coffee break complete. Focus and balance restored."
		"eq_snack":
			snacks += 1; stats.snacks_taken += 1
			result = "Snack packed. Eat it here or prepare a meal at the kitchen counter."
		"eq_eat":
			snacks -= 1; stats.snacks_eaten += 1; _restore(8, 12, 15)
			result = "Snack enjoyed. Health, balance, and focus restored."
		"eq_meal":
			snacks -= 1; stats.meals_prepared += 1; _restore(18, 25, 30)
			result = "Meal prepared and enjoyed. Health, balance, and focus restored."
		"eq_review":
			stats.notes_ready += 1; focus = maxf(0.0, focus - 5.0)
			result = "Presentation notes ready. Present at this table or the media TV."
		"eq_present":
			stats.notes_ready -= 1; stats.pages_held -= 1; stats.presentations += 1; focus = maxf(0.0, focus - 10.0)
			result = "Presentation complete! The report has been shared with the office."
		"eq_relax":
			stats.rest_breaks += 1; _restore(20, 35, 40)
			result = "Rested and refreshed. [F] Stand up when you're ready."
		"eq_toilet":
			stats.toilet_breaks += 1; _restore(0, 8, 10)
			result = "Toilet break finished. Wash your hands at the sink."
		"eq_shower":
			stats.showers_taken += 1; _restore(5, 20, 30)
			result = "Fresh from the shower. Focus and balance restored."
		"eq_wash_hands":
			stats.hands_washed += 1; _restore(0, 3, 5)
			result = "Hands washed and clean."
	if bathroom != null:
		bathroom.finish()
		bathroom = null
	if id == "eq_toilet": OfficeAudio.play_at(player.get_tree(), "splash")
	cooldowns[id] = float(DEFINITIONS[id].cooldown)
	OfficeAudio.play_at(player.get_tree(), "ding")
	var bubble_words := {"eq_coffee": "☕ Hot!", "eq_drink_coffee": "☕ Yum!", "eq_eat": "🍪 Yum!", "eq_meal": "🍽️ Yum!", "eq_present": "🎤 Ta-da!", "eq_relax": "😌 Ahh!", "eq_report": "📋 Done!", "eq_print": "🖨️ Done!", "eq_toilet": "🚽 Done!", "eq_shower": "🚿 Fresh!", "eq_wash_hands": "🧼 Clean!"}
	if bubble_words.has(id):
		player.show_social_speech(String(bubble_words[id]))
	active_action = ""
	active_item = null
	remaining = 0.0
	if is_instance_valid(item) and item.reserved_by == player and id != "eq_relax": item.reserved_by = null
	_seated_for_relax = false
	if not player.seated: player.play_anim("idle")
	player.message.text = result

func cancel(reason := "Activity cancelled. Nothing was consumed.") -> void:
	var item := active_item
	var was_active := is_active()
	if bathroom != null:
		bathroom.finish()
		bathroom = null
	active_action = ""
	active_item = null
	remaining = 0.0
	if is_instance_valid(item) and item.reserved_by == player and not _seated_for_relax: item.reserved_by = null
	if _seated_for_relax and is_instance_valid(player):
		if player.is_inside_tree(): player.stand_from_chair()
	_seated_for_relax = false
	if was_active and is_instance_valid(player) and player.is_inside_tree():
		player.message.text = reason
		if not player.combat.is_busy() and not player.seated: player.play_anim("idle")

func release_lounge_seat() -> bool:
	if not is_instance_valid(player.sitting_chair) or not player.sitting_chair.is_lounge_seat():
		return false
	if player.sitting_chair.reserved_by == player: player.sitting_chair.reserved_by = null
	var exit = player.sitting_chair.get_chair_exit_pos(player)
	if exit != null: player.global_position = exit
	return true

func _exit_tree() -> void:
	cancel("")
	if is_instance_valid(player) and is_instance_valid(player.sitting_chair) and player.sitting_chair.reserved_by == player:
		player.sitting_chair.reserved_by = null
