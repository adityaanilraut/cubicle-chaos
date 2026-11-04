class_name PropHandling
extends Node3D

# One owner for carry/charge/gesture state. The player's public held_prop remains
# the source of truth for equipment, combat, and existing interaction callers.
const CHARGE_TIME := 1.0
const TAP_TIME := 0.16
# Anyone in the forward half-plane is eligible; the nearest person wins.
const MIN_AIM_DOT := 0.0
var player: OfficePlayer
var charging := false
var charge_time := 0.0
var charge_source := ""
var gesture := ""
var gesture_time := 0.0
var gesture_duration := 0.0
var aim_direction := Vector3.FORWARD
var manual_aim_direction := Vector3.FORWARD
var locked_person: OfficeWorker
var target_ring: MeshInstance3D
var mouse_seen := false
var pickup_origin := Vector3.ZERO
var pickup_pose := Transform3D.IDENTITY
var preview: MeshInstance3D
var landing: MeshInstance3D
var charge_label: Label3D

func setup(owner_player: OfficePlayer) -> void:
	player = owner_player
	top_level = true
	preview = MeshInstance3D.new()
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.material_override = AssetCatalog.get_shared_material("throw_arc", Color(1.0, 0.76, 0.18), 0.5, true)
	add_child(preview)
	landing = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.21
	landing.mesh = ring
	landing.material_override = preview.material_override
	add_child(landing)
	target_ring = MeshInstance3D.new()
	target_ring.name = "ThrowTarget"
	var target_mesh := TorusMesh.new()
	target_mesh.inner_radius = 0.45
	target_mesh.outer_radius = 0.49
	target_ring.mesh = target_mesh
	target_ring.material_override = AssetCatalog.get_shared_material("throw_target", Color(1.0, 0.67, 0.10), 0.5, true)
	target_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(target_ring)
	charge_label = Label3D.new()
	charge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	charge_label.font_size = 42
	charge_label.pixel_size = 0.005
	charge_label.outline_size = 8
	add_child(charge_label)
	_hide_preview()

func is_locked() -> bool:
	return gesture in ["pickup", "release", "place"]

func charge_fraction() -> float:
	return clampf((charge_time - TAP_TIME) / CHARGE_TIME, 0.0, 1.0)

func set_aim_point(point: Vector3) -> void:
	var direction := point - player.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.04:
		manual_aim_direction = direction.normalized()
		aim_direction = manual_aim_direction

func update_mouse_aim() -> void:
	if not mouse_seen and not charging:
		manual_aim_direction = player.global_basis.z.normalized()
	if mouse_seen:
		var mouse := player.mouse_controls.pointer if charge_source == "mouse" and is_instance_valid(player.mouse_controls) else get_viewport().get_mouse_position()
		var point = player.mouse_controls.aim_point_at(mouse)
		if point != null: set_aim_point(point)
	_select_person()

func _select_person() -> void:
	locked_person = null
	var closest := INF
	for node in get_tree().get_nodes_in_group("workers"):
		if not node is OfficeWorker or node == player or node.is_queued_for_deletion():
			continue
		var person := node as OfficeWorker
		if not person.is_visible_in_tree():
			continue
		var offset := person.global_position - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.05 or distance >= closest or offset.dot(manual_aim_direction) <= MIN_AIM_DOT:
			continue

		locked_person = person
		closest = distance
	aim_direction = manual_aim_direction
	if is_instance_valid(locked_person):
		var direction := locked_person.global_position - player.global_position
		direction.y = 0.0
		aim_direction = direction.normalized()

