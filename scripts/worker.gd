class_name OfficeWorker
extends CharacterBody3D

enum State {
	IDLE,
	WALKING,
	SITTING,
	WORKING,
	BREAK
}

enum WalkGoal {
	TO_CHAIR,
	TO_BREAK,
	TO_STROLL
}

enum BreakType {
	WATER_COOLER,
	KITCHEN_COFFEE,
	CONFERENCE_ROOM,
	LOUNGE_RELAX,
	OFFICE_ERRAND,
	CHAT_WORKER
}

enum BreakPhase {
	STAND_TYPE_TO_SIT,
	STAND_SIT_TO_STAND,
	PERFORM_ACTION
}

const MOVE_SPEED := 1.85
const TURN_SPEED := 10.0

var worker_name: String = "Alex"
var worker_index: int = 0
var state: State = State.IDLE
var walk_goal: WalkGoal = WalkGoal.TO_CHAIR
var break_type: BreakType = BreakType.WATER_COOLER
var break_phase: BreakPhase = BreakPhase.PERFORM_ACTION

var state_timer: float = 0.0
var sitting_subphase: int = 0
var is_seated: bool = false
var stuck_timer: float = 0.0
var last_frame_pos: Vector3 = Vector3.ZERO
var _repath_attempts: int = 0
var _recovery_wait: float = 0.0
var _retarget_timer: float = 0.0
var _chair_retry_timer: float = 0.0
var _walk_elapsed: float = 0.0
var _path_initialized: bool = false
var _stand_exit_pos: Vector3 = Vector3.ZERO
var _stand_start_pos := Vector3.ZERO
var _stand_length := 2.05
var _idle_after_standing: bool = false
var _forced_stand_pending := false
var routines: Node
var thirst := 0.0
var fatigue := 0.0
var task_pressure := 0.0
var focus_strain := 0.0
var completed_tasks := 0
var social_need := 0.0
var social_cooldown := 0.0
var completed_conversations := 0
var social_session_id := 0
var _social_departure_pending := false
var _social_arrived := false
var social_speech: EmojiSpeechBubble
var player_conversation_partner: OfficeWorker
var _conversation_anim := "idle"
var _conversation_hold_time := 0.0
var last_break_type := -1
var _break_cooldowns: Dictionary = {}
var _planned_break := false
var _deskless_wait := 0.0

var office_ref: Node = null
var assigned_chair: FurnitureItem = null
var assigned_desk: FurnitureItem = null
var target_chair: FurnitureItem = null
var target_furniture: FurnitureItem = null
var target_partner: OfficeWorker = null
var target_walk_pos: Vector3 = Vector3.ZERO
var target_face_yaw: float = 0.0

var rig_root: Node3D = null
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var state_playback: AnimationNodeStateMachinePlayback = null
var nav_agent: NavigationAgent3D = null
var collision_shape: CollisionShape3D = null
var status_label: Label3D = null
var combat: OfficeCombat
var social: WorkerSocial

const OUTFIT_COLORS: Array[Color] = [
	Color(0.20, 0.42, 0.72), # Slate Blue
	Color(0.74, 0.31, 0.27), # Terracotta Red
	Color(0.22, 0.56, 0.42), # Forest Emerald
	Color(0.52, 0.33, 0.68), # Royal Plum
	Color(0.78, 0.54, 0.20), # Warm Ochre
	Color(0.18, 0.58, 0.64), # Deep Teal
	Color(0.64, 0.36, 0.48), # Dusty Rose
	Color(0.36, 0.52, 0.30), # Olive Moss
]

