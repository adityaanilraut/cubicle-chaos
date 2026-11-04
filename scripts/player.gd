class_name OfficePlayer
extends OfficeWorker

const WALK_SPEED := 2.8
const RUN_SPEED := 5.2
var running := false
var standing_up := false
var _stand_origin := Vector3.ZERO
var _stand_destination := Vector3.ZERO
var _stand_duration := 0.0

var office: Node3D
var carried_cup: Node3D
var nearby: Node3D
var prompt: Label
var objective: Label
var message: Label
var quest := 0 # 0 meet Maya, 1 take cup, 2 fill cup, 3 deliver, 4 finished
var busy := 0.0
var seated := false
var sitting_chair: FurnitureItem
var elapsed := 0.0
var cup_filled := false
var hand_attachment: BoneAttachment3D
var cup_in_hand := false
var drop_queued := false
var grabbed_furniture: FurnitureItem
var movable_nearby: FurnitureItem
var grip_local_point := Vector3.ZERO
var grab_axis := Vector3.FORWARD
var furniture_motion := "grip"
var grip_modifier: FurnitureGrip
var combat_hint: Label
var combat_target_marker: MeshInstance3D
var _cup_action_id := 0
var _cup_in_transition: Node3D
var _resting_cup: Node3D
var _cup_support: FurnitureItem
var _cup_surface_point := Vector3.ZERO
var interaction_focus: InteractionFocus
var interaction_actions: InteractionActions
var hud_layer: CanvasLayer
var interaction_hints_enabled := true
var gameplay_visible := true
var equipment: OfficeEquipment
var dialogue: OfficeDialogue
var work_status: Label
var activity_progress: ProgressBar
var held_prop: PhysicsProp
var nearby_prop: PhysicsProp
var prop_handling: PropHandling
var mouse_controls: MouseControls
var prop_grip: PropGrip
var cup_handling: PlayerCup
var high_contrast := false

func setup_player(p_office: Node3D) -> void:
	office = p_office
	super.setup(null, 99, "You", 7)
	combat.is_player = true
	remove_from_group("workers")
	status_label.text = "YOU"
	status_label.modulate = Color(1.0, 0.87, 0.25)
	# Report player movement to coworkers while retaining direct player control.
	# The inherited safe-velocity callback ignores this player's idle AI state.
	nav_agent.avoidance_enabled = true
	nav_agent.avoidance_priority = 1.0
	nav_agent.avoidance_mask = 0
	nav_agent.max_speed = RUN_SPEED
	var skeleton := rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	hand_attachment = BoneAttachment3D.new()
	hand_attachment.name = "CupHand"
	hand_attachment.bone_name = "office_RightHand"
	skeleton.add_child(hand_attachment)
	grip_modifier = FurnitureGrip.new()
	grip_modifier.player = self
	grip_modifier.active = false
	skeleton.add_child(grip_modifier)
	prop_grip = PropGrip.new()
	prop_grip.player = self
	skeleton.add_child(prop_grip)
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.38
	mesh.bottom_radius = 0.38
	mesh.height = 0.025
	ring.mesh = mesh
	ring.material_override = AssetCatalog.get_shared_material("player_marker", Color(1.0, 0.78, 0.18), 0.7)
	ring.position.y = 0.025
	add_child(ring)
	process_priority = 100
	_make_ui()
	interaction_focus = InteractionFocus.new()
	interaction_focus.name = "NearbyWhiteOutline"
	add_child(interaction_focus)
	interaction_actions = InteractionActions.new()
	hud_layer.add_child(interaction_actions)
	interaction_actions.setup(self)
	equipment = OfficeEquipment.new()
	add_child(equipment)
	equipment.setup(self)
	dialogue = OfficeDialogue.new()
	add_child(dialogue)
	dialogue.setup(self)
	prop_handling = PropHandling.new()
	add_child(prop_handling)
	prop_handling.setup(self)
	cup_handling = PlayerCup.new(self)
	mouse_controls = MouseControls.new()
	add_child(mouse_controls)
	mouse_controls.setup(self)
	combat_target_marker = mouse_controls._ring("CombatTarget", Color(1.0, 0.38, 0.18), 0.43)
	_update_equipment_hud()

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	hud_layer = layer
	layer.layer = 5
	add_child(layer)
	# Existing interaction systems write status here; normal play has no fixed panels.
	for field in ["objective", "prompt", "message", "combat_hint", "work_status"]:
		var status := Label.new()
		status.visible = false
		layer.add_child(status)
		set(field, status)
	combat_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	combat_hint.offset_left = -300
	combat_hint.offset_right = 300
	combat_hint.offset_top = -105
	combat_hint.offset_bottom = -20
	combat_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_hint.add_theme_font_size_override("font_size", 16)
	combat_hint.add_theme_color_override("font_color", Color.WHITE)
	combat_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	combat_hint.add_theme_constant_override("shadow_offset_x", 2)
	combat_hint.add_theme_constant_override("shadow_offset_y", 2)
	activity_progress = ProgressBar.new()
	activity_progress.visible = false
	layer.add_child(activity_progress)
	_update_objective()

func _update_equipment_hud() -> void:
	if not is_instance_valid(equipment): return
	work_status.text = equipment.get_summary()
	activity_progress.visible = false
	activity_progress.value = 100.0 * (1.0 - equipment.remaining / equipment.duration) if equipment.is_active() else 0.0

