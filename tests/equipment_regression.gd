extends SceneTree

var failures: Array[String] = []
var checks := 0
var office: Node3D
var player: OfficePlayer
var equipment: OfficeEquipment
var item: FurnitureItem
var origin := Vector3(2, 0, 5)

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func settle(frames := 3) -> void:
	for index in range(frames):
		await physics_frame
		await process_frame

func fixture(id: String) -> FurnitureItem:
	equipment.cancel()
	if player.seated:
		equipment.release_lounge_seat()
		player.seated = false
		player.sitting_chair = null
	player.busy = 0.0
	player.standing_up = false
	player.global_position = origin
	if is_instance_valid(item): item.queue_free()
	await settle()
	item = office.place_furniture_item(id, origin + Vector3(0, 0, 1.2), 0.0, false)
	await settle()
	return item

func complete(id: String) -> void:
	check(equipment.perform(id, item), "Can begin " + id)
	if equipment.is_active(): equipment.tick(equipment.duration + 0.01)
	check(not equipment.is_active() and item.reserved_by != player, "Completing " + id + " releases its reservation")

func capture_scene(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	office.iso_camera.target_zoom = 8.0
	office.iso_camera.focus_on(player.global_position + Vector3(0, 0, 0.6))
	player._update_nearby()
	await settle(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/office-equipment-" + label + ".png")

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	player = office.player
	equipment = player.equipment
	player.set_physics_process(false)
	player.nav_agent.avoidance_enabled = false
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)
		worker.nav_agent.avoidance_enabled = false
		worker.global_position = Vector3(-11, 0, 8)

	await fixture("desk_pc")
	item.owner_worker = office.workers_container.get_child(0)
	check(not equipment.perform("eq_report", item), "Personal workstation ownership is respected")
	item.owner_worker = null
	var departed := Node.new()
	item.reserved_by = departed
	departed.free()
	check(not item.is_in_use(), "Freed reservations are ignored safely")
	item.reserved_by = null
	var cup := Node3D.new()
	office.add_child(cup)
	player.carried_cup = cup
	check(not equipment.perform("eq_report", item), "Work equipment requires free hands")
	player.carried_cup = null
	cup.queue_free()
	check(equipment.perform("eq_report", item), "Free workstation starts a real timed report")
	check(item.reserved_by == player and item.is_in_use(), "Active use reserves exactly the current object")
	check(int(equipment.stats.reports_ready) == 0, "A report is not awarded before completion")
	equipment.tick(2.0)
	check(equipment.remaining > 4.0 and equipment.remaining < 6.0, "Progress advances over simulation time")
	await capture_scene("report-progress")
	var before := equipment.remaining
	office.game_menu.pause_game()
	player.set_physics_process(true)
	await create_timer(0.08, true).timeout
	check(is_equal_approx(equipment.remaining, before), "Pause freezes equipment progress")
	player.set_physics_process(false)
	office.game_menu.start_game()
	equipment.tick(20.0)
	check(int(equipment.stats.reports_ready) == 1 and item.reserved_by == null, "Completed report becomes printable work and releases workstation")
	check(not equipment.perform("eq_report", item), "Report cooldown prevents immediate repetition")

	await fixture("printer_station")
	check(not equipment.perform("eq_collect", item), "An empty printer tray cannot produce pages")
	complete("eq_print")
	check(int(equipment.stats.reports_ready) == 0 and int(item.get_meta("printed_pages", 0)) == 1, "Printing consumes one draft and leaves output at this printer")
	check(is_instance_valid(item.printer_output), "Printed pages have a visible paper stack and ready label")
	await capture_scene("printer-output")
	complete("eq_collect")
	check(int(equipment.stats.pages_held) == 1 and int(item.get_meta("printed_pages", 0)) == 0 and item.printer_output == null, "Collecting transfers output once and clears the tray")
	check(not equipment.perform("eq_print", item), "Printer cannot print without another completed report")

	await fixture("filing_cabinet")
	complete("eq_file")
	check(int(equipment.stats.reports_archived) == 1 and int(equipment.stats.pages_held) == 0, "Filing stores the report and removes held pages")
	complete("eq_retrieve")
	check(int(equipment.stats.reports_archived) == 0 and int(equipment.stats.pages_held) == 1, "Retrieval returns a stored report without duplicating it")
	check(not equipment.perform("eq_retrieve", item), "Empty archive cannot duplicate documents")

	await fixture("tv_presentation")
	check(not equipment.perform("eq_present", item), "Presentation requires prepared notes")
	await fixture("conference_table")
	complete("eq_review")
	check(int(equipment.stats.notes_ready) == 1, "Reviewing printed work produces presentation notes")
	await fixture("tv_presentation")
	complete("eq_present")
	check(int(equipment.stats.presentations) == 1 and int(equipment.stats.pages_held) == 0 and int(equipment.stats.notes_ready) == 0, "Presentation consumes one prepared report and records completion")

	await fixture("coffee_station")
	player.combat.health = 50.0
	player.combat.balance = 40.0
	equipment.focus = 30.0
	check(not equipment.perform("eq_drink_coffee", item), "Coffee must be brewed before drinking")
	complete("eq_coffee")
	complete("eq_drink_coffee")
	check(not equipment.coffee_ready and player.combat.health > 50 and player.combat.balance > 40 and equipment.focus > 30, "Coffee restores health, balance, and focus")
	check(not equipment.perform("eq_coffee", item), "Coffee station has a replenishment cooldown")
	await fixture("fridge")
	complete("eq_snack")
	check(equipment.snacks == 1, "Fridge supplies a usable snack")
	await fixture("kitchen_counter")
	complete("eq_meal")
	check(equipment.snacks == 0 and int(equipment.stats.meals_prepared) == 1, "Kitchen prepares a meal using a real snack")
	check(not equipment.perform("eq_meal", item), "Kitchen cannot prepare a meal without ingredients")

	await fixture("lounge_sofa")
	check(equipment.perform("eq_relax", item), "Sofa offers a timed seated rest")
	check(player.seated and player.sitting_chair == item and item.reserved_by == player, "Lounge rest is seated and reserves the sofa")
	equipment.tick(8.0)
	check(player.seated and int(equipment.stats.rest_breaks) == 1, "Completed rest restores resources and leaves player seated")
	await capture_scene("seated-lounge")
	player.interact()
	check(player.standing_up and player.seated, "Standing from the lounge begins a seated-to-standing transition")
	for i in range(240):
		if not player.standing_up: break
		player._physics_process(1.0 / 60.0)
		await settle(1)
	check(not player.seated and item.reserved_by == null and item.to_local(player.global_position).z > item.footprint_size.z * 0.5, "Standing leaves the lounge through its front and releases the seat")

	await fixture("laptop_desk")
	equipment.tick(20)
	var drafts_before := int(equipment.stats.reports_ready)
	check(equipment.perform("eq_report", item), "Can start a report for interruption checks")
	equipment.tick(1)
	player._update_nearby()
	check(player.get_context_actions().size() == 1 and player.get_context_actions()[0].id == "cancel_activity", "Busy equipment shows a single valid Cancel circle")
	player.perform_context_action("cancel_activity", item)
	check(not equipment.is_active() and item.reserved_by == null and int(equipment.stats.reports_ready) == drafts_before, "Cancelling releases the object without awarding partial work")
	check(equipment.perform("eq_report", item), "Cancelled work can be retried")
	item.global_position.x += 0.2
	equipment.tick(1)
	check(not equipment.is_active() and item.reserved_by == null and int(equipment.stats.reports_ready) == drafts_before, "Moved equipment cancels safely without rewards")
	check(equipment.perform("eq_report", item), "Still-reachable moved equipment can be used again")
	player.interrupt_for_combat()
	check(not equipment.is_active() and item.reserved_by == null, "Combat immediately cancels activity and releases reservation")
	check(equipment.perform("eq_report", item), "Can begin before deletion")
	item.queue_free()
	equipment.tick(1)
	check(not equipment.is_active() and int(equipment.stats.reports_ready) == drafts_before, "Deleted target cannot produce an item after cancellation")
	await settle()

	# All dedicated catalog objects expose at least one meaningful activity type.
	for id in OfficeEquipment.SUPPORTED:
		await fixture(id)
		check(not equipment._item_actions(item).is_empty(), "Dedicated activity exists for " + id)

	print("Equipment regression: %d checks, %d failures" % [checks, failures.size()])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