func setup(p_office: Node, p_index: int, p_name: String, outfit_color_idx: int) -> void:
	office_ref = p_office
	worker_index = p_index
	worker_name = p_name
	if office_ref != null:
		routines = office_ref.get_node_or_null("OfficeRoutines")
		if routines == null:
			routines = preload("res://scripts/office_routines.gd").new()
			routines.name = "OfficeRoutines"
			office_ref.add_child(routines)
	# Different starting needs avoid synchronized breaks and repetitive routes.
	thirst = 0.15 + float(worker_index % 3) * 0.12
	fatigue = 0.12 + float((worker_index + 1) % 4) * 0.10
	task_pressure = 0.18 + float((worker_index + 2) % 3) * 0.11
	focus_strain = 0.08 + float(worker_index % 4) * 0.08
	social_need = 0.25 + float(worker_index % 4) * 0.12
	add_to_group("workers")

	# Physics capsule for worker
	collision_layer = 4
	collision_mask = 1
	collision_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = 1.65
	collision_shape.shape = cap
	collision_shape.position = Vector3(0.0, 0.825, 0.0)
	add_child(collision_shape)

	# Seated workers disable their movement capsule so chairs remain navigable.
	# A non-blocking sensor still lets an actual thrown prop hit their torso.
	if p_office != null:
		var seated_hit_area := Area3D.new()
		seated_hit_area.name = "SeatedPropHitArea"
		seated_hit_area.collision_layer = 0
		seated_hit_area.collision_mask = 8
		var seated_shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.34
		seated_shape.shape = sphere
		seated_shape.position.y = 0.85
		seated_hit_area.add_child(seated_shape)
		seated_hit_area.body_entered.connect(_on_seated_prop_entered)
		add_child(seated_hit_area)

	# NavigationAgent3D for pathfinding and RVO obstacle avoidance
	nav_agent = NavigationAgent3D.new()
	# The baked surface sits 0.2m above the character's floor root.
	nav_agent.path_desired_distance = 0.30
	nav_agent.target_desired_distance = 0.30
	nav_agent.path_max_distance = 1.2
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.28
	nav_agent.height = 1.75
	nav_agent.neighbor_distance = 3.0
	nav_agent.max_neighbors = 12
	nav_agent.max_speed = MOVE_SPEED
	nav_agent.time_horizon_agents = 1.0
	nav_agent.time_horizon_obstacles = 0.6
	nav_agent.avoidance_priority = 0.4 + float(worker_index % 5) * 0.08
	nav_agent.velocity_computed.connect(_on_nav_velocity_computed)
	add_child(nav_agent)

	# Build the original character mesh and skeleton without imported assets.
	rig_root = OfficeCharacter.create_rig()
	rig_root.name = "CharacterRig"
	add_child(rig_root)

	# Apply shared low-poly palette materials to reuse materials across workers
	var c_idx := outfit_color_idx % OUTFIT_COLORS.size()
	var body_mat := AssetCatalog.get_shared_material(
		"worker_body_" + str(c_idx),
		OUTFIT_COLORS[c_idx],
		0.62
	)
	var joint_mat := AssetCatalog.get_shared_material(
		"worker_joints",
		Color(0.16, 0.18, 0.22),
		0.75
	)
	var surface_mi: MeshInstance3D = rig_root.find_child("OfficeOutfit", true, false)
	if surface_mi:
		surface_mi.material_override = body_mat
	var joints_mi: MeshInstance3D = rig_root.find_child("OfficeTrousers", true, false)
	if joints_mi:
		joints_mi.material_override = joint_mat

	var appearance := WorkerVariety.variety_for(4 if self is OfficePlayer else worker_index)
	var skin_color: Color = appearance.skin_tone
	var skin_mesh := rig_root.find_child("OfficeSkin", true, false) as MeshInstance3D
	skin_mesh.material_override = AssetCatalog.get_shared_material("worker_skin_" + skin_color.to_html(), skin_color, 0.8)
	var details_mesh := rig_root.find_child("OfficeDetails", true, false) as MeshInstance3D
	details_mesh.material_override = AssetCatalog.get_shared_material("worker_collar", Color(0.92, 0.91, 0.86), 0.8)

	# Attach shared AnimationLibrary and AnimationTree StateMachine
	anim_player = rig_root.find_child("AnimationPlayer", true, false)
	var shared_lib := AssetCatalog.get_worker_animation_library()
	if not anim_player.has_animation_library("office"):
		anim_player.add_animation_library("office", shared_lib)

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	rig_root.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.tree_root = AssetCatalog.get_worker_state_machine()
	anim_tree.active = true
	state_playback = anim_tree.get("parameters/playback")
	play_anim("idle")

	# Floating 3D status label above worker
	status_label = Label3D.new()
	status_label.position = Vector3(0.0, 2.02, 0.0)
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.no_depth_test = true
	status_label.fixed_size = false
	status_label.pixel_size = 0.0042
	status_label.font_size = 32
	status_label.outline_size = 10
	status_label.modulate = Color(0.95, 0.93, 0.86)
	status_label.outline_modulate = Color(0.06, 0.08, 0.12, 0.95)
	add_child(status_label)
	status_label.visible = false
	social_speech = EmojiSpeechBubble.new()
	add_child(social_speech)
	social_speech.setup(self)
	var variety := WorkerVariety.new()
	add_child(variety)
	variety.setup(self, 4 if self is OfficePlayer else worker_index)
	combat = OfficeCombat.new()
	social = WorkerSocial.new(self)
	combat.setup(self)

	# Assign personal desk/chair immediately if available
	if office_ref and office_ref.has_method("get_or_assign_personal_chair"):
		office_ref.get_or_assign_personal_chair(self)

	_enter_idle(0.35 + float(worker_index % 4) * 0.35)

