class_name OfficeEditorUi
extends RefCounted

# Furniture-editor HUD: top bar, inspector, floor controls and catalog.
# Widget references stay on the office; this module builds and refreshes them.
var office: Node3D

func _init(p_office: Node3D) -> void:
	office = p_office

func make_panel_style(bg: Color, border: Color = Color(0.28, 0.34, 0.44, 0.85)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb

func setup_ui() -> void:
	var canvas := CanvasLayer.new()
	office.hud = canvas
	canvas.name = "HUD"
	office.add_child(canvas)

	office.editor_root = Control.new()
	office.editor_root.name = "FurnitureEditor"
	office.editor_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	office.editor_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(office.editor_root)

	office.editor_toggle = Button.new()
	office.editor_toggle.name = "EditorToggle"
	office.editor_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	office.editor_toggle.offset_left = -132
	office.editor_toggle.offset_right = -16
	office.editor_toggle.offset_top = 16
	office.editor_toggle.offset_bottom = 56
	office.editor_toggle.text = "Edit office"
	office.editor_toggle.focus_mode = Control.FOCUS_NONE
	office.editor_toggle.add_theme_stylebox_override("normal", make_panel_style(Color(0.08, 0.10, 0.14, 0.80)))
	office.editor_toggle.pressed.connect(func(): office.set_editor_visible(not office.editor_visible))
	canvas.add_child(office.editor_toggle)

	# Editor tools only appear after opening the editor.
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 12
	top_panel.offset_top = 10
	top_panel.offset_right = -146
	top_panel.offset_bottom = 58
	top_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.08, 0.10, 0.14, 0.92)))
	office.editor_root.add_child(top_panel)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_panel.add_child(top_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "CUBICLE CHAOS"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.94, 0.95, 0.98))
	top_hbox.add_child(title_lbl)

	office.stats_label = Label.new()
	office.stats_label.text = "Workers: 6 | Desks: 8 | Rooms: 3 + Open Floor"
	office.stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office.stats_label.add_theme_font_size_override("font_size", 13)
	office.stats_label.add_theme_color_override("font_color", Color(0.75, 0.84, 0.95))
	top_hbox.add_child(office.stats_label)

	var btn_hire1 := Button.new()
	btn_hire1.text = "+ Hire Worker"
	btn_hire1.pressed.connect(func():
		if not office._editing_blocked_by_activity():
			office.spawn_worker()
	)
	top_hbox.add_child(btn_hire1)

	var btn_view := Button.new()
	btn_view.text = "Reset view"
	btn_view.pressed.connect(func():
		office.iso_camera.pan_offset = Vector3.ZERO
		office.iso_camera.target_yaw_deg = 45.0
		office.iso_camera.target_zoom = 12.0
		if is_instance_valid(office.player):
			office.iso_camera.focus_on(office.player.global_position)
	)
	top_hbox.add_child(btn_view)

	var btn_settings := Button.new()
	btn_settings.text = "Settings"
	btn_settings.pressed.connect(func(): office.game_menu.show_settings())
	top_hbox.add_child(btn_settings)

	var btn_pause := Button.new()
	btn_pause.text = "Pause (Esc)"
	btn_pause.pressed.connect(func(): office.game_menu.pause_game())
	top_hbox.add_child(btn_pause)

	# 3. RIGHT PANEL: Furniture Inspector & Controls Guide
	var right_panel := PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -305
	right_panel.offset_top = 68
	right_panel.offset_right = -12
	right_panel.offset_bottom = -90
	right_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.08, 0.10, 0.14, 0.88)))
	office.editor_root.add_child(right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(right_scroll)
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 7)
	right_scroll.add_child(right_vbox)

	office.mode_status_label = Label.new()
	office.mode_status_label.text = "MODE: SELECT / EDIT"
	office.mode_status_label.add_theme_font_size_override("font_size", 14)
	office.mode_status_label.add_theme_color_override("font_color", Color(0.40, 0.90, 0.65))
	right_vbox.add_child(office.mode_status_label)

	office.inspector_title_label = Label.new()
	office.inspector_title_label.text = "No Furniture Selected"
	office.inspector_title_label.add_theme_font_size_override("font_size", 15)
	right_vbox.add_child(office.inspector_title_label)

	office.inspector_owner_label = Label.new()
	office.inspector_owner_label.text = ""
	office.inspector_owner_label.add_theme_font_size_override("font_size", 13)
	office.inspector_owner_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	right_vbox.add_child(office.inspector_owner_label)

	office.inspector_hint_label = Label.new()
	office.inspector_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	office.inspector_hint_label.text = "Click any furniture in the office to inspect owner, move, rotate, or delete it."
	office.inspector_hint_label.add_theme_font_size_override("font_size", 12)
	office.inspector_hint_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	right_vbox.add_child(office.inspector_hint_label)

	var act_grid := GridContainer.new()
	act_grid.columns = 2
	act_grid.add_theme_constant_override("h_separation", 6)
	act_grid.add_theme_constant_override("v_separation", 6)
	right_vbox.add_child(act_grid)

	office.btn_move = Button.new()
	office.btn_move.text = "✥ Move (M)"
	office.btn_move.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office.btn_move.pressed.connect(office.start_moving_selected)
	act_grid.add_child(office.btn_move)

	office.btn_rotate = Button.new()
	office.btn_rotate.text = "↻ Rotate (R)"
	office.btn_rotate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office.btn_rotate.pressed.connect(office.rotate_active_or_selected)
	act_grid.add_child(office.btn_rotate)

	office.btn_delete = Button.new()
	office.btn_delete.text = "🗑 Delete (Del)"
	office.btn_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office.btn_delete.pressed.connect(office.delete_selected_furniture)
	act_grid.add_child(office.btn_delete)

	office.btn_cancel = Button.new()
	office.btn_cancel.text = "Cancel edit"
	office.btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office.btn_cancel.pressed.connect(office.cancel_current_action)
	act_grid.add_child(office.btn_cancel)

	setup_floor_controls(right_vbox)

	# 4. BOTTOM BAR: Scrollable Furniture & Room Objects Catalog
	var bottom_panel := PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 12
	bottom_panel.offset_top = -76
	bottom_panel.offset_right = -12
	bottom_panel.offset_bottom = -10
	bottom_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.08, 0.10, 0.14, 0.94)))
	office.editor_root.add_child(bottom_panel)

	var bottom_scroll := ScrollContainer.new()
	bottom_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom_panel.add_child(bottom_scroll)

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 6)
	bottom_scroll.add_child(bottom_hbox)

	var select_mode_btn := Button.new()
	select_mode_btn.text = "Select / Cancel edit"
	select_mode_btn.pressed.connect(office.cancel_current_action)
	bottom_hbox.add_child(select_mode_btn)

	for item_def in AssetCatalog.get_catalog_items():
		var id: String = item_def["id"]
		var hk: String = item_def.get("hotkey", "")
		var label_text: String = item_def.get("short", item_def["title"])
		if hk != "":
			label_text = "[%s] %s" % [hk, label_text]
		var b := Button.new()
		b.text = "+ " + label_text
		b.pressed.connect(func(): office.start_placing_catalog_item(id))
		bottom_hbox.add_child(b)
		office.build_buttons[id] = b

	office.editor_root.visible = false

