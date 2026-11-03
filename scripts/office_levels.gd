class_name OfficeLevels
extends Node3D

var office: Node3D
var level := 1
var unlocked := 1
var done: Array[bool] = [false, false, false]
var has_coffee := false
var repair_time := 0.0
var mouse_holding := false
var server: Node3D
var marker: Node3D
var delivery_spot: Node3D
var task_prop: PhysicsProp
var panel: PanelContainer
var checklist: Label
var action_button: Button
var notice: Label

func setup(owner_office: Node3D) -> void:
	office = owner_office
	_build_world()
	_build_hud()
	set_level(1)

func _build_world() -> void:
	server = Node3D.new()
	server.name = "RepairServer"
	add_child(server)
	server.position = Vector3(-11.4, 0, 9.4)
	var cabinet := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.7, 0.65)
	cabinet.mesh = box
	cabinet.position.y = 0.85
	cabinet.material_override = AssetCatalog.get_shared_material("level_server", Color("344657"), 0.5)
	server.add_child(cabinet)
	for y in [0.42, 0.72, 1.02, 1.32]:
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(0.62, 0.035, 0.02)
		strip.mesh = strip_mesh
		strip.position = Vector3(0, y, 0.335)
		strip.material_override = AssetCatalog.get_shared_material("server_lights", Color("e5aa53"), 0.5)
		server.add_child(strip)
	marker = _world_label(server, "!", Vector3(0, 2.1, 0), Color("ffbd59"), 72)
	var badge := Sprite3D.new()
	var badge_image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for x in range(96):
		for y in range(96):
			var distance := Vector2(x - 47.5, y - 47.5).length()
			badge_image.set_pixel(x, y, Color("263747") if distance < 44.0 else Color.TRANSPARENT)
	badge.texture = ImageTexture.create_from_image(badge_image)
	badge.pixel_size = 0.008
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	marker.add_child(badge)
	badge.position = Vector3(0, 0, -0.02)
	delivery_spot = Node3D.new()
	delivery_spot.position = Vector3(-4.0, 0.035, 9.0)
	add_child(delivery_spot)
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.85
	cylinder.bottom_radius = 0.85
	cylinder.height = 0.035
	disc.mesh = cylinder
	disc.material_override = AssetCatalog.get_shared_material("delivery_spot", Color("e8b75c"), 0.7)
	delivery_spot.add_child(disc)
	_world_label(delivery_spot, "PLACE BOX HERE", Vector3(0, 0.8, 0), Color("ffe2a2"), 30)

func _world_label(parent: Node3D, words: String, pos: Vector3, tint: Color, font: int) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = font
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = tint
	parent.add_child(label)
	return label

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(24, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.09, 0.13, 0.94)
	style.border_color = Color("526775")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	checklist = Label.new()
	checklist.custom_minimum_size.x = 260
	checklist.add_theme_font_size_override("font_size", 17)
	checklist.add_theme_color_override("font_color", Color("f4f4e9"))
	panel.add_child(checklist)
	action_button = Button.new()
	action_button.visible = false
	action_button.custom_minimum_size = Vector2(110, 56)
	action_button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var skin := StyleBoxFlat.new()
		skin.bg_color = Color("dca451") if state == "normal" else Color("f5c879")
		skin.set_corner_radius_all(28)
		action_button.add_theme_stylebox_override(state, skin)
	action_button.add_theme_color_override("font_color", Color("182631"))
	action_button.button_down.connect(func():
		if _action_kind() == "repair": mouse_holding = true
	)
	action_button.button_up.connect(func(): mouse_holding = false)
	action_button.pressed.connect(func():
		if _action_kind() != "repair": perform_action()
	)
	layer.add_child(action_button)
	notice = Label.new()
	notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice.offset_left = -240
	notice.offset_right = 240
	notice.offset_top = 25
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_color_override("font_color", Color.WHITE)
	notice.add_theme_color_override("font_outline_color", Color("17232c"))
	notice.add_theme_constant_override("outline_size", 6)
	layer.add_child(notice)