func play_anim(anim_name: String) -> void:
	if state_playback != null:
		if String(state_playback.get_current_node()) != anim_name:
			state_playback.travel(anim_name)

func get_desk_badge() -> String:
	if is_instance_valid(assigned_chair) and assigned_chair.desk_number > 0:
		return "Desk #%d" % assigned_chair.desk_number
	elif is_instance_valid(assigned_desk) and assigned_desk.desk_number > 0:
		return "Desk #%d" % assigned_desk.desk_number
	elif is_instance_valid(assigned_chair):
		return "Own Desk"
	return "No Desk"

func get_state_name() -> String:
	if combat != null and combat.is_engaged():
		return combat.status()
	if is_instance_valid(player_conversation_partner):
		return "Talking with you"
	if social_session_id != 0 and _social_departure_pending:
		return "Working · chat queued" if is_seated else "Waiting to meet coworker"
	if social_session_id != 0 and _social_arrived:
		return "Chatting with " + target_partner.worker_name if is_instance_valid(target_partner) else "Waiting for coworker"
	match state:
		State.IDLE:
			return "Waiting for workstation" if not is_instance_valid(assigned_chair) else "Preparing next task"
		State.WALKING:
			match walk_goal:
				WalkGoal.TO_CHAIR:
					return "Walking → Own " + get_desk_badge()
				WalkGoal.TO_BREAK:
					match break_type:
						BreakType.WATER_COOLER:
							return "Walking → Water Cooler"
						BreakType.KITCHEN_COFFEE:
							return "Walking → Break Kitchen"
						BreakType.CONFERENCE_ROOM:
							return "Walking → Conf Room"
						BreakType.LOUNGE_RELAX:
							return "Walking → Lounge"
						BreakType.OFFICE_ERRAND:
							return "Walking → Printer/Files"
						BreakType.CHAT_WORKER:
							return "Walking → Coworker"
				_:
					return "Walking"
		State.SITTING:
			return "Sitting at " + get_desk_badge()
		State.WORKING:
			if is_instance_valid(routines) and routines.is_waiting(self):
				return "Working · break queued"
			return "Working at " + get_desk_badge()
		State.BREAK:
			if is_seated:
				return "Standing Up"
			match break_type:
				BreakType.WATER_COOLER:
					return "Refilling water"
				BreakType.KITCHEN_COFFEE:
					return "Making coffee"
				BreakType.CONFERENCE_ROOM:
					return "Reviewing meeting notes"
				BreakType.LOUNGE_RELAX:
					return "Relaxing in Lounge"
				BreakType.OFFICE_ERRAND:
					return "Collecting printouts"
				BreakType.CHAT_WORKER:
					return "Chatting w/ Coworker"
	return "Idle"

func _update_label() -> void:
	if status_label:
		status_label.text = "%s (%s)\n[%s]" % [worker_name, get_desk_badge(), get_state_name()]

func _on_seated_prop_entered(body: Node3D) -> void:
	if not is_seated or not collision_shape.disabled or not body is PhysicsProp:
		return
	var prop := body as PhysicsProp
	if prop.is_held() or prop.impact.thrower == null or not is_instance_valid(prop.impact.thrower.get_ref()):
		return
	var speed := prop.linear_velocity.length()
	prop.impact.queue_contact(self, speed, prop.linear_velocity.normalized(), prop.global_position)