func _update_objective() -> void:
	objective.text = ""

func _physics_process(delta: float) -> void:
	elapsed += delta
	running = false
	mouse_controls.tick(delta)
	prop_handling.tick(delta)
	if combat.buffered_fight > 0.0 and (busy > 0.0 or seated or equipment.is_active() or dialogue.is_open or is_instance_valid(carried_cup) or is_instance_valid(grabbed_furniture) or (is_instance_valid(held_prop) and not combat.has_bat()) or office.edit_mode != office.EditMode.SELECT):
		combat.buffered_fight = 0.0
	if gameplay_visible and OfficeInput.is_pressed("fight") and not combat.is_busy() and combat.cooldown <= 0.0 and combat.buffered_fight <= 0.0:
		try_attack("light")
	if combat.tick(delta):
		# Combat can move or turn the player without going through normal carry
		# movement. Keep the equipped bat with the player during those reactions.
		if combat.has_bat(): held_prop.global_transform = BaseballBat.held_pose(self)
		equipment.cancel("Activity interrupted by combat.")
		if dialogue.is_open: dialogue.close()
		status_label.text = "YOU • " + combat.status().to_upper()
		office.iso_camera.focus_on(global_position)
		_update_nearby()
		return
	var using_equipment := equipment.tick(delta)
	_update_equipment_hud()
	if dialogue.is_open:
		velocity = Vector3.ZERO
		nav_agent.velocity = Vector3.ZERO
		play_anim("talk")
		_update_nearby()
		return
	if using_equipment:
		status_label.text = "YOU • " + String(OfficeEquipment.DEFINITIONS[equipment.active_action].label).to_upper()
		office.iso_camera.focus_on(global_position)
		_update_nearby()
		return
	status_label.text = "YOU • MOVING FURNITURE" if is_instance_valid(grabbed_furniture) else "YOU"
	if seated and not is_instance_valid(sitting_chair):
		seated = false
		standing_up = false
		collision_shape.set_deferred("disabled", false)
		busy = 0.0
	if busy > 0.0:
		busy -= delta
		velocity = Vector3.ZERO
		nav_agent.velocity = Vector3.ZERO
		if standing_up:
			var progress := 1.0 - maxf(busy, 0.0) / _stand_duration
			global_position = _stand_origin.lerp(_stand_destination, smoothstep(0.2, 0.9, progress))
			office.iso_camera.focus_on(global_position)
		if busy <= 0.0:
			if standing_up: _finish_standing()
			if drop_queued and is_instance_valid(carried_cup):
				drop_queued = false
				_drop_cup()
			elif not seated:
				play_anim("idle")
		_update_nearby()
		return
	if seated:
		nav_agent.velocity = Vector3.ZERO
		_update_nearby()
		return
	var input := Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)), float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	var yaw: float = office.iso_camera.global_rotation.y
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var dir := (right * input.x + forward * input.y).normalized()
	if input.length_squared() > 0:
		mouse_controls.stop_walking()
	else:
		dir = mouse_controls.movement_direction()
	if is_instance_valid(grabbed_furniture):
		_process_furniture_move(dir, delta)
		office.iso_camera.focus_on(global_position)
		_update_nearby()
		return
	elif grip_modifier.active:
		release_furniture()
	var before_motion := global_transform
	if prop_handling.is_locked(): dir = Vector3.ZERO
	running = dir.length_squared() > 0.01 and Input.is_key_pressed(KEY_SHIFT) and not is_instance_valid(carried_cup) and not is_instance_valid(held_prop) and office.edit_mode == office.EditMode.SELECT
	var carry_scale := held_prop.carry_speed_scale if is_instance_valid(held_prop) else 1.0
	velocity = dir * (RUN_SPEED if running else WALK_SPEED) * carry_scale
	if prop_handling.charging: velocity *= 0.4
	var mouse_facing := combat.face_locked_target(delta)
	if not mouse_facing: mouse_facing = mouse_controls.face_pointer(delta)
	if dir.length_squared() > 0.01:
		if not prop_handling.charging and not mouse_facing: rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(delta * 10.0, 0.0, 1.0))
	move_and_slide()
	if not prop_handling.follow_held():
		global_transform = before_motion
		velocity = Vector3.ZERO
		prop_handling.follow_held()
	var moved := global_position.distance_squared_to(before_motion.origin) > 0.000001
	running = running and moved
	if running: status_label.text = "YOU • RUNNING"
	play_anim(("run" if running else "walk") if moved else "idle")
	nav_agent.velocity = velocity
	global_position.y = 0.0
	var bounds: Rect2 = office.FLOOR_BOUNDS.grow(-0.5)
	global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
	global_position.z = clampf(global_position.z, bounds.position.y, bounds.end.y)
	office.iso_camera.focus_on(global_position)
	_update_nearby()

func _process(_delta: float) -> void:
	# Follow the animated hand in world space. Keeping the cup upright separately
	# avoids inheriting the wrist's rotation and scale as the character moves.
	if cup_in_hand and is_instance_valid(carried_cup) and is_instance_valid(hand_attachment):
		carried_cup.global_position = hand_attachment.global_position + Vector3(0.0, -0.10, 0.0)
		carried_cup.global_rotation = Vector3.ZERO
	if is_instance_valid(_resting_cup):
		if is_instance_valid(_cup_support) and not _cup_support.is_queued_for_deletion():
			_resting_cup.global_position = _cup_support.to_global(_cup_surface_point)
		else:
			_resting_cup.global_position.y = 0.0
			_cup_support = null