func set_level(value: int) -> void:
	if is_instance_valid(task_prop):
		if office.player.held_prop == task_prop:
			office.player.held_prop = null
			office.player.prop_handling.cancel_charge()
		task_prop.queue_free()
		task_prop = null
	level = clampi(value, 1, 2)
	done = [false, false, false]
	has_coffee = false
	repair_time = 0.0
	mouse_holding = false
	server.visible = level == 2
	delivery_spot.visible = level == 1
	if level == 1:
		task_prop = office.spawn_prop("box", Vector3(-7.4, 0.05, 8.4))
		_world_label(task_prop, "BOX", Vector3(0, 1.0, 0), Color.WHITE, 28)
	_refresh()

func _refresh() -> void:
	var tasks: Array = ["Drink coffee", "Talk to a coworker", "Move the box to its spot"] if level == 1 else ["Fix the server", "Get coffee", "Give coffee to a coworker"]
	var completed := 0
	for task_done in done:
		if task_done: completed += 1
	checklist.text = "LEVEL %d  /  5\nTODAY'S TASKS   %d / 3\n" % [level, completed]
	for i in range(3): checklist.text += "\n%s  %s" % ["✓" if done[i] else "○", tasks[i]]
	marker.visible = level == 2 and not done[0]
	notice.text = "Level complete! Open the menu for Level 2." if level == 1 and done.all(func(v): return v) else ("All tasks complete!" if level == 2 and done.all(func(v): return v) else "")
	if done.all(func(v): return v): unlocked = maxi(unlocked, mini(level + 1, 2))

func _action_kind() -> String:
	var p: OfficePlayer = office.player
	if not p.gameplay_visible or p.busy > 0 or p.dialogue.is_open or p.equipment.is_active() or p.combat.is_busy() or p.seated or is_instance_valid(p.held_prop) or is_instance_valid(p.carried_cup): return ""
	if level == 2 and not done[0] and p.global_position.distance_to(server.global_position) < 2.0: return "repair"
	if level == 2 and has_coffee and not done[2] and p.nearby is OfficeWorker and p._can_reach_interaction(p.nearby): return "give"
	for item in get_tree().get_nodes_in_group("furniture"):
		if item is FurnitureItem and item.item_id == "coffee_station" and p._can_reach_interaction(item):
			if level == 1 and not done[0]: return "drink"
			if level == 2 and not done[1]: return "coffee"
	return ""

func perform_action() -> bool:
	match _action_kind():
		"drink":
			office.player.play_anim("drink")
			office.player.busy = 2.0
			done[0] = true
		"coffee":
			has_coffee = true
			done[1] = true
		"give":
			has_coffee = false
			done[2] = true
			var worker: OfficeWorker = office.player.nearby
			worker.show_social_speech("☕ Thank you!")
		_:
			return false
	_refresh()
	return true

func talked() -> void:
	if level == 1 and not done[1]:
		done[1] = true
		_refresh()

func _process(delta: float) -> void:
	if not is_instance_valid(office.player): return
	var p: OfficePlayer = office.player
	var playing: bool = p.gameplay_visible
	panel.visible = playing
	notice.visible = playing
	var kind := _action_kind() if playing else ""
	action_button.visible = kind != ""
	if kind == "repair":
		if mouse_holding or OfficeInput.is_pressed("interact"):
			repair_time += delta / maxf(Engine.time_scale, 0.1)
			if repair_time >= 5.0:
				done[0] = true
				repair_time = 0
				mouse_holding = false
				_refresh()
		else: repair_time = 0
	else:
		repair_time = 0
		mouse_holding = false
	if action_button.visible:
		action_button.text = ("HOLD %s\nFIX %d%%" % [OfficeInput.key_name("interact"), int(repair_time * 20)]) if kind == "repair" else ("%s\n%s" % [OfficeInput.key_name("interact"), {"drink": "DRINK", "coffee": "GET COFFEE", "give": "GIVE COFFEE"}[kind]])
		var target: Vector3 = server.global_position + Vector3.UP * 1.5 if kind == "repair" else p.global_position + Vector3.UP * 1.5
		var screen := get_viewport().get_camera_3d().unproject_position(target)
		action_button.position = Vector2(clampf(screen.x - 55, 10, get_viewport().get_visible_rect().size.x - 120), clampf(screen.y + 35, 10, get_viewport().get_visible_rect().size.y - 70))
	if level == 1 and not done[2] and is_instance_valid(task_prop) and not task_prop.is_held() and not is_instance_valid(p.held_prop):
		var diff: Vector3 = task_prop.global_position - delivery_spot.global_position
		if Vector2(diff.x, diff.z).length() < 0.85:
			done[2] = true
			_refresh()
