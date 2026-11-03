extends SceneTree

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

func frames(count := 4) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func ray(a: Vector3, b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a, b, 1)
	return office.get_world_3d().direct_space_state.intersect_ray(query)

func capture(pos: Vector3, zoom: float, filename: String) -> void:
	office.iso_camera.focus_on(pos)
	office.iso_camera.target_zoom = zoom
	await frames(25)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/previews/" + filename + ".png"))

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	office.player.set_physics_process(false)
	for worker in office.workers_container.get_children():
		worker.set_physics_process(false)
		worker.nav_agent.avoidance_enabled = false
		worker._enter_idle(100.0)
	# Larger floors can take longer to bake on busy machines. Wait for the
	# navigation server to publish the bake before checking actual routes.
	var map: RID = office.get_world_3d().navigation_map
	for i in range(400):
		if not office.nav_region.is_baking() and not office._nav_rebake_pending and NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await create_timer(0.05).timeout
	await frames(8)
	check(not office.nav_region.is_baking() and NavigationServer3D.map_get_iteration_id(map) > 0, "Navigation bake is ready before testing routes")

	var catalog := {}
	for def in AssetCatalog.get_catalog_items():
		catalog[def.id] = true
	for entry in ModernAssets.ITEMS:
		check(catalog.has(entry[0]) and office.build_buttons.has(entry[0]), entry[0] + " is available in the furniture editor")
		var visual := AssetCatalog.build_furniture_visual(entry[0])
		var actual := AssetCatalog.compute_node_aabb(visual.node)
		check(actual.size.x > 0 and actual.size.y > 0 and actual.size.z > 0, entry[0] + " has real geometry")
		var size: Vector3 = visual.size
		check(actual.position.x >= -size.x * 0.5 - 0.01 and actual.end.x <= size.x * 0.5 + 0.01 and actual.position.z >= -size.z * 0.5 - 0.01 and actual.end.z <= size.z * 0.5 + 0.01 and actual.end.y <= size.y + 0.01, entry[0] + " collision footprint contains its geometry")
		visual.node.free()

	# Paths must run from the existing office into the actual furnished rooms.
	var start := Vector3(-8, 0, 9.6)
	for entry in [["Datacenter", Vector3(-9, 0, 16.4)], ["IT lab", Vector3(-2, 0, 16.1)], ["Meeting", Vector3(2, 0, 16.2)], ["Bathroom 1", Vector3(9.25, 0, 18.6)], ["Bathroom 2", Vector3(12.3, 0, 18.7)]]:
		var target: Vector3 = entry[1]
		var path := NavigationServer3D.map_get_path(map, start, target, true)
		check(path.size() >= 2 and path[path.size() - 1].distance_to(target) < 0.6, entry[0] + " is reachable from the original office")
	# Visitors can enter from the east and pass through the screening arch.
	var arrival_path := NavigationServer3D.map_get_path(map, Vector3(20.5, 0, 7.0), Vector3(5.3, 0, 7.0), true)
	check(arrival_path.size() >= 2 and arrival_path[arrival_path.size() - 1].distance_to(Vector3(5.3, 0, 7.0)) < 0.6, "Entrance connects through security to the office")
	check(ray(Vector3(20.5, 1, 7), Vector3(11.5, 1, 7)).is_empty(), "Entrance and security share an unobstructed passage")
	check(not ray(Vector3(13.5, 1, 5.71), Vector3(12.5, 1, 5.71)).is_empty(), "Security arch posts block movement")
	check(not ray(Vector3(13.5, 1, 4), Vector3(12.5, 1, 4)).is_empty(), "Public lobby is separated from the staff lounge")
	for target in [Vector3(16.5, 0, -3.3), Vector3(16.5, 0, 16.3), Vector3(-9, 0, 16.4)]:
		var path := NavigationServer3D.map_get_path(map, Vector3(20.5, 0, 7), target, true)
		check(path.size() >= 2 and path[0].distance_to(Vector3(20.5, 0, 7)) < 0.4 and path[path.size() - 1].distance_to(target) < 0.4, "Arrival connects to room at " + str(target))
	var rack_count := 0
	for item in office.furniture_container.get_children():
		if item.item_id in ["server_rack", "network_rack"] and item.position.x < -5 and item.position.z > 12:
			rack_count += 1
	check(rack_count == 6, "Data center contains two three-rack banks")
	check(ray(Vector3(-9, 1, 12.8), Vector3(-9, 1, 18.0)).is_empty(), "Data center service aisle stays clear")
	check(not ray(Vector3(-12, 1, 11.5), Vector3(-12, 1, 12.5)).is_empty(), "Clear glass walls physically block actors")
	check(ray(Vector3(-9, 1, 11.5), Vector3(-9, 1, 12.5)).is_empty(), "Datacenter portal is open")
	check(ray(Vector3(8.5, 1, 11.5), Vector3(8.5, 1, 12.5)).is_empty(), "Bathroom portal is open")
	# Check the furnished additions themselves, including their rotated bounds
	# and collisions with the architecture, rather than just their room centers.
	var reception_count := 0
	for item in office.furniture_container.get_children():
		if item.item_id == "reception_desk": reception_count += 1
		if item.position.x > 13 or (item.position.x < -5 and item.position.z > 12):
			var issue: String = office.get_placement_issue(item, item.global_position, item.global_rotation.y)
			check(issue.is_empty(), item.item_title + " has clearance at " + str(item.position) + ": " + issue)
	check(reception_count == 1, "Office has a single dedicated reception desk")

	var probe := FurnitureItem.new()
	probe.setup("chair_desk")
	probe.set_preview_mode(true)
	office.add_child(probe)
	await frames()
	check(office.get_placement_issue(probe, Vector3(-9, 0, 12), 0) == "Leave the doorway clear.", "Editor protects the datacenter entrance")
	check(office.get_placement_issue(probe, Vector3(11.5, 0, 12), 0) == "Leave the doorway clear.", "Editor protects the second bathroom entrance")
	for point in [Vector3(20, 0, 7), Vector3(17, 0, 7), Vector3(13, 0, 7), Vector3(16.5, 0, -2), Vector3(16.5, 0, 12)]:
		check(office.get_placement_issue(probe, point, 0) == "Leave the doorway clear.", "Editor protects the new arrival and room entrances at " + str(point))
	check(office.get_placement_issue(probe, Vector3(-2, 0, 16), 0).is_empty(), "New wing floor accepts furniture")
	check(not office.get_placement_issue(probe, Vector3(0, 0, 20), 0).is_empty(), "Expanded boundary rejects overhanging furniture")
	probe.queue_free()

	# Real player input crosses the old hard-coded southern boundary.
	office.iso_camera.target_yaw_deg = 0
	office.iso_camera.rotation_degrees.y = 0
	office.player.global_position = Vector3(20.4, 0, 7)
	office.player.set_physics_process(true)
	key(KEY_A, true)
	await frames(200)
	key(KEY_A, false)
	office.player.set_physics_process(false)
	check(office.player.global_position.x < 12.4, "Player can walk from the exterior landing through entrance and security (ended at " + str(office.player.global_position) + ")")
	check(absf(office.player.global_position.z - 7) < 0.1, "Arrival route needs no detour around furniture")
	office.player.global_position = Vector3(-9, 0, 9.4)
	office.player.set_physics_process(true)
	key(KEY_S, true)
	await frames(45)
	key(KEY_S, false)
	office.player.set_physics_process(false)
	check(office.player.global_position.z > 10.5, "Player can walk beyond the original floor into the new wing")
	office.iso_camera.focus_on(Vector3(0, 0, 19))
	check(is_equal_approx(office.iso_camera.target_pos.z, 19), "Camera can follow to the back of the wing")

	var glass: FurnitureItem = office.place_furniture_item("glass_partition", Vector3(30, 0, 30), 0, false)
	glass.set_preview_mode(true)
	glass.set_preview_mode(false)
	var pane: MeshInstance3D = glass.visual_root.get_child(0).get_child(0)
	var mat: StandardMaterial3D = pane.get_active_material(0)
	check(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.albedo_color.a < 0.3, "Glass stays transparent after moving or cancelling a preview")
	glass.queue_free()

	if "--capture" in OS.get_cmdline_user_args():
		office.iso_camera.target_yaw_deg = 45
		await capture(Vector3(4, 0, 5), 45, "expanded-office")
		await capture(Vector3(16.5, 0, 5.2), 20, "welcome-lobby")
		await capture(Vector3(16.5, 0, -5.5), 13, "visitor-meeting")
		await capture(Vector3(16.5, 0, 16), 13, "it-support")
		await capture(Vector3(0, 0, 15.4), 23, "modern-wing")
		await capture(Vector3(-9, 0, 16), 11, "datacenter")
		await capture(Vector3(9.5, 0, 16), 10, "bathrooms")
	print("EXPANSION CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	root.remove_child(office)
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