func _update_nearby() -> void:
	_update_combat_hint()
	if not is_instance_valid(held_prop):
		held_prop = null
	nearby_prop = _find_nearby_prop()
	nearby = null
	movable_nearby = null
	if combat.is_busy():
		prompt.text = combat.status() + (" • Getting back up automatically…" if combat.is_down() else "")
	elif dialogue.is_open:
		if is_instance_valid(dialogue.speaker):
			prompt.text = "Talking to " + dialogue.speaker.worker_name + " • F to finish"
		else:
			dialogue.close()
			prompt.text = "The conversation has ended."
	elif equipment.is_active():
		nearby = equipment.active_item
		prompt.text = equipment.get_progress_text()
	elif busy > 0.0:
		prompt.text = "Finishing your interaction…"
	elif is_instance_valid(grabbed_furniture):
		nearby = grabbed_furniture
		prompt.text = "Moving " + grabbed_furniture.item_title + " • WASD to move in any direction • B / F to release"
	elif seated:
		nearby = sitting_chair
		prompt.text = "[F] Stand up"
	else:
		var best := INF
		var best_priority := 2
		for node in get_tree().get_nodes_in_group("player_interactable") + get_tree().get_nodes_in_group("furniture") + get_tree().get_nodes_in_group("workers"):
			if not _can_reach_interaction(node):
				continue
			var point: Vector3 = node.closest_surface_point(global_position) if node is FurnitureItem else node.global_position
			var distance := Vector2(global_position.x - point.x, global_position.z - point.z).length()
			# Non-interactive furniture is only relevant at actual grabbing range.
			if node is FurnitureItem and not node.is_chair and not node.is_water_dispenser:
				if not (is_instance_valid(carried_cup) and node.can_hold_cup()) and not equipment.handles(node) and (distance >= 0.65 or not node.can_player_move() or node.is_in_use() or is_instance_valid(carried_cup)):
					continue
			# A coworker's own desk/chair must not steal their Talk action.
			if node is FurnitureItem:
				var owner := node.owner_worker as OfficeWorker
				if is_instance_valid(owner) and owner.is_seated and owner.can_accept_player_conversation(self) and _can_reach_interaction(owner): continue
				if node == _cup_support and is_instance_valid(_resting_cup) and not is_instance_valid(carried_cup) and _can_reach_interaction(_resting_cup): continue
			var priority := 1
			if node is OfficeWorker and node.is_seated and node.can_accept_player_conversation(self): priority = 0
			elif node.is_in_group("player_interactable") and not is_instance_valid(carried_cup): priority = 0
			elif node is FurnitureItem and node.is_water_dispenser and is_instance_valid(carried_cup): priority = 0
			if priority < best_priority or (priority == best_priority and distance < best):
				best_priority = priority
				best = distance
				nearby = node
		movable_nearby = _find_movable_furniture()
		prompt.text = "Walk closer to a coworker, cup, chair, or water dispenser."
		if is_instance_valid(nearby):
			if nearby.is_in_group("player_interactable"):
				prompt.text = "[F] Pick up cup" if not is_instance_valid(carried_cup) else "Your hands are full"
			elif nearby is OfficeWorker:
				if not nearby.can_accept_player_conversation(self):
					prompt.text = nearby.worker_name + " • " + nearby.get_state_name()
				else:
					prompt.text = "[F] Talk to " + nearby.worker_name
			elif nearby is FurnitureItem and is_instance_valid(carried_cup) and not nearby.get_cup_spot(global_position).is_empty():
				prompt.text = "[F / G] Place cup on " + nearby.item_title
			elif nearby is FurnitureItem and nearby.is_water_dispenser:
				prompt.text = "[F] Fill cup" if is_instance_valid(carried_cup) else "[F] Drink water"
			elif nearby is FurnitureItem and nearby.is_chair:
				prompt.text = "%s’s assigned chair" % nearby.owner_worker.worker_name if is_instance_valid(nearby.owner_worker) else "Chair is reserved" if is_instance_valid(nearby.reserved_by) else "[F] Sit down"
			elif nearby is FurnitureItem and equipment.handles(nearby):
				prompt.text = equipment.get_hint(nearby)
			else:
				prompt.text = nearby.item_title
			if nearby == movable_nearby and not is_instance_valid(carried_cup) and not nearby.is_in_use():
				prompt.text += "   •   [B] Move furniture"
	if is_instance_valid(carried_cup) and busy <= 0.0 and not combat.is_busy():
		prompt.text += "   •   [G] " + ("Place on table" if not _find_cup_placement().is_empty() else "Put down cup")
	_refresh_context_display()
	_update_equipment_hud()

