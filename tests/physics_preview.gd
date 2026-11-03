extends SceneTree

# Visual QA fixture, deliberately outside the furnished floor. Run without
# --headless; screenshots are written to build/previews/physics-*.png.
var office: Node3D
const CENTER := Vector3(35, 0, 35)

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func capture(title: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://build/previews")
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join("physics-" + title + ".png"))

func _run() -> void:
	office = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.8).timeout
	office.game_menu.pause_on_focus_loss = false
	office.game_menu.start_game()
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for worker in office.workers_container.get_children(): worker.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14, 0.1, 12)
	shape.shape = box
	floor_body.add_child(shape)
	var floor_visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	floor_visual.mesh = mesh
	floor_visual.material_override = AssetCatalog.get_shared_material("preview_floor", Color(0.80, 0.77, 0.68), 0.8)
	floor_body.add_child(floor_visual)
	root.add_child(floor_body)
	floor_body.position = CENTER + Vector3(0, -0.05, 0)
	var plant: FurnitureItem = office.place_furniture_item("potted_plant", CENTER + Vector3(-2.3, 0, 0), 0, false)
	var table: FurnitureItem = office.place_furniture_item("side_table", CENTER, 0, false)
	var monitor: PhysicsProp = office.spawn_prop("monitor", CENTER + Vector3(2.2, 0, 0))
	monitor.freeze = true
	for entry in [[plant, "CERAMIC"], [table, "WOOD"], [monitor, "ELECTRONICS"]]:
		var label := Label3D.new()
		label.text = entry[1]
		label.font_size = 40
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(label)
		label.position = entry[0].global_position + Vector3(0, 1.8, 0)
	office.iso_camera.target_pos = CENTER + Vector3(0, 0, 0.2)
	office.iso_camera.target_zoom = 8.0
	office.iso_camera.target_yaw_deg = 25
	player.global_position = CENTER + Vector3(0, 0, 2.0)
	var held: PhysicsProp = office.spawn_prop("keyboard", player.global_position + Vector3(0, 0.035, 0.6))
	held.freeze = true
	await frames(30)
	var picked := player.try_pickup_prop()
	if not picked:
		push_error("Visual fixture pickup failed: can act=%s, reach=%s, player=%s, prop=%s" % [player.prop_handling.can_act(), player.prop_handling.can_pick_up(held), player.global_position, held.global_position])
		quit(1)
		return
	for i in range(25):
		player.prop_handling.tick(1.0 / 60)
		await frames(1)
	await capture("intact-carry")
	for body in [plant, table, monitor]: body.take_damage(body.max_health * 0.45, Vector3.RIGHT)
	player.prop_handling.begin_charge()
	for i in range(50):
		player.prop_handling.tick(1.0 / 60)
		await frames(1)
	await capture("damaged-aim")
	player.prop_handling.cancel_charge()
	for body in [plant, table, monitor]: body.take_damage(1000, Vector3.RIGHT)
	await frames(10)
	await capture("fractured")
	print("Physics visual previews saved to build/previews/physics-*.png")
	quit()