func _physics_process(delta: float) -> void:
	thirst = minf(1.0, thirst + delta * 0.0045)
	fatigue = minf(1.0, fatigue + delta * 0.0035)
	task_pressure = minf(1.0, task_pressure + delta * 0.005)
	focus_strain = minf(1.0, focus_strain + delta * 0.003)
	social_need = minf(1.0, social_need + delta * 0.004)
	social_cooldown = maxf(0.0, social_cooldown - delta)
	_deskless_wait = maxf(0.0, _deskless_wait - delta)
	for key in _break_cooldowns:
		_break_cooldowns[key] = maxf(0.0, float(_break_cooldowns[key]) - delta)
	if combat.tick(delta):
		_update_label()
		return
	if is_instance_valid(player_conversation_partner):
		_conversation_hold_time += delta
		if player_conversation_partner.combat.is_engaged() or global_position.distance_to(player_conversation_partner.global_position) > 3.0 or _conversation_hold_time > 120.0:
			end_player_conversation(player_conversation_partner)
		else:
			_stop_walking_velocity()
			if not is_seated:
				var direction := player_conversation_partner.global_position - global_position
				rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(delta * 8.0, 1.0))
			return
	if _social_departure_pending:
		_process_social_departure()
		return
	if social_session_id != 0 and _social_arrived:
		_stop_walking_velocity()
		if is_instance_valid(target_partner):
			var direction := target_partner.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(delta * 8.0, 1.0))
		return
	state_timer -= delta
	_chair_retry_timer = maxf(0.0, _chair_retry_timer - delta)
	if _forced_stand_pending and is_seated:
		if not is_instance_valid(routines) or routines.request_stand(self):
			_forced_stand_pending = false
			_begin_standing()
			_idle_after_standing = true
		return
	if state != State.WALKING:
		nav_agent.velocity = Vector3.ZERO

	match state:
		State.IDLE:
			velocity = Vector3.ZERO
			if state_timer <= 0.0:
				_decide_next_from_idle()

		State.WALKING:
			_process_walking(delta)

		State.SITTING:
			velocity = Vector3.ZERO
			_process_sitting(delta)

		State.WORKING:
			velocity = Vector3.ZERO
			_process_working(delta)

		State.BREAK:
			velocity = Vector3.ZERO
			_process_break(delta)

func _enter_idle(duration: float = 1.4) -> void:
	_release_routine()
	if nav_agent:
		nav_agent.avoidance_enabled = true
	_release_break_spot()
	state = State.IDLE
	state_timer = duration
	is_seated = false
	if collision_shape:
		collision_shape.disabled = false
	play_anim("idle" if randf() < 0.6 else "idle_breath")
	_update_label()

func _decide_next_from_idle() -> void:
	if office_ref == null:
		state_timer = 1.5
		return

	# Always get ONLY this worker's own assigned desk chair (never someone else's!)
	var my_chair: FurnitureItem = office_ref.get_or_assign_personal_chair(self)
	if my_chair != null and _chair_retry_timer <= 0.0:
		_start_walking_to_chair(my_chair)
	else:
		# Hires without a desk wait between useful errands instead of roaming.
		if _deskless_wait <= 0.0 and (not is_instance_valid(routines) or routines.request_outing(self)):
			_choose_and_walk_to_break()
		else:
			state_timer = 2.0
			_update_label()

func _start_walking_to_chair(chair: FurnitureItem) -> void:
	_release_break_spot()
	# Strictly enforce that a worker only ever walks to & sits on their own personal chair
	if chair.owner_worker != null and chair.owner_worker != self:
		_choose_and_walk_to_break()
		return

	chair.owner_worker = self
	chair.reserved_by = self
	assigned_chair = chair
	target_chair = chair
	walk_goal = WalkGoal.TO_CHAIR
	target_walk_pos = target_chair.get_chair_approach_pos()
	target_face_yaw = target_chair.global_rotation.y
	_enter_walking(target_walk_pos)

func _enter_walking(dest: Vector3) -> void:
	nav_agent.avoidance_enabled = true
	if is_instance_valid(target_furniture):
		target_furniture.reserved_by = self
	state = State.WALKING
	is_seated = false
	if collision_shape:
		collision_shape.disabled = false
	stuck_timer = 0.0
	last_frame_pos = global_position
	target_walk_pos = Vector3(dest.x, 0.0, dest.z)
	_repath_attempts = 0
	_recovery_wait = 0.0
	_retarget_timer = 0.0
	_walk_elapsed = 0.0
	_path_initialized = false
	play_anim("walk")
	_update_label()

func _set_navigation_target() -> bool:
	var nav_map := nav_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return false
	var projected := NavigationServer3D.map_get_closest_point(nav_map, target_walk_pos)
	if Vector2(projected.x - target_walk_pos.x, projected.z - target_walk_pos.z).length() > 0.6:
		return false
	nav_agent.target_position = projected
	_path_initialized = true
	return true