func _can_reach_interaction(node: Node) -> bool:
	if not is_instance_valid(node) or not node is Node3D or node == self or node.is_queued_for_deletion():
		return false
	if node is FurnitureItem and (node.is_preview or is_instance_valid(node.being_moved_by)):
		return false
	var point: Vector3 = node.closest_surface_point(global_position) if node is FurnitureItem else node.global_position
	var reach := 2.4 if node is OfficeWorker and node.is_seated else 1.65
	if Vector2(global_position.x - point.x, global_position.z - point.z).length() > reach:
		return false
	var exclusions: Array[RID] = [get_rid()]
	if node is CollisionObject3D:
		exclusions.append(node.get_rid())
	if node == _resting_cup and is_instance_valid(_cup_support): exclusions.append(_cup_support.get_rid())
	# Talk at face height, above desks. Keep walls and other people as blockers.
	var origin := global_position + Vector3.UP * (1.5 if node is OfficeWorker else 0.9)
	var endpoint := point + Vector3.UP * 0.9
	if node is OfficeWorker:
		endpoint = point + Vector3.UP * (1.35 if node.is_seated else 1.5)
	elif node.is_in_group("player_interactable"):
		origin = global_position + Vector3.UP * 1.35
		endpoint = point + Vector3.UP * 0.11
	var ray := PhysicsRayQueryParameters3D.create(origin, endpoint, 1 | 4, exclusions)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func get_context_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if combat.is_busy() or dialogue.is_open or busy > 0.0 or office.edit_mode != office.EditMode.SELECT:
		return actions
	if equipment.is_active():
		actions.append({"id": "cancel_activity", "key": OfficeInput.key_name("interact"), "label": "Cancel"})
		return actions
	if is_instance_valid(office.levels):
		var level_action: String = office.levels._action_kind()
		if level_action in ["drink", "coffee", "give"]:
			actions.append({"id": "level_" + level_action, "key": OfficeInput.key_name("interact"), "label": {"drink": "Drink coffee", "coffee": "Get coffee", "give": "Give coffee"}[level_action]})
			return actions
	if is_instance_valid(held_prop):
		if not prop_handling.is_locked():
			if combat.has_bat():
				actions.append({"id": "bat_light", "key": OfficeInput.key_name("fight"), "label": "Swing bat"})
				actions.append({"id": "bat_heavy", "key": OfficeInput.key_name("heavy_attack"), "label": "Smash"})
			actions.append({"id": "prop_throw", "key": OfficeInput.key_name("prop"), "label": "Throw", "hint": "Tap to throw; hold to charge and aim with the mouse."})
			actions.append({"id": "prop_place", "key": OfficeInput.key_name("place"), "label": "Place gently"})
		return actions
	if is_instance_valid(grabbed_furniture):
		actions.append({"id": "release", "key": OfficeInput.key_name("grab") + " / " + OfficeInput.key_name("interact"), "label": "Release"})
	elif seated:
		actions.append({"id": "interact", "key": OfficeInput.key_name("interact"), "label": "Stand"})
	elif is_instance_valid(nearby) and _can_reach_interaction(nearby):
		var label := ""
		if nearby.is_in_group("player_interactable") and not is_instance_valid(carried_cup):
			label = "Pick up"
		elif nearby is OfficeWorker and nearby.can_accept_player_conversation(self):
			label = dialogue.get_talk_label(nearby)
		elif nearby is FurnitureItem and is_instance_valid(carried_cup) and not nearby.get_cup_spot(global_position).is_empty():
			label = "Place cup"
		elif nearby is FurnitureItem and nearby.is_water_dispenser:
			label = "Fill cup" if is_instance_valid(carried_cup) else "Drink"
		elif nearby is FurnitureItem and nearby.is_chair and not is_instance_valid(nearby.owner_worker) and not is_instance_valid(nearby.reserved_by):
			label = "Sit"
		if not label.is_empty():
			actions.append({"id": "interact", "key": OfficeInput.key_name("interact"), "label": label})
		if nearby is FurnitureItem and equipment.handles(nearby):
			actions.append_array(equipment.get_actions(nearby))
		if nearby is FurnitureItem and nearby == movable_nearby and not nearby.is_in_use() and not is_instance_valid(carried_cup):
			actions.append({"id": "grab", "key": OfficeInput.key_name("grab"), "label": "Move"})
		if nearby is OfficeWorker and not is_instance_valid(carried_cup) and combat.cooldown <= 0.0:
			if combat.find_target(OfficeCombat.KICK_REACH) == nearby:
				actions.append({"id": "fight", "key": OfficeInput.key_name("fight"), "label": "Fight", "hint": "Tap or hold for light attacks. Use %s for a heavy attack. They will fight back." % OfficeInput.key_name("heavy_attack")})
	if is_instance_valid(carried_cup):
		actions.append({"id": "drop", "key": OfficeInput.key_name("place"), "label": "Place on table" if not _find_cup_placement().is_empty() else "Put down"})
	if is_instance_valid(held_prop):
		actions.append({"id": "prop_throw", "key": OfficeInput.key_name("prop"), "label": "Throw " + held_prop.prop_title})
	elif is_instance_valid(nearby_prop) and not is_instance_valid(carried_cup) and not is_instance_valid(grabbed_furniture) and not seated:
		actions.append({"id": "prop_pickup", "key": OfficeInput.key_name("prop"), "label": "Pick up " + nearby_prop.prop_title, "target": nearby_prop})
	return actions

