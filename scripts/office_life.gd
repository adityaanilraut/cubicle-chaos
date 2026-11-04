class_name OfficeLife
extends Node3D

# The briefing uses real OfficeWorkers: normal talk, physics hits, pause and
# furniture reservations still apply. Only their scheduled meeting poses live here.
const BEAT_SECONDS := 2.5
const SLIDES := [
	["01 / TODAY'S PLAN", "Welcome to the team\nShare ideas. Help a coworker.\nLeave time for a coffee."],
	["02 / SMALL WINS", "Reports are moving\nThe printer is (mostly) working\nTeam morale is on the rise."],
	["03 / YOUR IDEAS", "Make room for good ideas\nSketch them on a whiteboard\nAsk questions. Work together."],
	["04 / NEXT STEPS", "One thing at a time\nTake a break. Come back fresh.\nThank you, team!"],
]
const EXCHANGE := [
	["presenter", "🎤 Welcome, everyone!"],
	["presenter", "📈 Small wins add up!"],
	["attendee_0", "🙋 What about the printer?"],
	["presenter", "🖨️ Morgan is on the case!"],
	["presenter", "💡 Let's share some ideas!"],
	["attendee_1", "☕ More coffee breaks?"],
	["presenter", "✅ Great for team morale!"],
	["attendee_0", "📝 Putting that in my notes!"],
	["presenter", "🤝 Let's help each other!"],
	["attendee_1", "🙌 Count me in!"],
	["presenter", "👏 Thanks for joining!"],
	["", ""],
]
var office: Node3D
var table: FurnitureItem
var screen: FurnitureItem
var stage: Node3D
var slide_title: Label3D
var slide_body: Label3D
var slide_footer: Label3D
var bars: Array[MeshInstance3D] = []
var participants: Dictionary = {}
var elapsed := 0.0
var current_beat := -1
var slide_index := -1
var _table_transform := Transform3D.IDENTITY
var _screen_transform := Transform3D.IDENTITY
var _welcome_pending := true
var _welcome_time := 0.0

func setup(owner_office: Node3D) -> void:
	office = owner_office
	name = "OfficeLife"
	for item: FurnitureItem in office.furniture_container.get_children():
		if item.item_id == "conference_table" and item.global_position.distance_to(Vector3(16.5, 0, -5.9)) < 0.1:
			item.set_meta("meeting_anchor", "table")
		if item.item_id == "tv_presentation" and item.global_position.distance_to(Vector3(16.8, 0, -9.1)) < 0.1:
			item.set_meta("meeting_anchor", "screen")
	_find_anchors()
	_build_screen()
	decorate_boss()
	for i in range(3):
		var role := "presenter" if i == 0 else "attendee_%d" % (i - 1)
		var worker: OfficeWorker = office.spawn_worker(_position_for(role), role)
		bind_participant(worker)
	# Let the arriving player see a real two-way coworker chat before desks fill.
	for i in [1, 2]:
		var worker: OfficeWorker = office.workers_container.get_child(i)
		worker._enter_idle(6.0)
		worker.social_need = 0.8

func _find_anchors() -> void:
	table = null
	screen = null
	for item: FurnitureItem in office.furniture_container.get_children():
		match String(item.get_meta("meeting_anchor", "")):
			"table": table = item
			"screen": screen = item
	if is_instance_valid(table): _table_transform = table.global_transform
	if is_instance_valid(screen): _screen_transform = screen.global_transform

func _position_for(role: String) -> Vector3:
	if role == "presenter": return screen.to_global(Vector3(1.65, 0, 1.55))
	return table.to_global(Vector3(-0.85 if role == "attendee_0" else 0.85, 0, 0.68))

func bind_participant(worker: OfficeWorker) -> void:
	if not _room_available() or worker.meeting_role.is_empty(): return
	worker._enter_idle(1.0)
	worker.meeting = self
	worker.target_furniture = table
	worker.global_position = _position_for(worker.meeting_role)
	worker.is_seated = worker.meeting_role != "presenter"
	worker.state = OfficeWorker.State.WORKING if worker.is_seated else OfficeWorker.State.IDLE
	worker.nav_agent.avoidance_enabled = not worker.is_seated
	worker.collision_shape.set_deferred("disabled", worker.is_seated)
	worker.rotation.y = table.global_rotation.y + (PI if worker.is_seated else 0.0)
	participants[worker] = {"beat": -1}
	worker.play_anim("listen" if worker.is_seated else "present")
	worker._update_label()