func _launch_velocity(prop: PhysicsProp, origin: Vector3, strength: float) -> Vector3:
	var velocity := prop.launch_velocity(aim_direction, strength)
	if not is_instance_valid(locked_person):
		return velocity
	# Keep the prop's mass- and charge-dependent horizontal speed, and aim the
	# arc at the person's torso. Clamp lift so distant targets cannot grant an
	# unlimited throw; the trajectory preview uses this exact same velocity.
	var center := origin + Vector3.UP * prop.footprint_size.y * 0.5
	var target := locked_person.global_position + Vector3.UP * (0.75 if locked_person.is_seated else 0.95)
	var horizontal_distance := Vector2(target.x - center.x, target.z - center.z).length()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var horizontal := Vector3(target.x - center.x, 0.0, target.z - center.z)
	if horizontal.length_squared() > 0.0001:
		horizontal = horizontal.normalized() * horizontal_speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	var flight_time := horizontal_distance / maxf(horizontal_speed, 0.1)
	if flight_time > 0.02:
		var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		var required_lift := (target.y - center.y + 0.5 * gravity * flight_time * flight_time) / flight_time
		velocity.y = clampf(required_lift, -horizontal_speed, maxf(4.0, velocity.y))
	return velocity

func begin_charge(source := "keyboard") -> bool:
	if charging or not can_act() or not is_instance_valid(player.held_prop) or is_locked(): return false
	charging = true
	charge_source = source
	charge_time = 0.0
	manual_aim_direction = player.global_basis.z.normalized()
	update_mouse_aim()
	return true

func cancel_charge() -> void:
	charging = false
	charge_source = ""
	charge_time = 0.0
	locked_person = null
	_hide_preview()

func can_act() -> bool:
	return player.gameplay_visible and not player.combat.is_busy() and player.busy <= 0.0 and not player.seated and not player.dialogue.is_open and not player.equipment.is_active() and player.office.edit_mode == player.office.EditMode.SELECT