func _find_nearby_prop() -> PhysicsProp:
	if is_instance_valid(held_prop) and held_prop.is_held():
		return null
	var best: PhysicsProp = null
	var best_distance := 1.7
	for node in get_tree().get_nodes_in_group("physics_props"):
		var prop := node as PhysicsProp
		if prop == null or prop.is_held() or not is_instance_valid(prop):
			continue
		var distance := global_position.distance_to(prop.global_position)
		if distance < best_distance and prop_handling.can_pick_up(prop):
			best_distance = distance
			best = prop
	return best

func try_pickup_prop() -> bool:
	if is_instance_valid(held_prop):
		return prop_handling.release_throw(0.0)
	var prop := _find_nearby_prop()
	if prop == null or not prop_handling.pick_up(prop):
		return false
	message.text = "Picked up " + prop.prop_title + ". Tap T to throw; hold T to charge; G to place."
	_update_nearby()
	return true

func throw_prop() -> void:
	prop_handling.release_throw(0.0)
	_update_nearby()

func place_prop() -> bool:
	var placed := prop_handling.place_gently()
	_update_nearby()
	return placed

func _refresh_context_display() -> void:
	if not is_instance_valid(interaction_focus) or not is_instance_valid(interaction_actions):
		return
	var show_hints: bool = gameplay_visible and interaction_hints_enabled and office.edit_mode == office.EditMode.SELECT
	interaction_focus.set_target((held_prop if is_instance_valid(held_prop) else nearby if is_instance_valid(nearby) else nearby_prop) if show_hints else null)
	if not show_hints:
		interaction_actions.visible = false
		return
	var anchor: Node3D = held_prop if is_instance_valid(held_prop) else nearby if is_instance_valid(nearby) else nearby_prop if is_instance_valid(nearby_prop) else self
	var title := "Cup in hand"
	if nearby is FurnitureItem:
		title = nearby.item_title
	elif nearby is OfficeWorker:
		title = nearby.worker_name + (" · Boss" if nearby.is_boss else "")
	elif is_instance_valid(nearby):
		title = "Water cup"
	if anchor is PhysicsProp: title = anchor.prop_title
	interaction_actions.show_actions(anchor, get_context_actions(), title)

func perform_context_action(action_id: String, expected_target: Node3D) -> void:
	# Moving people and furniture may invalidate a circle between draw and click.
	_update_nearby()
	if action_id.begins_with("prop_") or action_id.begins_with("bat_"):
		var expected_prop := held_prop if is_instance_valid(held_prop) else nearby_prop
		if expected_target != expected_prop: return
		var legal := false
		for action in get_context_actions():
			if action.id == action_id: legal = true
		if not legal: return
		match action_id:
			"prop_throw": throw_prop()
			"prop_place": place_prop()
			"prop_pickup": try_pickup_prop()
			"bat_light": try_attack("light", true)
			"bat_heavy": try_attack("heavy", true)
		_update_nearby()
		return
	if action_id != "drop" and expected_target != nearby:
		return
	var allowed := false
	for action in get_context_actions():
		if action.id == action_id:
			allowed = true
	if not allowed:
		return
	if action_id.begins_with("level_"):
		office.levels.perform_action()
		_update_nearby()
		return
	if action_id.begins_with("eq_"):
		equipment.perform(action_id, nearby as FurnitureItem)
		_update_nearby()
		return
	match action_id:
		"cancel_activity": equipment.cancel()
		"interact": interact()
		"grab": try_grab_furniture()
		"release": release_furniture()
		"drop": _drop_cup()
		"prop_pickup": try_pickup_prop()
		"prop_throw": throw_prop()
		"fight": try_attack("light", true)
	_update_nearby()

func set_interaction_hints_enabled(enabled: bool) -> void:
	interaction_hints_enabled = enabled
	_refresh_context_display()

func set_high_contrast_enabled(enabled: bool) -> void:
	high_contrast = enabled
	if is_instance_valid(interaction_focus):
		interaction_focus.set_high_contrast(enabled)

func set_gameplay_visible(enabled: bool) -> void:
	gameplay_visible = enabled
	if not enabled:
		combat.buffered_fight = 0.0
		if is_instance_valid(combat_target_marker): combat_target_marker.visible = false
		if is_instance_valid(prop_handling): prop_handling.cancel_charge()
		if is_instance_valid(mouse_controls): mouse_controls.cancel()
	if is_instance_valid(hud_layer):
		hud_layer.visible = enabled
	_refresh_context_display()