func release_participant(worker: OfficeWorker) -> void:
	participants.erase(worker)
	worker.meeting = null
	worker.show_social_speech("")
	# Composite conference seats belong to the table, so leave at its edge.
	if worker.is_seated and is_instance_valid(table) and not table.is_queued_for_deletion():
		worker.global_position = table.to_global(Vector3(-0.85 if worker.meeting_role == "attendee_0" else 0.85, 0, 1.45))
	worker.is_seated = false
	if worker.target_furniture == table: worker.target_furniture = null
	worker.collision_shape.set_deferred("disabled", false)
	worker.nav_agent.avoidance_enabled = true

func _room_available() -> bool:
	for item in [table, screen]:
		if not is_instance_valid(item) or item.is_queued_for_deletion() or item.is_preview or is_instance_valid(item.being_moved_by):
			return false
	return table.global_transform.is_equal_approx(_table_transform) and screen.global_transform.is_equal_approx(_screen_transform)

func tick_worker(worker: OfficeWorker, _delta: float) -> bool:
	if not participants.has(worker):
		worker.meeting = null
		return false
	if not _room_available():
		release_participant(worker)
		worker._enter_idle(1.0)
		return false
	worker._stop_walking_velocity()
	var point := _position_for(worker.meeting_role)
	# Avoid dragging a displaced actor back into the meeting.
	if worker.global_position.distance_to(point) > 0.35:
		release_participant(worker)
		worker._enter_idle(1.0)
		return false
	var beat := maxi(0, current_beat)
	var data: Dictionary = participants[worker]
	if int(data.beat) != beat:
		data.beat = beat
		var exchange: Array = EXCHANGE[beat]
		var speaking: bool = exchange[0] == worker.meeting_role
		worker.show_social_speech(String(exchange[1]) if speaking else "")
		var motion := "present" if worker.meeting_role == "presenter" else "listen"
		if worker.is_seated:
			if beat >= 10: motion = "applaud"
			elif speaking: motion = "raise_hand" if beat in [2, 5] else "read_notes"
			elif beat in [3, 7]: motion = "read_notes"
		worker.play_anim(motion)
	if worker.is_seated:
		worker.rotation.y = table.global_rotation.y + PI
	else:
		var facing := table.global_position - worker.global_position
		worker.rotation.y = atan2(facing.x, facing.z)
	return true

func _physics_process(delta: float) -> void:
	elapsed += delta
	current_beat = int(elapsed / BEAT_SECONDS) % EXCHANGE.size()
	for actor in participants.keys():
		if not is_instance_valid(actor) or actor.is_queued_for_deletion(): participants.erase(actor)
	if is_instance_valid(stage):
		stage.visible = _room_available()
		var next_slide := int(elapsed / 7.5) % SLIDES.size()
		if next_slide != slide_index:
			slide_index = next_slide
			slide_title.text = SLIDES[slide_index][0]
			slide_body.text = SLIDES[slide_index][1]
			slide_footer.text = "TEAM BRIEFING  /  %02d OF 04" % (slide_index + 1)
		for i in range(bars.size()):
			var height := 0.22 + float((i + slide_index) % 3 + 1) * 0.15
			var reveal := smoothstep(0.0, 0.9, fmod(elapsed, 7.5))
			bars[i].scale.y = lerpf(bars[i].scale.y, maxf(0.02, height * reveal), minf(1.0, delta * 6.0))
			bars[i].position.y = 1.43 + bars[i].scale.y * 0.5
	if _welcome_pending:
		_welcome_time += delta
		if _welcome_time >= 1.0 and NavigationServer3D.map_get_iteration_id(office.get_world_3d().navigation_map) > 0:
			_welcome_pending = false
			if office.workers_container.get_child_count() >= 3:
				var maya: OfficeWorker = office.workers_container.get_child(1)
				if maya.state == OfficeWorker.State.IDLE and maya.is_physics_processing() and maya.routines.request_outing(maya):
					if not maya.routines.try_start_social(maya): maya.routines.release_outing(maya)

