class_name InteractionActions
extends Control

# Screen-space controls anchored to the current world target; every circle is
# the same action as its keyboard shortcut, with eligibility checked on click.
var player: OfficePlayer
var caption: Label
var buttons: Array[Button] = []
var action_ids: Array[String] = []
var action_targets: Array[Node3D] = []
var target: Node3D
var anchor := Vector2.ZERO
var pending_clicks: Dictionary = {}

func setup(owner_player: OfficePlayer) -> void:
	player = owner_player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10))
	caption.add_theme_constant_override("outline_size", 6)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	for index in range(4):
		var button := Button.new()
		button.custom_minimum_size = Vector2(68, 68)
		button.size = Vector2(68, 68)
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 12)
		for state in ["normal", "hover", "pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.07, 0.12, 0.18, 0.96) if state == "normal" else Color(0.16, 0.30, 0.36, 1.0)
			style.border_color = Color.WHITE if state != "normal" else Color(0.72, 0.83, 0.88)
			style.set_border_width_all(2)
			style.set_corner_radius_all(34)
			button.add_theme_stylebox_override(state, style)
		button.button_down.connect(func():
			if index < action_ids.size():
				pending_clicks[index] = {"id": action_ids[index], "target": action_targets[index]}
		)
		button.pressed.connect(func():
			if pending_clicks.has(index):
				var intent: Dictionary = pending_clicks[index]
				pending_clicks.erase(index)
				if is_instance_valid(intent.target):
					player.perform_context_action(intent.id, intent.target)
		)
		add_child(button)
		buttons.append(button)
	visible = false

func show_actions(value: Node3D, actions: Array[Dictionary], title: String) -> void:
	target = value
	action_ids.clear()
	action_targets.clear()
	caption.text = title
	for index in range(buttons.size()):
		buttons[index].visible = index < actions.size()
		if index < actions.size():
			var action := actions[index]
			action_ids.append(action.id)
			action_targets.append(action.get("target", value))
			buttons[index].text = action.key + "\n" + action.label
			buttons[index].tooltip_text = action.get("hint", action.label)
	visible = is_instance_valid(target) and not actions.is_empty()
	_process(0.0)

func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(target):
		visible = false
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(target.global_position):
		visible = false
		return
	var screen := camera.unproject_position(target.global_position)
	var viewport := get_viewport_rect().size
	var width := float(action_ids.size()) * 76.0 - 8.0
	var side_margin := 310.0 if player.office.editor_visible and viewport.x >= 1100 else 16.0
	anchor = Vector2(clampf(screen.x, side_margin + width * 0.5, viewport.x - side_margin - width * 0.5), clampf(screen.y + 30, 70, viewport.y - 90))
	caption.position = anchor + Vector2(-160, -28)
	caption.size = Vector2(320, 24)
	for index in range(action_ids.size()):
		buttons[index].position = anchor + Vector2(-width * 0.5 + float(index) * 76.0, 0)