func _unhandled_input(event: InputEvent) -> void:
	if not gameplay_visible:
		return
	if mouse_controls.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		prop_handling.mouse_seen = true
	if event is InputEventKey and OfficeInput.matches(event, "prop") and not event.pressed:
		if prop_handling.charge_source == "keyboard": prop_handling.release_throw()
		get_viewport().set_input_as_handled()
		return
	if dialogue.is_open:
		if event is InputEventKey: get_viewport().set_input_as_handled()
		return
	if equipment.is_active():
		if event is InputEventKey and event.pressed and not event.echo and OfficeInput.matches(event, "interact"):
			equipment.cancel()
			_update_nearby()
		if event is InputEventKey: get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if OfficeInput.matches(event, "prop"):
			if is_instance_valid(held_prop):
				prop_handling.begin_charge()
			else:
				try_pickup_prop()
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "fight"):
			try_attack("light", true)
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "heavy_attack"):
			try_attack("heavy", true)
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "grab"):
			if is_instance_valid(grabbed_furniture):
				release_furniture()
			else:
				try_grab_furniture()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_instance_valid(grabbed_furniture):
			release_furniture()
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "interact"):
			_update_nearby()
			if is_instance_valid(office.levels) and office.levels._action_kind() == "repair":
				get_viewport().set_input_as_handled()
				return
			if not is_instance_valid(office.levels) or not office.levels.perform_action():
				interact()
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "secondary") and nearby is FurnitureItem and equipment.handles(nearby):
			var actions := equipment.get_actions(nearby)
			if actions.size() > 1: equipment.perform(actions[1].id, nearby)
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "place") and is_instance_valid(held_prop):
			place_prop()
			get_viewport().set_input_as_handled()
		elif OfficeInput.matches(event, "place") and is_instance_valid(carried_cup):
			if busy > 0.0:
				drop_queued = true
				message.text = "Putting the cup down as soon as you finish."
			else:
				_drop_cup()
			get_viewport().set_input_as_handled()

func interact() -> void:
	if dialogue.is_open: return
	if equipment.is_active():
		equipment.cancel()
		return
	if office.edit_mode != office.EditMode.SELECT:
		return
	if combat.is_busy():
		return
	if is_instance_valid(grabbed_furniture):
		release_furniture()
		return
	if busy > 0.0 or is_instance_valid(held_prop) or prop_handling.is_locked():
		return
	if seated:
		stand_from_chair()
		return
	if not _can_reach_interaction(nearby):
		return
	var direction := nearby.global_position - global_position
	if direction.length_squared() > 0.01:
		rotation.y = atan2(direction.x, direction.z)
	if nearby.is_in_group("player_interactable") and carried_cup == null:
		var cup := nearby
		cup.remove_from_group("player_interactable")
		carried_cup = cup
		_pick_up_cup(cup)
		message.text = "Picking up the cup..."
		if quest == 1:
			quest = 3 if cup_filled else 2
	elif nearby is OfficeWorker:
		var coworker: OfficeWorker = nearby
		if coworker.combat.is_engaged() or not dialogue.open(coworker): return
		if is_instance_valid(office.levels): office.levels.talked()
		play_anim("wave")
		busy = 2.0
		message.text = "Chatting with " + coworker.worker_name
	elif nearby is FurnitureItem and is_instance_valid(carried_cup) and not nearby.get_cup_spot(global_position).is_empty():
		_drop_cup({"item": nearby})
	elif nearby is FurnitureItem and equipment.handles(nearby):
		var actions := equipment.get_actions(nearby)
		if not actions.is_empty(): equipment.perform(actions[0].id, nearby)
		else: message.text = equipment.get_hint(nearby)
	elif nearby is FurnitureItem and nearby.is_water_dispenser:
		play_anim("drink" if carried_cup == null else "watercooler")
		busy = 2.5
		if carried_cup != null:
			cup_filled = true
			if quest == 2:
				quest = 3
			message.text = "You filled the cup with water."
		else:
			message.text = "A refreshing water break."
	elif nearby is FurnitureItem and nearby.is_chair:
		if is_instance_valid(nearby.owner_worker):
			message.text = "This is %s's chair. Try an unassigned chair." % nearby.owner_worker.worker_name
			return
		if is_instance_valid(nearby.reserved_by):
			message.text = "Someone has reserved this chair."
			return
		sitting_chair = nearby
		mouse_controls.cancel()
		sitting_chair.reserved_by = self
		velocity = Vector3.ZERO
		nav_agent.velocity = Vector3.ZERO
		global_position = sitting_chair.get_seat_world_pos()
		rotation.y = sitting_chair.global_rotation.y
		collision_shape.set_deferred("disabled", true)
		play_anim("stand_to_sit")
		seated = true
		busy = anim_player.get_animation("office/stand_to_sit").length
		message.text = "Taking a moment to relax. Press F to stand."
	_update_objective()

func stand_from_chair() -> bool:
	if standing_up or not seated or not is_instance_valid(sitting_chair): return false
	var exit = sitting_chair.get_chair_exit_pos(self)
	if exit == null:
		message.text = "There is no room to stand. Clear the front or sides of the chair."
		return false
	mouse_controls.cancel()
	standing_up = true
	_stand_origin = global_position
	_stand_destination = exit
	_stand_duration = anim_player.get_animation("office/sit_to_stand").length
	busy = _stand_duration
	velocity = Vector3.ZERO
	nav_agent.velocity = Vector3.ZERO
	play_anim("sit_to_stand")
	return true

func _finish_standing() -> void:
	global_position = _stand_destination
	if is_instance_valid(sitting_chair) and sitting_chair.reserved_by == self:
		sitting_chair.reserved_by = null
	standing_up = false
	seated = false
	sitting_chair = null
	collision_shape.set_deferred("disabled", false)

func on_furniture_destroyed(item: FurnitureItem) -> void:
	if grabbed_furniture == item:
		release_furniture()
	if sitting_chair == item:
		seated = false
		standing_up = false
		busy = 0.0
		sitting_chair = null
		global_position.y = 0.0
		velocity = Vector3.ZERO
		nav_agent.velocity = Vector3.ZERO
		collision_shape.set_deferred("disabled", false)
		if not combat.is_busy(): play_anim("idle")
	if equipment.active_item == item:
		equipment.cancel("The object broke. Activity cancelled.")
	if _cup_support == item:
		_cup_support = null
		if is_instance_valid(_resting_cup): _resting_cup.global_position.y = 0.0
	if nearby == item: nearby = null
	if movable_nearby == item: movable_nearby = null