func _build_screen() -> void:
	slide_index = -1
	bars.clear()
	if not is_instance_valid(screen): return
	stage = Node3D.new()
	stage.name = "LiveBriefing"
	screen.add_child(stage)
	var backdrop := ModernAssets.material("briefing_screen", Color("172c35"))
	backdrop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ModernAssets.box(stage, Vector3(3.5, 1.8, 0.08), Vector3(0, 2.0, 0.25), backdrop)
	var gold := ModernAssets.material("briefing_gold", Color("efbc72"))
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ModernAssets.box(stage, Vector3(3.5, 0.045, 0.02), Vector3(0, 2.89, 0.30), gold)
	slide_title = _screen_label("", Vector3(-1.51, 2.56, 0.31), 35, Color("efbc72"))
	slide_body = _screen_label("", Vector3(-1.51, 2.15, 0.31), 27, Color("f4f1e6"))
	slide_footer = _screen_label("", Vector3(-1.51, 1.23, 0.31), 17, Color("b2cbbf"))
	for i in range(3):
		var mat := ModernAssets.material("briefing_bar_%d" % i, [Color("93b8a0"), Color("efbc72"), Color("87a9b6")][i])
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var bar := ModernAssets.box(stage, Vector3(0.15, 1, 0.02), Vector3(0.92 + i * 0.23, 1.6, 0.31), mat)
		bar.scale.y = 0.02
		bars.append(bar)

func _screen_label(words: String, pos: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.position = pos
	label.font_size = font_size
	label.pixel_size = 0.004
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.modulate = color
	label.outline_size = 0
	stage.add_child(label)
	return label

func decorate_boss() -> void:
	for worker: OfficeWorker in office.workers_container.get_children():
		if worker.worker_name != "Alex": continue
		worker.is_boss = true
		if worker.has_node("BossTitle"): continue
		var outfit := worker.rig_root.find_child("OfficeOutfit", true, false) as MeshInstance3D
		outfit.material_override = AssetCatalog.get_shared_material("boss_suit", Color("293a50"), 0.7)
		var skeleton := worker.rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "office_Spine2"
		skeleton.add_child(attachment)
		ModernAssets.box(attachment, Vector3(0.045, 0.21, 0.022), Vector3(0, -0.075, 0.135), ModernAssets.material("boss_tie", Color("d6ab59")))
		var label := Label3D.new()
		label.name = "BossTitle"
		label.text = "ALEX · BOSS"
		label.position.y = 1.92
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 30
		label.pixel_size = 0.005
		label.modulate = Color("f2d395")
		worker.add_child(label)
		worker._update_label()

func leave_ideas(item: FurnitureItem) -> void:
	if item.has_node("SharedIdeas"): return
	item.set_meta("shared_ideas", true)
	var ideas := Node3D.new()
	ideas.name = "SharedIdeas"
	item.add_child(ideas)
	ModernAssets.box(ideas, Vector3(1.64, 0.94, 0.008), Vector3(0, 1.40, 0.09), ModernAssets.material("ideas_board", Color("eeede6")))
	var label := Label3D.new()
	label.text = "TEAM IDEAS\n\n01  Share the load\n02  Try something new\n03  Coffee + teamwork"
	label.font_size = 21
	label.pixel_size = 0.003
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.modulate = Color("304d52")
	label.position = Vector3(-0.73, 1.78, 0.10)
	ideas.add_child(label)

func restore(members: Array[OfficeWorker]) -> void:
	participants.clear()
	_find_anchors()
	_build_screen()
	decorate_boss()
	for item in office.furniture_container.get_children():
		if bool(item.get_meta("shared_ideas", false)): leave_ideas(item)
	for worker in members: bind_participant(worker)
	_welcome_pending = false