func setup_floor_controls(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Floor"
	heading.add_theme_font_size_override("font_size", 18)
	parent.add_child(heading)
	var hint := Label.new()
	hint.text = "Applies to every room · saves automatically"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	parent.add_child(hint)
	var color_label := Label.new()
	color_label.text = "Color"
	parent.add_child(color_label)
	var color_row := HBoxContainer.new()
	parent.add_child(color_row)
	office.floor_color_picker = ColorPickerButton.new()
	office.floor_color_picker.name = "FloorColor"
	office.floor_color_picker.edit_alpha = false
	office.floor_color_picker.color = office.floor_mat.albedo_color
	office.floor_color_picker.custom_minimum_size = Vector2(80, 34)
	office.floor_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office.floor_color_picker.tooltip_text = "Choose a floor color"
	office.floor_color_picker.color_changed.connect(func(color: Color): office.game_menu.set_setting("floor_color", color.to_html(false)))
	color_row.add_child(office.floor_color_picker)
	var match_theme := Button.new()
	match_theme.text = "Match theme"
	match_theme.pressed.connect(func(): office.game_menu.set_setting("floor_color", ""))
	color_row.add_child(match_theme)
	for kind in ["Pattern", "Texture"]:
		var label := Label.new()
		label.text = kind
		parent.add_child(label)
		var option := OptionButton.new()
		option.name = "Floor" + kind
		option.custom_minimum_size.y = 34
		var names: Array[String] = OfficeFloor.PATTERNS if kind == "Pattern" else OfficeFloor.TEXTURES
		for title in names:
			option.add_item(title)
		parent.add_child(option)
		if kind == "Pattern":
			office.floor_pattern_option = option
			option.item_selected.connect(func(idx: int): office.game_menu.set_setting("floor_pattern", idx))
		else:
			office.floor_texture_option = option
			option.item_selected.connect(func(idx: int): office.game_menu.set_setting("floor_texture", idx))

func set_editor_visible(enabled: bool) -> void:
	if enabled and is_instance_valid(office.player):
		office.player.mouse_controls.cancel()
		office.player.prop_handling.cancel_charge()
		office.player.dialogue.close()
		office.player.equipment.cancel()
		office.player.release_furniture()
	if not enabled:
		office.cancel_current_action()
		office.select_furniture(null)
	office.editor_visible = enabled
	office.editor_root.visible = enabled
	office.editor_toggle.text = "Done" if enabled else "Edit office"
	for worker in office.workers_container.get_children():
		worker.status_label.visible = enabled and office.show_worker_labels
	if is_instance_valid(office.player):
		office.player._refresh_context_display()

func refresh_ui() -> void:
	if office.stats_label == null:
		return

	var desk_count := 0
	var chair_count := 0
	var total_objects: int = office.furniture_container.get_child_count()
	for f in office.furniture_container.get_children():
		if f is FurnitureItem:
			if f.is_desk:
				desk_count += 1
			elif f.is_chair:
				chair_count += 1

	var worker_count: int = office.workers_container.get_child_count()
	office.stats_label.text = "%d coworkers  |  %d desks  |  %d objects" % [
		worker_count, desk_count, total_objects
	]
	var routines := office.get_node_or_null("OfficeRoutines")
	if routines != null:
		office.stats_label.text = "%d coworkers  |  %d desks  |  %d objects  |  Breaks %d/%d  |  %d chats" % [
			worker_count, desk_count, total_objects, routines.get_active_outing_count(), routines.max_outings, routines.social_sessions.size()
		]

	# Update Inspector Panel
	match office.edit_mode:
		office.EditMode.SELECT:
			office.mode_status_label.text = "MODE: SELECT / EDIT"
			office.mode_status_label.add_theme_color_override("font_color", Color(0.40, 0.90, 0.65))
			if is_instance_valid(office.selected_furniture):
				office.inspector_title_label.text = "Selected: " + office.selected_furniture.item_title
				if office.selected_furniture.is_desk or office.selected_furniture.is_chair:
					office.inspector_owner_label.text = "🔒 " + office.selected_furniture.get_owner_summary()
					office.inspector_owner_label.visible = true
				else:
					office.inspector_owner_label.visible = false
				office.inspector_hint_label.text = "Press M to Move, R to Rotate 90°, or Del to Delete this item."
				office.btn_move.disabled = false
				office.btn_rotate.disabled = false
				office.btn_delete.disabled = false
				office.btn_cancel.disabled = false
			else:
				office.inspector_title_label.text = "No Furniture Selected"
				office.inspector_owner_label.visible = false
				office.inspector_hint_label.text = "Left-click any furniture in the office to select it, or pick an item below to build."
				office.btn_move.disabled = true
				office.btn_rotate.disabled = true
				office.btn_delete.disabled = true
				office.btn_cancel.disabled = true
			if not office.placement_issue.is_empty():
				office.inspector_hint_label.text = office.placement_issue

		office.EditMode.PLACE_NEW:
			var def := AssetCatalog.get_item_def(office.placing_item_id)
			office.mode_status_label.text = "MODE: PLACING FURNITURE"
			office.mode_status_label.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0))
			office.inspector_title_label.text = "Placing: " + def.get("title", office.placing_item_id)
			office.inspector_owner_label.visible = false
			office.inspector_hint_label.text = "Left-Click floor to place (hold Shift for multiple). Press R to Rotate, Right-Click/Esc to Cancel."
			office.btn_move.disabled = true
			office.btn_rotate.disabled = false
			office.btn_delete.disabled = true
			office.btn_cancel.disabled = false
			if not office.placement_issue.is_empty():
				office.inspector_hint_label.text = office.placement_issue + " Choose a clear spot."

		office.EditMode.MOVE_EXISTING:
			office.mode_status_label.text = "MODE: MOVING FURNITURE"
			office.mode_status_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.30))
			if is_instance_valid(office.selected_furniture):
				office.inspector_title_label.text = "Moving: " + office.selected_furniture.item_title
			office.inspector_owner_label.visible = false
			office.inspector_hint_label.text = "Left-Click floor to confirm new spot. Press R to Rotate, Right-Click/Esc to Cancel."
			office.btn_move.disabled = true
			office.btn_rotate.disabled = false
			office.btn_delete.disabled = true
			office.btn_cancel.disabled = false
			if not office.placement_issue.is_empty():
				office.inspector_hint_label.text = office.placement_issue + " Choose a clear spot."