func _find_movable_furniture() -> FurnitureItem:
	var best: FurnitureItem = null
	var best_distance := 0.65
	for node in get_tree().get_nodes_in_group("furniture"):
		var item := node as FurnitureItem
		if item == null or not item.can_player_move() or item.is_in_use():
			continue
		var surface := item.closest_surface_point(global_position)
		var distance := global_position.distance_to(surface)
		if distance >= best_distance or distance < 0.08:
			continue
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, surface + Vector3.UP * 0.6, 1, [get_rid(), item.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		best = item
		best_distance = distance
	return best

func try_grab_furniture() -> bool:
	if combat.is_busy() or busy > 0.0 or seated or equipment.is_active() or dialogue.is_open:
		message.text = "Stand up and finish your interaction first."
		return false
	if is_instance_valid(carried_cup) or is_instance_valid(held_prop):
		message.text = "Put down what you are carrying first — you need both hands."
		return false
	if office.edit_mode != office.EditMode.SELECT:
		message.text = "Finish or cancel furniture placement first."
		return false
	var item := _find_movable_furniture()
	if item == null:
		message.text = "Move closer to the edge of a piece of furniture, then press B."
		return false
	if item.is_in_use():
		message.text = "Someone is using this workstation. Wait until they stand up."
		return false
	var issue: String = office.get_placement_issue(item, item.global_position, item.global_rotation.y, self)
	if not issue.is_empty():
		message.text = "Use M in the furniture editor to clear this object's blocked position first."
		return false
	mouse_controls.cancel()
	grabbed_furniture = item
	item.being_moved_by = self
	item.set_selected(true)
	var contact := item.closest_surface_point(global_position)
	grab_axis = (contact - global_position).normalized()
	rotation.y = atan2(grab_axis.x, grab_axis.z)
	contact.y = clampf(item.footprint_size.y - 0.025, 0.28, 1.15)
	grip_local_point = item.to_local(contact)
	add_collision_exception_with(item)
	grip_modifier.active = true
	furniture_motion = "grip"
	play_anim("grip")
	office._notify_workers_furniture_changed(item, false)
	status_label.text = "YOU • MOVING FURNITURE"
	message.text = "Use WASD to move the object in any direction. B / F releases it."
	_update_nearby()
	return true

func _process_furniture_move(direction: Vector3, delta: float) -> void:
	var horizontal := Vector3(direction.x, 0.0, direction.z).limit_length(1.0)
	if horizontal.length_squared() < 0.0225:
		velocity = Vector3.ZERO
		nav_agent.velocity = Vector3.ZERO
		furniture_motion = "grip"
		play_anim("grip")
		return
	var item := grabbed_furniture
	var area := item.footprint_size.x * item.footprint_size.z
	var speed := clampf(1.1 - area * 0.035, 0.45, 1.05)
	var amount := horizontal.dot(grab_axis)
	var motion := horizontal * speed * delta
	var steps := maxi(1, ceili(motion.length() / 0.04))
	var step := motion / float(steps)
	var moved := Vector3.ZERO
	var blocked := ""
	for i in range(steps):
		var next_pos := item.global_position + step
		blocked = office.get_placement_issue(item, next_pos, item.global_rotation.y, self)
		if not blocked.is_empty():
			break
		if not _can_move_with_furniture(step, item):
			blocked = "There is no room to step that way."
			break
		item.global_position = next_pos
		global_position += step
		moved += step
	velocity = moved / maxf(delta, 0.001)
	nav_agent.velocity = velocity
	furniture_motion = ("pull" if amount < -0.15 else "push") if moved.length_squared() > 0.000001 else "grip"
	play_anim(furniture_motion)
	message.text = blocked if not blocked.is_empty() else "Moving " + item.item_title + " • B / F to release"

func _can_move_with_furniture(motion: Vector3, item: FurnitureItem) -> bool:
	var next := global_position + motion
	if not office.FLOOR_BOUNDS.grow(-0.27).has_point(Vector2(next.x, next.z)):
		return false
	if test_move(global_transform, motion):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.transform.origin += motion + Vector3.UP * 0.01
	query.collision_mask = 1 | 4
	query.exclude = [get_rid(), item.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func release_furniture() -> void:
	if is_instance_valid(grabbed_furniture):
		var item := grabbed_furniture
		remove_collision_exception_with(item)
		grabbed_furniture = null
		office.finish_player_furniture_move(item)
		message.text = "Furniture released."
	if is_instance_valid(grip_modifier):
		grip_modifier.active = false
	furniture_motion = "grip"
	status_label.text = "YOU"
	if not seated and busy <= 0.0:
		play_anim("idle")

# Reuse the character's animated bend and stand transitions: the cup remains on
# the floor during the reach, then follows the hand during the lift and walk.
func _pick_up_cup(cup: Node3D) -> void:
	cup_handling.pick_up_cup(cup)

func _find_cup_placement(preferred: FurnitureItem = null) -> Dictionary:
	return cup_handling.find_cup_placement(preferred)

func _drop_cup(requested: Dictionary = {}) -> void:
	cup_handling.drop_cup(requested)

func try_attack(kind: String = "auto", buffer_input := false) -> bool:
	if not gameplay_visible: return false
	if (combat.is_busy() or combat.cooldown > 0.0) and not buffer_input:
		return false
	if busy > 0.0 or seated or equipment.is_active() or dialogue.is_open:
		message.text = "Stand up and finish your interaction to fight."
		return false
	if prop_handling.is_locked(): return false
	if is_instance_valid(carried_cup) or is_instance_valid(grabbed_furniture) or (is_instance_valid(held_prop) and not combat.has_bat()):
		message.text = "Free your hands first: G puts down the cup; B releases furniture; T throws a prop."
		return false
	if office.edit_mode != office.EditMode.SELECT:
		message.text = "Finish or cancel furniture placement to fight."
		return false
	if (combat.request_fight(kind) if buffer_input and kind in ["auto", "light", "heavy"] else combat.start_attack(kind)):
		message.text = "Next strike queued." if combat.buffered_fight > 0.0 else ("Bat ready: light swings chain; heavy attack smashes down." if combat.has_bat() else "Tap to chain attacks. Heavy attacks have longer reach and windup.")
		return true
	return false

func _update_combat_hint() -> void:
	var opponent := combat.locked_target()
	if not is_instance_valid(opponent): opponent = combat.find_target(1.85 if combat.has_bat() else OfficeCombat.KICK_REACH)
	if combat.phase == OfficeCombat.Phase.ATTACK and is_instance_valid(combat.strike_target):
		opponent = combat.strike_target
	var show: bool = gameplay_visible and not office.editor_visible and office.edit_mode == office.EditMode.SELECT and not dialogue.is_open and not equipment.is_active() and (is_instance_valid(opponent) or combat.is_busy() or combat.stance_time > 0.0 or combat.departure_notice_time > 0.0)
	combat_hint.visible = show
	combat_target_marker.visible = show and is_instance_valid(opponent)
	if combat_target_marker.visible:
		combat_target_marker.global_position = opponent.global_position + Vector3.UP * 0.05
		var warning := opponent.combat.phase == OfficeCombat.Phase.ATTACK and opponent.combat.phase_time < float(opponent.combat.current_move().contact)
		combat_target_marker.scale = Vector3.ONE * (1.0 + 0.12 * sin(elapsed * 20.0) if warning else 1.0)
	if not show: return
	var text := ("BAT  •  %s  Swing  •  %s  Smash  •  %s" if combat.has_bat() else "%s  Light  •  %s  Heavy  •  %s") % [OfficeInput.key_name("fight"), OfficeInput.key_name("heavy_attack"), "Move to circle or dodge" if is_instance_valid(combat.target) else "Face or aim at a target"]
	if is_instance_valid(opponent):
		text += "\n%s%s  •  Health %d  •  Balance %d" % ["LOCKED · " if combat.target == opponent else "", opponent.worker_name, ceili(opponent.combat.health), maxi(0, ceili(opponent.combat.balance))]
		if combat.target == opponent: text += "  •  Retreat to disengage"
		if opponent.combat.is_down():
			text += "\nGets up and leaves" if opponent.combat.player_knockdowns >= 2 else "\nWatch out: gets up fighting"
		elif opponent.combat.revenge_pending:
			text += "\nCOUNTERATTACK · Move away to dodge"
		if opponent.combat.phase == OfficeCombat.Phase.ATTACK and opponent.combat.phase_time < float(opponent.combat.current_move().contact):
			text += "  •  INCOMING %s" % String(opponent.combat.current_move().label).to_upper()
	if combat.is_busy(): text += "\n" + combat.status()
	if combat.departure_notice_time > 0.0: text += "\n%s is leaving the office because of you." % combat.departure_name
	text += "   •   Your health %d  •  Balance %d" % [ceili(combat.health), maxi(0, ceili(combat.balance))]
	combat_hint.text = text

func interrupt_for_combat() -> void:
	if is_instance_valid(mouse_controls): mouse_controls.cancel()
	if is_instance_valid(prop_handling):
		if not combat.has_bat(): prop_handling.place_gently(true)
		prop_handling.reset()
	if is_instance_valid(dialogue): dialogue.close()
	if is_instance_valid(equipment):
		equipment.cancel("Activity interrupted by combat.")
		equipment.release_lounge_seat()
	if is_instance_valid(grabbed_furniture):
		release_furniture()
	if seated and is_instance_valid(sitting_chair):
		var exit = sitting_chair.get_chair_exit_pos(self)
		if exit != null: global_position = exit
		if sitting_chair.reserved_by == self: sitting_chair.reserved_by = null
	standing_up = false
	seated = false
	sitting_chair = null
	busy = 0.0
	_cup_action_id += 1
	var cup := carried_cup if is_instance_valid(carried_cup) else _cup_in_transition
	if is_instance_valid(cup):
		cup.global_position = Vector3(global_position.x, 0.0, global_position.z)
		cup.add_to_group("player_interactable")
	carried_cup = null
	_cup_in_transition = null
	cup_in_hand = false
	drop_queued = false
	super.interrupt_for_combat()
