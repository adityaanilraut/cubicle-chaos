class_name EmojiSpeechBubble
extends CanvasLayer

const EMOJI_FONT = preload("res://assets/fonts/NotoEmoji.ttf")
const BUBBLE_COLOR := Color("fff5df")
var actor: Node3D
var panel: PanelContainer
var label: Label
var tail: Polygon2D
var skeleton: Skeleton3D
var head_bone := -1
var text := ""
var _hide_timer := 0.0
var _head_position := Vector3.ZERO
var _has_head_position := false

func setup(person: Node3D) -> void:
	actor = person
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	skeleton = person.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		head_bone = skeleton.find_bone("office_Head")
		if head_bone >= 0:
			skeleton.skeleton_updated.connect(_sync_head)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BUBBLE_COLOR
	style.set_corner_radius_all(18)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 5
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Arial", "Helvetica", "sans-serif"])
	system_font.font_weight = 700
	system_font.fallbacks = [EMOJI_FONT]
	label.add_theme_font_override("font", system_font)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("715136"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	tail = Polygon2D.new()
	tail.color = BUBBLE_COLOR
	tail.polygon = PackedVector2Array([Vector2(-8, -1), Vector2(8, -1), Vector2(0, 10)])
	panel.add_child(tail)
	visible = false

func say(emojis: String) -> void:
	text = emojis
	label.text = emojis
	panel.size = Vector2.ZERO
	_hide_timer = 2.6
	visible = not emojis.is_empty()
	_process(0.0)

func _sync_head() -> void:
	if not is_inside_tree(): return
	_head_position = skeleton.to_global(skeleton.get_bone_global_pose(head_bone).origin)
	_has_head_position = true

func _process(delta: float) -> void:
	if not visible or not is_instance_valid(actor):
		return
	if delta > 0.0 and not text.is_empty() and not get_tree().paused:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			text = ""
			visible = false
			return
	var camera := get_viewport().get_camera_3d()
	var head := actor.global_position + Vector3(0, 2.1, 0)
	if _has_head_position:
		head = _head_position + Vector3(0, 0.30, 0)
	var viewport := get_viewport().get_visible_rect()
	panel.visible = not get_tree().paused and actor.is_visible_in_tree() and camera != null and not camera.is_position_behind(head)
	if not panel.visible:
		return
	var screen := camera.unproject_position(head)
	panel.visible = viewport.has_point(screen)
	panel.position = screen - Vector2(panel.size.x * 0.5, panel.size.y + 10)
	panel.position.x = clampf(panel.position.x, viewport.position.x, maxf(viewport.position.x, viewport.end.x - panel.size.x))
	tail.position = Vector2(panel.size.x * 0.5, panel.size.y)