func _stop_walking_velocity() -> void:
	velocity = Vector3.ZERO
	nav_agent.velocity = Vector3.ZERO

func _retry_or_abandon_path() -> void:
	_stop_walking_velocity()
	_repath_attempts += 1
	if _repath_attempts >= 3:
		# An unreachable desk should not cause an endless retry loop.
		if walk_goal == WalkGoal.TO_CHAIR:
			_chair_retry_timer = randf_range(6.0, 9.0)
		if walk_goal == WalkGoal.TO_BREAK:
			_break_cooldowns[break_type] = 24.0
		_release_break_spot()
		target_partner = null
		_deskless_wait = 10.0
		_enter_idle(randf_range(2.0, 4.0))
		return
	_recovery_wait = 0.35 + float(worker_index % 4) * 0.15
	_path_initialized = false
	stuck_timer = 0.0
	last_frame_pos = global_position
	play_anim("idle")

func _process_walking(delta: float) -> void:
	if walk_goal == WalkGoal.TO_CHAIR:
		if not is_instance_valid(target_chair) or target_chair.is_preview or is_instance_valid(target_chair.being_moved_by) or (target_chair.owner_worker != null and target_chair.owner_worker != self):
			_stop_walking_velocity()
			_enter_idle(1.0)
			return
	if is_instance_valid(target_furniture) and (target_furniture.is_preview or is_instance_valid(target_furniture.being_moved_by)):
		_stop_walking_velocity()
		_enter_idle(1.0)
		return
	if NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) == 0:
		_stop_walking_velocity()
		return
	_walk_elapsed += delta
	if _walk_elapsed > 35.0:
		_repath_attempts = 2
		_retry_or_abandon_path()
		return
	if _recovery_wait > 0.0:
		_recovery_wait -= delta
		_stop_walking_velocity()
		return
	_retarget_timer -= delta
	if walk_goal == WalkGoal.TO_BREAK and break_type == BreakType.CHAT_WORKER:
		if not is_instance_valid(target_partner) or (social_session_id == 0 and target_partner.is_seated):
			_stop_walking_velocity()
			_enter_idle(1.0)
			return
	if not _path_initialized:
		if not _set_navigation_target():
			_retry_or_abandon_path()
			return
		play_anim("walk")

	# Updating the path first distinguishes arriving from exhausting an unreachable path.
	var next_pos := nav_agent.get_next_path_position()
	var flat_dist := Vector2(global_position.x - target_walk_pos.x, global_position.z - target_walk_pos.z).length()
	if flat_dist <= 0.43:
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, target_walk_pos + Vector3.UP * 0.8, 1, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_stop_walking_velocity()
			_on_walk_arrived()
			return
	if nav_agent.is_navigation_finished():
		_retry_or_abandon_path()
		return

	# Measure progress over a time window, independent of frame rate.
	stuck_timer += delta
	if stuck_timer >= 1.2:
		if global_position.distance_to(last_frame_pos) < 0.10:
			_retry_or_abandon_path()
			return
		last_frame_pos = global_position
		stuck_timer = 0.0

	var dir := next_pos - global_position
	dir.y = 0.0
	var desired_vel := dir.normalized() * minf(MOVE_SPEED, dir.length() / maxf(delta, 0.001))
	if nav_agent.avoidance_enabled:
		nav_agent.velocity = desired_vel
	else:
		_apply_movement(desired_vel, delta)

func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	if state != State.WALKING or _recovery_wait > 0.0 or not _path_initialized:
		return
	_apply_movement(safe_velocity, get_physics_process_delta_time())

func _apply_movement(vel: Vector3, delta: float) -> void:
	velocity = Vector3(vel.x, 0.0, vel.z)
	if velocity.length_squared() > 0.02:
		# Character rig faces +Z in local space
		var desired_yaw := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	move_and_slide()
	global_position.y = 0.0

func _on_walk_arrived() -> void:
	match walk_goal:
		WalkGoal.TO_CHAIR:
			if is_instance_valid(target_chair) and (target_chair.owner_worker == null or target_chair.owner_worker == self):
				_enter_sitting()
			else:
				_enter_idle(1.0)
		WalkGoal.TO_BREAK:
			if social_session_id != 0:
				_social_arrived = true
				state = State.BREAK
				break_phase = BreakPhase.PERFORM_ACTION
				play_anim("idle_breath")
				routines.mark_social_arrived(self)
				_update_label()
			else:
				_enter_break_perform()
		_:
			_enter_idle(1.2)

