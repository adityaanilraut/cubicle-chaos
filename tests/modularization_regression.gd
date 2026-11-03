extends SceneTree

# Verifies shared, catalog-driven behaviour: objects get qualities from
# profiles/flags, never from consumers naming individual item ids.
var failures: Array[String] = []
var checks := 0
var office: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func settle(frames := 3) -> void:
	for i in range(frames):
		await physics_frame
		await process_frame

func fixture(id: String, pos: Vector3) -> FurnitureItem:
	var item: FurnitureItem = office.place_furniture_item(id, pos, 0.0, false)
	await settle()
	return item

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.7).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker._enter_idle(100.0)

	# Every workstation-profile object shares the report activity and cup surface.
	for id in ["desk_pc", "laptop_desk", "exec_desk", "desk_plain", "computer_set"]:
		var item := await fixture(id, Vector3(30, 0, 30))
		check(office.player.equipment.handles(item), id + " handles equipment via profile")
		check(office.player.equipment._item_actions(item) == ["eq_report"], id + " shares workstation actions")
		item.queue_free()
		await settle()

	# Same-profile archive/coffee/fridge objects share actions without id lists.
	for pair in [["filing_cabinet", "bookcase_wide"], ["coffee_station", "coffee_station"]]:
		var a := await fixture(pair[0], Vector3(30, 0, 30))
		var b := await fixture(pair[1], Vector3(34, 0, 30))
		check(a.equipment_actions() == b.equipment_actions() and not a.equipment_actions().is_empty(), pair[0] + "/" + pair[1] + " share profile actions")
		a.queue_free()
		b.queue_free()
		await settle()

	# Decorative objects have no equipment, are not break spots, and cannot hold cups.
	var plant := await fixture("potted_plant", Vector3(30, 0, 30))
	check(not office.player.equipment.handles(plant), "Plant has no equipment activity")
	check(not plant.is_break_spot and office.find_break_spot() != plant, "Plant is not an NPC break spot")
	check(not plant.can_hold_cup(), "Plant cannot hold a cup")
	plant.queue_free()
	await settle()

	# Any lounge-profile seat is a seat the equipment relax flow recognises.
	for id in ["lounge_sofa", "lounge_chair"]:
		var seat := await fixture(id, Vector3(30, 0, 30))
		check(seat.is_seat() and seat.is_lounge_seat(), id + " is a lounge seat via profile")
		check(office.player.equipment.handles(seat), id + " offers relax via profile")
		seat.queue_free()
		await settle()
	var chair := await fixture("chair_desk", Vector3(30, 0, 30))
	check(chair.is_seat() and not chair.is_lounge_seat(), "Desk chair is a seat but not a lounge seat")
	check(is_zero_approx(chair.place_rot_y - PI), "Desk chair carries its placement rotation as data")
	chair.queue_free()
	await settle()

	# Movability and cup behaviour come from flags, shared across objects.
	var rug := await fixture("rug", Vector3(30, 0, 30))
	check(not rug.can_player_move(), "Rug is not player-movable via flag")
	rug.queue_free()
	var table := await fixture("round_table", Vector3(30, 0, 34))
	check(table.can_hold_cup() and table.cup_round, "Round table holds cups with round clipping via flags")
	table.queue_free()
	await settle()

	# Break lookup is tag-driven: the water dispenser is found by its water tag.
	var dispenser := await fixture("water_dispenser", Vector3(30, 0, 30))
	check(dispenser.has_break_tag("water"), "Dispenser carries the water break tag")
	var found: FurnitureItem = office.find_tagged_spot("water")
	check(found != null and found.has_break_tag("water"), "Water lookup resolves through the shared tag query")
	dispenser.queue_free()
	await settle()

	# Catalog defs are cached copies: mutating a returned def cannot corrupt others.
	var def_a := AssetCatalog.get_item_def("desk_pc")
	def_a["title"] = "CORRUPTED"
	check(AssetCatalog.get_item_def("desk_pc")["title"] != "CORRUPTED", "Catalog defs are isolated copies")
	check(OfficeEquipment.SUPPORTED.has("printer_station") and not OfficeEquipment.SUPPORTED.has("potted_plant"), "Supported equipment is derived from catalog profiles")

	print("MODULARIZATION CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
