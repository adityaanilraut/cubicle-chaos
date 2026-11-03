class_name OfficeIntro
extends CanvasLayer

# A short optional first-run introduction. Progress is stored separately from shifts.
const INTRO_PATH := "user://office_intro.cfg"
var office: Node3D
var panel: PanelContainer
var instruction: Label
var skip_button: Button
var active := false
var moved := false
var talked := false
var start_position := Vector3.ZERO
var finish_time := 0.0

func setup(owner_office: Node3D) -> void:
	office = owner_office
	layer = 20
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -460
	panel.offset_right = -24
	panel.offset_top = 70
	panel.offset_bottom = 150
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.055, 0.09, 0.13, 0.96)
	skin.border_color = Color("e1b66d")
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(12)
	skin.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", skin)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	instruction = Label.new()
	instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_font_size_override("font_size", 16)
	row.add_child(instruction)
	skip_button = Button.new()
	skip_button.text = "Skip"
	skip_button.pressed.connect(skip)
	row.add_child(skip_button)
	panel.visible = false

func start_if_new() -> void:
	var config := ConfigFile.new()
	if config.load(INTRO_PATH) == OK and bool(config.get_value("intro", "finished", false)):
		return
	start_intro()

func start_intro() -> void:
	active = true
	moved = false
	talked = false
	finish_time = 0.0
	start_position = office.player.global_position
	skip_button.visible = true
	panel.visible = true
	_refresh()

func notice_talk() -> void:
	if active:
		talked = true
		_refresh()

func skip() -> void:
	if not active:
		return
	active = false
	panel.visible = false
	_remember_finished()

func _remember_finished() -> void:
	var config := ConfigFile.new()
	config.set_value("intro", "finished", true)
	config.save(INTRO_PATH)

func _refresh() -> void:
	if moved and talked:
		instruction.text = "All set! Explore the office at your own pace."
		skip_button.visible = false
		if finish_time == 0.0:
			finish_time = 3.0
			_remember_finished()
	elif not moved:
		instruction.text = "WELCOME  1 / 2\nMove with WASD or click the floor."
	else:
		instruction.text = "WELCOME  2 / 2\nApproach a coworker and press %s to talk." % OfficeInput.key_name("interact")

func _process(delta: float) -> void:
	if not active:
		return
	panel.visible = office.player.gameplay_visible
	if finish_time > 0.0:
		finish_time -= delta / maxf(Engine.time_scale, 0.1)
		if finish_time <= 0.0:
			active = false
			panel.visible = false
		return
	if not moved and office.player.global_position.distance_to(start_position) >= 1.0:
		moved = true
		_refresh()