func _enter_sitting() -> void:
	# The chair is already in the baked obstacles. A seated RVO agent would
	# create a second invisible blocker in the adjacent walkway.
	nav_agent.velocity = Vector3.ZERO
	nav_agent.avoidance_enabled = false
	state = State.SITTING
	is_seated = true
	sitting_subphase = 0
	if collision_shape:
		collision_shape.disabled = true
	state_timer = 2.05
	play_anim("stand_to_sit")
	_update_label()

func _process_sitting(delta: float) -> void:
	if not is_instance_valid(target_chair):
		_force_stand_and_idle()
		return

	# Smoothly align worker onto their own chair seat and face the desk (+Z of chair)
	var seat_pos := target_chair.get_seat_world_pos()
	global_position = global_position.lerp(seat_pos, clampf(delta * 8.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_chair.global_rotation.y, clampf(delta * 10.0, 0.0, 1.0))

	if sitting_subphase == 0 and state_timer <= 0.0:
		sitting_subphase = 1
		state_timer = 1.05
		play_anim("sit_to_type")
	elif sitting_subphase == 1 and state_timer <= 0.0:
		_enter_working()

func _enter_working() -> void:
	nav_agent.velocity = Vector3.ZERO
	nav_agent.avoidance_enabled = false
	if collision_shape:
		collision_shape.disabled = true
	state = State.WORKING
	is_seated = true
	_release_routine()
	state_timer = 28.0 + float(worker_index % 5) * 4.5 + randf_range(0.0, 5.0)
	play_anim("typing")
	_update_label()

func _process_working(_delta: float) -> void:
	if not is_instance_valid(target_chair):
		_force_stand_and_idle()
		return

	global_position = target_chair.get_seat_world_pos()
	rotation.y = target_chair.global_rotation.y

	if state_timer <= 0.0:
		_start_break_from_work()

func _start_break_from_work() -> void:
	if is_instance_valid(routines) and not routines.request_outing(self):
		state_timer = 1.0
		_update_label()
		return
	if not _planned_break and not _plan_break():
		_release_routine()
		state_timer = 8.0
		return
	if social_session_id != 0:
		_process_social_departure()
		return
	if is_instance_valid(routines) and not routines.request_stand(self):
		state_timer = 0.3
		_update_label()
		return
	_begin_standing()

func _begin_standing() -> void:
	var exit = target_chair.get_chair_exit_pos(self) if is_instance_valid(target_chair) else global_position
	if exit == null:
		state_timer = 0.3
		return
	_idle_after_standing = false
	_stand_exit_pos = exit
	_stand_start_pos = global_position
	_stand_length = anim_player.get_animation("office/sit_to_stand").length
	state = State.BREAK
	break_phase = BreakPhase.STAND_TYPE_TO_SIT
	state_timer = 0.85
	play_anim("type_to_sit")
	_update_label()

func _process_break(delta: float) -> void:
	match break_phase:
		BreakPhase.STAND_TYPE_TO_SIT:
			if state_timer <= 0.0:
				break_phase = BreakPhase.STAND_SIT_TO_STAND
				state_timer = _stand_length
				play_anim("sit_to_stand")
		BreakPhase.STAND_SIT_TO_STAND:
			var progress := 1.0 - maxf(state_timer, 0.0) / _stand_length
			global_position = _stand_start_pos.lerp(_stand_exit_pos, smoothstep(0.2, 0.9, progress))
			if state_timer <= 0.0:
				is_seated = false
				if is_instance_valid(routines):
					routines.finish_stand(self)
				if collision_shape:
					collision_shape.disabled = false
				# Keep ownership of assigned_chair, just clear active sitting target
				target_chair = assigned_chair
				if _idle_after_standing:
					_enter_idle(1.5)
				else:
					_choose_and_walk_to_break()
		BreakPhase.PERFORM_ACTION:
			if break_type != BreakType.CHAT_WORKER and (not is_instance_valid(target_furniture) or target_furniture.is_preview or is_instance_valid(target_furniture.being_moved_by)):
				_enter_idle(2.0)
				return
			if break_type == BreakType.CHAT_WORKER and (not is_instance_valid(target_partner) or target_partner.combat.is_engaged() or target_partner.global_position.distance_to(global_position) > 2.0):
				_enter_idle(1.0)
				return
			# Smoothly face the target object or coworker during break
			if break_type == BreakType.CHAT_WORKER and is_instance_valid(target_partner):
				var to_p := target_partner.global_position - global_position
				if to_p.length_squared() > 0.001:
					target_face_yaw = atan2(to_p.x, to_p.z)
			elif is_instance_valid(target_furniture):
				target_face_yaw = target_furniture.get_look_at_object_yaw(global_position)

			rotation.y = lerp_angle(rotation.y, target_face_yaw, clampf(delta * 8.0, 0.0, 1.0))

			if state_timer <= 0.0:
				_complete_break_task()
				target_partner = null
				_release_break_spot()
				# After finishing break, return strictly to this worker's OWN desk chair
				var my_chair: FurnitureItem = office_ref.get_or_assign_personal_chair(self) if office_ref else null
				if my_chair != null and _chair_retry_timer <= 0.0:
					_start_walking_to_chair(my_chair)
				else:
					_enter_idle(1.5)

func _release_break_spot() -> void:
	if is_instance_valid(target_furniture) and target_furniture.reserved_by == self:
		target_furniture.reserved_by = null
	target_furniture = null

func _release_routine() -> void:
	if social_session_id != 0 and is_instance_valid(routines):
		routines.finish_social(social_session_id, false, self)
	if is_instance_valid(routines):
		routines.release(self)
	_planned_break = false
	_forced_stand_pending = false

func _plan_break() -> bool:
	_release_break_spot()
	if office_ref == null:
		return false
	var choices: Array[Dictionary] = [
		{"kind": BreakType.WATER_COOLER, "need": thirst, "tag": "water"},
		{"kind": BreakType.KITCHEN_COFFEE, "need": fatigue, "tag": "kitchen"},
		{"kind": BreakType.OFFICE_ERRAND, "need": task_pressure, "tag": "errand"},
		{"kind": BreakType.LOUNGE_RELAX, "need": focus_strain, "tag": "lounge"},
		{"kind": BreakType.CONFERENCE_ROOM, "need": task_pressure * 0.65, "tag": "conference"},
		{"kind": BreakType.CHAT_WORKER, "need": social_need, "tag": "social"}
	]
	choices.sort_custom(func(a: Dictionary, b: Dictionary):
		var score_a := float(a["need"]) - (0.35 if a["kind"] == last_break_type else 0.0)
		var score_b := float(b["need"]) - (0.35 if b["kind"] == last_break_type else 0.0)
		return score_a > score_b
	)
	for choice in choices:
		if choice["tag"] == "social":
			if social_need >= 0.45 and social_cooldown <= 0.0 and is_instance_valid(routines) and routines.try_start_social(self):
				return true
			continue
		if float(_break_cooldowns.get(choice["kind"], 0.0)) > 0.0:
			continue
		var spot: FurnitureItem = office_ref.find_tagged_spot(choice["tag"], self)
		if spot == null:
			continue
		break_type = choice["kind"]
		target_furniture = spot
		spot.reserved_by = self
		_planned_break = true
		return true
	return false

func _choose_and_walk_to_break() -> void:
	if social_session_id != 0:
		_planned_break = false
		walk_goal = WalkGoal.TO_BREAK
		_enter_walking(target_walk_pos)
		return
	if not _planned_break and not _plan_break():
		_deskless_wait = 10.0
		_enter_idle(3.0)
		return
	_planned_break = false
	if not is_instance_valid(target_furniture) or target_furniture.is_preview or is_instance_valid(target_furniture.being_moved_by):
		_enter_idle(2.0)
		return
	target_partner = null
	walk_goal = WalkGoal.TO_BREAK
	_enter_walking(target_furniture.get_interact_world_pos())

func _complete_break_task() -> void:
	if break_type == BreakType.CHAT_WORKER:
		return
	completed_tasks += 1
	last_break_type = break_type
	_deskless_wait = 18.0 + float(worker_index % 4) * 3.0
	match break_type:
		BreakType.WATER_COOLER: thirst = 0.0
		BreakType.KITCHEN_COFFEE: fatigue = 0.0
		BreakType.OFFICE_ERRAND: task_pressure = 0.0
		BreakType.CONFERENCE_ROOM: task_pressure = maxf(0.0, task_pressure - 0.65)
		BreakType.LOUNGE_RELAX: focus_strain = 0.0
	_update_label()

func _enter_break_perform() -> void:
	state = State.BREAK
	break_phase = BreakPhase.PERFORM_ACTION
	is_seated = false
	if collision_shape:
		collision_shape.disabled = false

	match break_type:
		BreakType.WATER_COOLER:
			state_timer = randf_range(4.8, 6.8)
			play_anim("drink" if randf() < 0.6 else "watercooler")
		BreakType.KITCHEN_COFFEE:
			state_timer = randf_range(4.8, 6.8)
			play_anim("drink")
		BreakType.CONFERENCE_ROOM:
			state_timer = randf_range(5.0, 7.2)
			play_anim("talk2" if randf() < 0.5 else "lean")
		BreakType.OFFICE_ERRAND:
			state_timer = randf_range(4.2, 6.0)
			play_anim("lean" if randf() < 0.6 else "idle_breath")
		BreakType.CHAT_WORKER:
			state_timer = randf_range(5.0, 7.0)
			play_anim("talk" if randf() < 0.55 else "talk2")
			if is_instance_valid(target_partner) and not target_partner.is_seated:
				target_partner.join_coworker_chat(self)
		_:
			state_timer = randf_range(4.5, 6.5)
			play_anim("stretch" if randf() < 0.55 else "lean")

	_update_label()

func join_coworker_chat(initiator: OfficeWorker) -> void:
	social.join_coworker_chat(initiator)

func greet_player(player: OfficeWorker) -> void:
	social.greet_player(player)

func on_furniture_removed_or_moved(item: FurnitureItem, was_deleted: bool = false) -> void:
	var affected := item == target_chair or item == target_furniture or item == assigned_chair or item == assigned_desk
	if not affected: return
	if is_instance_valid(player_conversation_partner):
		end_player_conversation(player_conversation_partner)
	if was_deleted:
		if item == assigned_chair:
			assigned_chair = null
			assigned_desk = null
		elif item == assigned_desk:
			assigned_desk = null
		if item == target_chair:
			# A destroyed seat cannot support a queued stand-up animation.
			_release_routine()
			_release_break_spot()
			target_chair = null
			is_seated = false
			global_position.y = 0.0
			collision_shape.set_deferred("disabled", false)
			if not combat.is_engaged(): _enter_idle(0.8)
			return
	_force_stand_and_idle()

func _force_stand_and_idle() -> void:
	if combat.is_engaged():
		return
	if is_seated:
		if state == State.BREAK and break_phase != BreakPhase.PERFORM_ACTION:
			_idle_after_standing = true
			return
		_release_routine()
		_release_break_spot()
		if is_instance_valid(routines) and not routines.request_stand(self):
			_forced_stand_pending = true
			return
		_begin_standing()
		_idle_after_standing = true
		return
	target_chair = assigned_chair if is_instance_valid(assigned_chair) else null
	_release_break_spot()
	is_seated = false
	if collision_shape:
		collision_shape.disabled = false
	_enter_idle(0.8)

func interrupt_for_combat() -> void:
	if is_instance_valid(player_conversation_partner):
		end_player_conversation(player_conversation_partner)
	_release_routine()
	# Cancel reservations and navigation callbacks before combat takes movement.
	if is_seated and is_instance_valid(target_chair):
		global_position = target_chair.get_chair_approach_pos()
	is_seated = false
	_release_break_spot()
	target_partner = null
	if is_instance_valid(target_chair) and target_chair.reserved_by == self:
		target_chair.reserved_by = null
	state = State.IDLE
	state_timer = 1.5
	_path_initialized = false
	collision_shape.set_deferred("disabled", false)
	_stop_walking_velocity()

func is_willing_to_socialize(initiator: OfficeWorker) -> bool:
	return social.is_willing_to_socialize(initiator)

func _prepare_social_session(partner: OfficeWorker, meeting_position: Vector3, id: int) -> void:
	social.prepare_social_session(partner, meeting_position, id)

func _process_social_departure() -> void:
	social.process_social_departure()

func _begin_social_talk() -> void:
	social.begin_social_talk()

func show_social_speech(line: String) -> void:
	social.show_social_speech(line)

func _finish_social_session(completed: bool, interrupted := false) -> void:
	social.finish_social_session(completed, interrupted)

func _return_to_own_work() -> void:
	social.return_to_own_work()

func can_accept_player_conversation(player: OfficeWorker) -> bool:
	return social.can_accept_player_conversation(player)

func begin_player_conversation(player: OfficeWorker) -> bool:
	return social.begin_player_conversation(player)

func end_player_conversation(player: OfficeWorker) -> void:
	social.end_player_conversation(player)