func can_pick_up(prop: PhysicsProp) -> bool:
	if not is_instance_valid(prop) or prop.is_queued_for_deletion() or prop.is_held(): return false
	var center := prop.global_position + prop.global_basis * Vector3.UP * prop.footprint_size.y * 0.5
	if center.distance_to(player.global_position + Vector3.UP * 0.7) > 1.7: return false
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.25, center, 1 | 4 | 8, [player.get_rid(), prop.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func pick_up(prop: PhysicsProp) -> bool:
	if not can_act() or is_instance_valid(player.held_prop) or is_instance_valid(player.carried_cup) or is_instance_valid(player.grabbed_furniture) or not can_pick_up(prop): return false
	# Validate the entire lift before reserving the object. A desk above a prop
	# cannot be bypassed by snapping it directly to the hands.
	var old_yaw := player.global_rotation.y
	var toward := prop.global_position - player.global_position
	if Vector2(toward.x, toward.z).length() > 0.05: player.rotation.y = atan2(toward.x, toward.z)
	var yaw := player.global_rotation.y
	var target := grip_position(prop)
	var lift_pose := BaseballBat.held_pose(player) if prop.prop_id == "baseball_bat" else Transform3D(Basis(Vector3.UP, yaw), target)
	if not prop.can_transform_to(lift_pose, [player.get_rid()]):
		player.rotation.y = old_yaw
		return false
	player.held_prop = prop
	pickup_origin = prop.global_position
	pickup_pose = prop.global_transform
	prop.pick_up(player)
	start_gesture("pickup", 0.32)
	OfficeAudio.play_at(get_tree(), "pickup")
	return true

func start_gesture(value: String, duration: float) -> void:
	gesture = value
	gesture_time = 0.0
	gesture_duration = duration

func grip_position(prop: PhysicsProp) -> Vector3:
	if prop.prop_id == "baseball_bat": return BaseballBat.held_pose(player).origin
	var windup := charge_fraction() if charging else 0.0
	var distance := 0.42 + minf(prop.footprint_size.z * 0.35, 0.18) - windup * 0.15
	return player.global_position + player.global_basis.z * distance + Vector3.UP * (1.02 - minf(prop.footprint_size.y * 0.3, 0.22) + windup * 0.20)

func follow_held() -> bool:
	var prop := player.held_prop
	if not is_instance_valid(prop): return true
	if prop.prop_id == "baseball_bat":
		if player.combat.phase == OfficeCombat.Phase.ATTACK and player.combat.kind == "bat": return true
		var pose := BaseballBat.held_pose(player)
		if gesture == "pickup":
			var t := smoothstep(0.0, 1.0, minf(gesture_time / gesture_duration, 1.0))
			pose = pickup_pose.interpolate_with(pose, t)
		# Combat knockback or loading can leave the held pose inside geometry.
		# Let the player move out; resume normal collision checks once clear.
		if not prop.fits_transform(prop.global_transform, [player.get_rid()]):
			prop.global_transform = pose
			return true
		if not prop.can_transform_to(pose, [player.get_rid()]): return false
		prop.global_transform = pose
		return true
	var target := grip_position(prop)
	if gesture == "pickup":
		var t := smoothstep(0.0, 1.0, minf(gesture_time / gesture_duration, 1.0))
		target = pickup_origin.lerp(target, t)
	if not prop.can_move_to(target, player.global_rotation.y, [player.get_rid()]): return false
	prop.global_rotation = Vector3(0, player.global_rotation.y, 0)
	prop.global_position = target
	return true

func tick(delta: float) -> void:
	if not gesture.is_empty():
		gesture_time += delta
		if gesture_time >= gesture_duration: gesture = ""
	if not is_instance_valid(player.held_prop):
		player.held_prop = null
		cancel_charge()
		return
	if not can_act():
		cancel_charge()
		return
	if charging:
		charge_time += delta
		update_mouse_aim()
		var old_yaw := player.rotation.y
		player.rotation.y = atan2(aim_direction.x, aim_direction.z)
		if not follow_held(): player.rotation.y = old_yaw
		_update_preview()
	else:
		follow_held()

func release_throw(power: float = -1.0) -> bool:
	if not can_act() or not is_instance_valid(player.held_prop) or is_locked():
		cancel_charge()
		return false
	update_mouse_aim()
	var strength := charge_fraction() if power < 0.0 else clampf(power, 0.0, 1.0)
	var prop := player.held_prop
	var origin := prop.global_position
	# A throw starts at the last collision-checked held pose, never beyond a wall.
	if not prop.fits_transform(prop.global_transform, [player.get_rid()]):
		cancel_charge()
		return false
	var launch := _launch_velocity(prop, origin, strength)
	player.held_prop = null
	cancel_charge()
	prop.throw_from(origin, aim_direction, strength, player, launch)
	start_gesture("release", 0.30)
	OfficeAudio.play_at(get_tree(), "throw")
	player.show_social_speech("🎯 Throw!")
	return true

func find_placement() -> Dictionary:
	var prop := player.held_prop
	if not is_instance_valid(prop): return {}
	var best := 1.5
	var result := {}
	for item in get_tree().get_nodes_in_group("furniture"):
		if not item.can_hold_cup() or item.is_in_use(): continue
		for surface in item._cup_surfaces:
			var half := prop.footprint_size * 0.5 + Vector3(0.025, 0, 0.025)
			var low: Vector3 = surface.position + half
			var high: Vector3 = surface.end - half
			if low.x > high.x or low.z > high.z: continue
			var local: Vector3 = item.to_local(player.global_position)
			var point := Vector3(clampf(local.x, low.x, high.x), surface.end.y + 0.025, clampf(local.z, low.z, high.z))
			if item.cup_round and Vector2(point.x - surface.get_center().x, point.z - surface.get_center().z).length() + Vector2(half.x, half.z).length() > minf(surface.size.x, surface.size.z) * 0.5: continue
			var box := AABB(point - Vector3(half.x, 0, half.z), prop.footprint_size)
			var blocked := false
			for obstacle in item._cup_obstacles:
				if box.intersects(obstacle): blocked = true
			if blocked: continue
			var world: Vector3 = item.to_global(point)
			var distance := Vector2(world.x - player.global_position.x, world.z - player.global_position.z).length()
			if distance >= best or world.y > 1.45: continue
			# Tables have coarse collision boxes (some include their chairs). Only
			# the selected support is excluded; its visual clutter was checked above.
			if not prop.can_move_to(world, item.global_rotation.y, [player.get_rid(), item.get_rid()]): continue
			best = distance
			result = {"position": world, "yaw": item.global_rotation.y, "support": item}
	if not result.is_empty(): return result
	# Try reachable floor positions around the player, closest to facing first.
	for angle in [0.0, -0.65, 0.65, -1.3, 1.3, PI]:
		var direction := player.global_basis.z.rotated(Vector3.UP, angle)
		var distance := 0.48 + maxf(prop.footprint_size.x, prop.footprint_size.z) * 0.55
		var point := player.global_position + direction * distance
		point.y = 0.035
		if not player.office.FLOOR_BOUNDS.grow(-0.4).has_point(Vector2(point.x, point.z)): continue
		if prop.can_move_to(point, player.global_rotation.y, [player.get_rid()]):
			return {"position": point, "yaw": player.global_rotation.y}
	return {}

func place_gently(interrupted := false) -> bool:
	if not is_instance_valid(player.held_prop): return false
	if not interrupted and (not can_act() or is_locked()): return false
	var prop := player.held_prop
	var placement := find_placement()
	# If all floor/surface positions are blocked, release at the safe held pose.
	# Normal placement stays in hand; combat interruption must free both hands.
	if placement.is_empty() and not interrupted: return false
	player.held_prop = null
	cancel_charge()
	if not placement.is_empty(): prop.global_rotation = Vector3(0, placement.yaw, 0)
	prop.drop_gently(placement.get("position", prop.global_position), player)
	if not interrupted: start_gesture("place", 0.28)
	return true

func reset() -> void:
	cancel_charge()
	gesture = ""

func _hide_preview() -> void:
	if is_instance_valid(preview): preview.visible = false
	if is_instance_valid(landing): landing.visible = false
	if is_instance_valid(target_ring): target_ring.visible = false
	if is_instance_valid(charge_label): charge_label.visible = false

func _seated_target_hit(from: Vector3, to: Vector3) -> Variant:
	if not is_instance_valid(locked_person) or not locked_person.is_seated or not locked_person.collision_shape.disabled:
		return null
	# Match the seated worker's non-blocking thrown-prop sensor in the preview.
	var center := locked_person.global_position + Vector3.UP * 0.85
	var segment := to - from
	var a := segment.length_squared()
	if a < 0.000001: return null
	var offset := from - center
	var c := offset.length_squared() - 0.34 * 0.34
	if c <= 0.0: return from
	var b := offset.dot(segment)
	var discriminant := b * b - a * c
	if discriminant < 0.0: return null
	var t := (-b - sqrt(discriminant)) / a
	if t < 0.0 or t > 1.0: return null
	return from + segment * t

func _update_preview() -> void:
	if not is_instance_valid(player.held_prop): return
	var prop := player.held_prop
	var origin := prop.global_position + Vector3.UP * prop.footprint_size.y * 0.5
	var launch := _launch_velocity(prop, prop.global_position, charge_fraction())
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous := origin
	var endpoint := origin
	for i in range(1, 49):
		var t := float(i) * 0.045
		var point := origin + launch * t + Vector3.DOWN * gravity * t * t * 0.5
		var ray := PhysicsRayQueryParameters3D.create(previous, point, 1 | 4 | 8, [player.get_rid(), prop.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		var seated_hit: Variant = _seated_target_hit(previous, point)
		if seated_hit != null and (hit.is_empty() or previous.distance_squared_to(seated_hit) < previous.distance_squared_to(hit.position)):
			point = seated_hit
			hit = {"position": seated_hit}
		elif not hit.is_empty():
			point = hit.position
		if point.y < 0.04: point.y = 0.04
		mesh.surface_add_vertex(previous)
		mesh.surface_add_vertex(point)
		endpoint = point
		if not hit.is_empty() or point.y <= 0.04: break
		previous = point
	mesh.surface_end()
	preview.mesh = mesh
	preview.visible = charge_time >= TAP_TIME
	landing.position = endpoint + Vector3.UP * 0.02
	landing.visible = preview.visible
	charge_label.position = player.global_position + Vector3.UP * 2.35
	target_ring.visible = preview.visible and is_instance_valid(locked_person)
	if target_ring.visible:
		target_ring.global_position = locked_person.global_position + Vector3.UP * 0.045
	var target_text := " • locked: " + locked_person.worker_name if is_instance_valid(locked_person) else ""
	charge_label.text = "%d%%%s • release %s to throw" % [roundi(charge_fraction() * 100), target_text, "right mouse" if charge_source == "mouse" else OfficeInput.key_name("prop")]
	charge_label.visible = preview.visible
