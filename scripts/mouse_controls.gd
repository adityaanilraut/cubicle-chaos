class_name MouseControls
extends Node3D

# Mouse intent is separate from player locomotion and prop physics. Navigation
# supplies direction; the player's normal collision-checked movement applies it.
const ARRIVAL_DISTANCE := 0.22
const RETARGET_INTERVAL := 0.12
var player: OfficePlayer
var pointer := Vector2.ZERO
var pointer_seen := false
var dragging := false
var moving := false
var aiming := false
var destination := Vector3.ZERO
var aim_point := Vector3.ZERO
var retarget_time := 0.0
var stuck_time := 0.0
var last_position := Vector3.ZERO
var marker: MeshInstance3D
var reticle: MeshInstance3D

func setup(owner_player: OfficePlayer) -> void:
	player = owner_player
	top_level = true
	marker = _ring("MouseDestination", Color(0.98, 0.75, 0.20), 0.17)
	reticle = _ring("MouseAim", Color(0.95, 0.97, 1.0), 0.11)

func _ring(title: String, color: Color, radius: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius
	mesh.outer_radius = radius + 0.025
	instance.mesh = mesh
	instance.material_override = AssetCatalog.get_shared_material(title, color, 0.5, true)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	add_child(instance)
	return instance

func can_control() -> bool:
	return player.gameplay_visible and not player.office.editor_visible and player.office.edit_mode == player.office.EditMode.SELECT and not player.seated and player.busy <= 0.0 and not player.combat.is_busy() and not player.dialogue.is_open and not player.equipment.is_active()

func is_active() -> bool:
	return moving or dragging or aiming

func pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func floor_point(screen: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return null
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func aim_point_at(screen: Vector2) -> Variant:
	# A cursor on someone's torso must aim at that person, rather than at
	# the distant floor behind them in the isometric camera's projection.
	var camera := get_viewport().get_camera_3d()
	if camera == null: return null
	var exclusions: Array[RID] = [player.get_rid()]
	if is_instance_valid(player.held_prop): exclusions.append(player.held_prop.get_rid())
	var origin := camera.project_ray_origin(screen)
	var end := origin + camera.project_ray_normal(screen) * 180.0
	var ray := PhysicsRayQueryParameters3D.create(origin, end, 1 | 4 | 8, exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	# Seated coworkers disable their movement capsule to fit on the chair.
	# Pick their animated torso as well, while respecting objects in front.
	var nearest := origin.distance_to(hit.position) if not hit.is_empty() else 180.0
	var seated_target: OfficeWorker
	for worker in get_tree().get_nodes_in_group("workers"):
		if not worker.is_seated or not worker.collision_shape.disabled: continue
		var skeleton := worker.rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var hips := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("office_Hips")).origin)
		var head := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("office_Head")).origin)
		var points := Geometry3D.get_closest_points_between_segments(origin, end, hips, head)
		var distance := origin.distance_to(points[0])
		if points[0].distance_to(points[1]) < 0.24 and distance < nearest:
			nearest = distance
			seated_target = worker
	if seated_target != null: return seated_target.global_position
	if not hit.is_empty():
		var body = hit.collider
		if body is OfficeWorker or body is PhysicsProp:
			return body.global_position
		return hit.position
	return floor_point(screen)

func body_at(screen: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return null
	var origin := camera.project_ray_origin(screen)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 180.0, 1 | 4 | 8, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.get("collider") as Node3D

func set_pointer(screen: Vector2) -> void:
	pointer = screen
	pointer_seen = true
	player.prop_handling.mouse_seen = true

func handle_event(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		set_pointer(event.position)
		return false
	if not event is InputEventMouseButton or not event.pressed: return false
	set_pointer(event.position)
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		cancel()
		return false # Camera owns middle-drag, including Shift + middle.
	if not can_control() or pointer_over_ui(): return false
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not is_instance_valid(player.held_prop) and not is_instance_valid(player.grabbed_furniture) and _try_world_action(body_at(pointer)):
			return true
		var point = floor_point(pointer)
		if point != null and move_to(point): dragging = true
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if is_instance_valid(player.grabbed_furniture): return false
		var point = aim_point_at(pointer)
		if point == null: return false
		aiming = true
		aim_point = point
		player.prop_handling.set_aim_point(point)
		if is_instance_valid(player.held_prop): player.prop_handling.begin_charge("mouse")
		return true
	return false

func _try_world_action(body: Node3D) -> bool:
	if not is_instance_valid(body): return false
	if body is PhysicsProp:
		if player.prop_handling.pick_up(body):
			stop_walking()
			player._update_nearby()
			return true
	elif body is FurnitureItem or body is OfficeWorker:
		player._update_nearby()
		if player.nearby != body: return false
		for action in player.get_context_actions():
			if action.id == "interact" or action.id.begins_with("eq_"):
				stop_walking()
				player.perform_context_action(action.id, body)
				return true
	return false

func _input(event: InputEvent) -> void:
	# Releases arrive here even if a GUI control consumes them later. Only a
	# matching world press owns the gesture, so GUI clicks never start actions.
	if not event is InputEventMouseButton or event.pressed: return
	if event.button_index == MOUSE_BUTTON_LEFT:
		dragging = false
	elif event.button_index == MOUSE_BUTTON_RIGHT and aiming:
		set_pointer(event.position)
		aiming = false
		reticle.visible = false
		if player.prop_handling.charge_source != "mouse": return
		if can_control() and not pointer_over_ui():
			var point = aim_point_at(pointer)
			if point != null: player.prop_handling.set_aim_point(point)
			player.prop_handling.release_throw()
		else:
			player.prop_handling.cancel_charge()

func move_to(point: Vector3) -> bool:
	if not can_control() or not player.office.FLOOR_BOUNDS.grow(-0.4).has_point(Vector2(point.x, point.z)): return false
	var target := point
	if not is_instance_valid(player.grabbed_furniture):
		var nav_map := player.nav_agent.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(nav_map) == 0: return false
		target = NavigationServer3D.map_get_closest_point(nav_map, point)
		if Vector2(target.x - point.x, target.z - point.z).length() > 0.6: return false
		player.nav_agent.target_position = target
	destination = Vector3(target.x, 0, target.z)
	moving = true
	retarget_time = RETARGET_INTERVAL
	stuck_time = 0.0
	last_position = player.global_position
	marker.global_position = destination + Vector3.UP * 0.035
	marker.visible = true
	return true

func stop_walking() -> void:
	dragging = false
	_finish_destination()

func _finish_destination() -> void:
	moving = false
	stuck_time = 0.0
	if is_instance_valid(marker): marker.visible = false

func cancel() -> void:
	stop_walking()
	aiming = false
	if is_instance_valid(reticle): reticle.visible = false
	if is_instance_valid(player) and is_instance_valid(player.prop_handling) and player.prop_handling.charge_source == "mouse":
		player.prop_handling.cancel_charge()

func tick(delta: float) -> void:
	if not can_control():
		cancel()
		return
	retarget_time = maxf(0, retarget_time - delta)
	var over_ui := pointer_over_ui()
	if dragging and over_ui:
		stop_walking()
	if dragging and retarget_time <= 0:
		var point = floor_point(pointer)
		if point != null and Vector2(point.x - destination.x, point.z - destination.z).length() > 0.25:
			move_to(point)
	if aiming and not over_ui:
		var point = aim_point_at(pointer)
		if point != null:
			aim_point = point
			player.prop_handling.set_aim_point(point)
			reticle.global_position = point + Vector3.UP * 0.045
			reticle.visible = true
	else:
		reticle.visible = false
	if moving:
		stuck_time = stuck_time + delta if player.global_position.distance_to(last_position) < 0.003 and not player.prop_handling.is_locked() else 0.0
		last_position = player.global_position
		if stuck_time > 1.0: stop_walking()

func movement_direction() -> Vector3:
	if not moving: return Vector3.ZERO
	var remaining := destination - player.global_position
	remaining.y = 0
	if remaining.length() <= ARRIVAL_DISTANCE:
		_finish_destination()
		return Vector3.ZERO
	if is_instance_valid(player.grabbed_furniture): return remaining.normalized()
	var next := player.nav_agent.get_next_path_position() - player.global_position
	next.y = 0.0
	if player.nav_agent.is_navigation_finished():
		_finish_destination()
		return Vector3.ZERO
	return next.normalized()

func face_pointer(delta: float) -> bool:
	if not aiming or not can_control() or player.prop_handling.is_locked() or is_instance_valid(player.grabbed_furniture): return false
	var offset := aim_point - player.global_position
	if is_instance_valid(player.held_prop) and player.prop_handling.charging:
		offset = player.prop_handling.aim_direction
	offset.y = 0
	if offset.length_squared() < 0.04: return true
	var old_yaw := player.rotation.y
	player.rotation.y = lerp_angle(old_yaw, atan2(offset.x, offset.z), clampf(delta * 16, 0, 1))
	if not player.prop_handling.follow_held(): player.rotation.y = old_yaw
	return true
