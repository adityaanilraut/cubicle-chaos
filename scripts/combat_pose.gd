class_name CombatPose
extends SkeletonModifier3D

# Layer procedural guard/strike poses over the original idle and walk cycles.
var combat: OfficeCombat
var _guard_weight := 0.0
var _kung_fu_weight := 0.0
var _last_pose: Array[Transform3D] = []
var _fall_start_pose: Array[Transform3D] = []
var _guard_clock := 0.0
var _guard_resume_delay := 0.0
var _step_distance := 0.0

# Hips, body pitch/roll/curl, left/right ankles, left/right wrists. Points are
# actor-local meters, so the feet and supporting hands can stay on the floor.
const FALL_KEYS := [
	[0.00, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(0.10, 0.105, 0), Vector3(-0.10, 0.105, 0), Vector3(0.24, 1.28, 0.25), Vector3(-0.24, 1.28, 0.25)],
	[0.12, Vector3(0, 0.84, -0.08), Vector3(-0.22, 0, 0.16), Vector3(0.14, 0.105, 0.04), Vector3(-0.14, 0.105, 0), Vector3(0.30, 1.24, 0.30), Vector3(-0.30, 1.20, 0.28)],
	[0.34, Vector3(0, 0.43, -0.30), Vector3(-0.92, 0.06, 0.25), Vector3(0.18, 0.12, 0.34), Vector3(-0.18, 0.105, 0.29), Vector3(0.42, 0.55, -0.20), Vector3(-0.40, 0.50, -0.25)],
	[0.54, Vector3(0, 0.19, -0.42), Vector3(-1.53, 0.04, 0.04), Vector3(0.20, 0.105, 0.22), Vector3(-0.20, 0.105, 0.17), Vector3(0.40, 0.105, -0.68), Vector3(-0.40, 0.105, -0.66)],
	[0.68, Vector3(0, 0.20, -0.42), Vector3(-1.50, 0.04, 0.06), Vector3(0.20, 0.105, 0.22), Vector3(-0.20, 0.105, 0.17), Vector3(0.40, 0.105, -0.68), Vector3(-0.40, 0.105, -0.66)],
]
const GET_UP_KEYS := [
	[0.00, Vector3(0, 0.20, -0.42), Vector3(-1.50, 0.04, 0.06), Vector3(0.20, 0.105, 0.22), Vector3(-0.20, 0.105, 0.17), Vector3(0.40, 0.105, -0.68), Vector3(-0.40, 0.105, -0.66)],
	[0.32, Vector3(0.04, 0.25, -0.35), Vector3(-1.15, 0.35, 0.28), Vector3(0.20, 0.105, 0.27), Vector3(-0.18, 0.105, 0.22), Vector3(0.40, 0.105, -0.38), Vector3(-0.28, 0.12, -0.55)],
	[0.66, Vector3(0, 0.27, -0.25), Vector3(-0.85, 0.05, 0.10), Vector3(0.20, 0.105, 0.38), Vector3(-0.20, 0.105, 0.32), Vector3(0.34, 0.105, -0.40), Vector3(-0.34, 0.105, -0.40)],
	[1.02, Vector3(0, 0.56, -0.10), Vector3(0.24, 0, 0.12), Vector3(0.19, 0.105, 0.30), Vector3(-0.19, 0.105, -0.38), Vector3(0.28, 0.70, 0.32), Vector3(-0.15, 0.50, 0.28)],
	[1.38, Vector3(0, 0.70, -0.02), Vector3(0.12, 0, 0.10), Vector3(0.16, 0.105, 0.08), Vector3(-0.16, 0.105, -0.08), Vector3(0.26, 0.97, 0.28), Vector3(-0.26, 0.94, 0.25)],
	[1.80, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(0.10, 0.105, 0), Vector3(-0.10, 0.105, 0), Vector3(0.24, 1.25, 0.20), Vector3(-0.24, 1.25, 0.20)],
]

func begin_fall() -> void:
	# Save the last visible pose, including an interrupted punch or kick.
	_fall_start_pose = _last_pose.duplicate()
	_guard_resume_delay = 0.0

func finish_recovery() -> void:
	# Complete the planted rise before lifting the hands into a fresh guard.
	# This also keeps an immediate counterattack from snapping out of the kneel.
	_guard_weight = 0.0
	_guard_resume_delay = 0.06

func _process_modification() -> void:
	if combat == null or not is_instance_valid(combat.actor):
		return
	var actor := combat.actor
	var skeleton := get_skeleton()
	_guard_clock += get_process_delta_time()
	if combat.is_down():
		_guard_weight = 0.0
		_apply_knockdown(skeleton)
		_last_pose = _read_pose(skeleton)
		return
	if _guard_resume_delay > 0.0:
		_guard_resume_delay -= get_process_delta_time()
		_last_pose = _read_pose(skeleton)
		return
	_guard_weight = move_toward(_guard_weight, 1.0 if combat.has_fighting_pose() else 0.0, get_process_delta_time() * (14.0 if combat.is_busy() else 7.0))
	if _guard_weight <= 0.0:
		_last_pose = _read_pose(skeleton)
		return
	var source := _read_pose(skeleton)
	_apply_fighting_pose(skeleton)
	_blend_pose(skeleton, source, 1.0 - _guard_weight)
	_last_pose = _read_pose(skeleton)
	combat.trail.sample_tip(skeleton)

func _apply_fighting_pose(skeleton: Skeleton3D) -> void:
	var actor := combat.actor
	var move := combat.current_move()
	var attacking := combat.phase == OfficeCombat.Phase.ATTACK
	var time := combat.phase_time
	var contact := float(move.contact)
	var duration := float(move.duration)
	var extension := smoothstep(contact * 0.40, contact, time) * (1.0 - smoothstep(contact + 0.05, duration, time)) if attacking else 0.0
	var chamber := sin(clampf(time / contact, 0, 1) * PI) if attacking else 0.0
	var stagger := sin(clampf(time / 0.38, 0, 1) * PI) if combat.phase == OfficeCombat.Phase.STAGGER else 0.0
	var body_hit := combat.hit_height < 1.15
	var recoil := sin(clampf((time - contact) / maxf(duration - contact, 0.01), 0, 1) * PI) if attacking else 0.0
	var breath := sin(_guard_clock * 3.0) * 0.012 if not attacking else 0.0
	var kung_fu := combat.stance_style == "Kung fu"
	_kung_fu_weight = move_toward(_kung_fu_weight, 1.0 if kung_fu else 0.0, get_process_delta_time() * 7.0)
	var stationary := actor.velocity.length_squared() < 0.04
	var turn := 0.0
	if attacking:
		match combat.move_id:
			"bat_forehand": turn = 0.9 * extension - 0.35 * chamber
			"bat_backhand": turn = -0.9 * extension + 0.35 * chamber
			"bat_overhead": turn = -0.15 * chamber
			"cross": turn = -0.32 * extension
			"jab", "palm": turn = 0.20 * extension
			"hook": turn = 0.65 * extension - 0.25 * chamber
			"uppercut": turn = -0.40 * extension
			"side_kick": turn = 0.90 * extension
			"roundhouse": turn = -0.75 * extension
			"sweep": turn = 0.70 * extension
			"spinning_kick": turn = TAU * smoothstep(0.02, contact, time)
	_rotate(skeleton, "Hips", Vector3.UP, turn)
	_rotate(skeleton, "Spine", Vector3.RIGHT, (0.30 if body_hit else -0.24) * stagger - (0.16 * extension if move.family == "kick" else 0.0) + (0.15 * chamber if combat.move_id == "uppercut" else 0.0) + breath)
	_rotate(skeleton, "Spine1", Vector3.UP, lerpf(-0.12, 0.12, _kung_fu_weight))
	_rotate(skeleton, "Spine1", Vector3.UP, -turn * 0.25 + combat.hit_side * stagger * 0.18)
	_rotate(skeleton, "Head", Vector3.RIGHT, (-0.18 if not body_hit else 0.12) * stagger)
	_rotate(skeleton, "Head", Vector3.FORWARD, combat.hit_side * stagger * 0.14)
	# Lower the center of gravity into a forward karate stance or a kung fu cat
	# stance. Keep ordinary walking feet untouched so retreat remains readable.
	if stationary:
		var hips := skeleton.find_bone("office_Hips")
		var lowered := lerpf(0.07, 0.10, _kung_fu_weight) + chamber * 0.025 + stagger * 0.045
		if attacking and combat.move_id == "sweep": lowered += 0.23 * extension
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + skeleton.global_basis.inverse() * actor.global_basis * Vector3(0, -lowered, 0.16 * extension if move.family == "punch" else 0.0))
		for side in ["Left", "Right"]:
			var left: bool = side == "Left"
			var foot := Vector3(0.23 if left else -0.23, 0.105, 0.26 if left else -0.20)
			foot = foot.lerp(Vector3(0.18 if left else -0.23, 0.16 if left else 0.105, 0.30 if left else -0.14), _kung_fu_weight)
			_solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", _to_skeleton(skeleton, foot), Vector3(0.12 if left else -0.12, 0.2, 1))
			var bone := skeleton.find_bone("office_" + side + "Foot")
			_set_global_basis(skeleton, bone, Basis(Vector3.UP, turn) * skeleton.get_bone_global_rest(bone).basis)
	elif combat.is_player and is_instance_valid(combat.target):
		_apply_combat_steps(skeleton)
	for side in ["Left", "Right"]:
		var sign_x := 1.0 if side == "Left" else -1.0
		var guard := Vector3(sign_x * 0.23, 1.40 if side == "Left" else 1.30, 0.20 if side == "Left" else 0.16)
		guard = guard.lerp(Vector3(sign_x * 0.30, 1.25 if side == "Left" else 1.46, 0.35 if side == "Left" else 0.18), _kung_fu_weight)
		guard.y += breath
		# The spare hand protects the jaw; hits fold the guard toward the actual
		# impact height instead of using the same full-body flinch for every hit.
		if attacking and side != move.side: guard += Vector3(-sign_x * 0.035, 0.07, -0.03) * extension
		if stagger > 0.0:
			guard = guard.lerp(Vector3(sign_x * 0.18, 1.02 if body_hit else 1.48, 0.30), stagger * 0.8)
		if attacking and move.family == "punch" and side == move.side:
			guard = _hand_strike(combat.move_id, guard, time, contact, duration)
			guard.z -= 0.045 * recoil
		_solve_limb(skeleton, side + "Arm", side + "ForeArm", side + "Hand", _to_skeleton(skeleton, guard), Vector3(sign_x, -0.6, -0.2))
		# Open palms in kung fu guards and palm strikes; closed fists in karate.
		var open_hand: bool = kung_fu and (not attacking or move.family == "kick" or combat.move_id == "palm")
		for finger in ["Index", "Middle", "Ring", "Pinky"]:
			for joint in range(1, 4):
				_rotate(skeleton, side + "Hand" + finger + str(joint), Vector3.RIGHT, 0.12 if open_hand else 1.15)
	if attacking and move.family == "kick":
		var side: String = move.side
		var foot := _foot_strike(combat.move_id, side, time, contact, duration)
		_solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", _to_skeleton(skeleton, foot), Vector3(0.4 if side == "Left" else -0.4, 0.6, 1))
		var bone := skeleton.find_bone("office_" + side + "Foot")
		var sole := skeleton.get_bone_global_rest(bone).basis
		if combat.move_id in ["side_kick", "roundhouse", "spinning_kick"]:
			sole = Basis(Vector3.FORWARD, extension * PI * 0.45) * sole
		_set_global_basis(skeleton, bone, sole)

func _apply_combat_steps(skeleton: Skeleton3D) -> void:
	# Plant and lift feet along travel while the torso keeps facing the locked
	# opponent. This supports circling and backpedalling without a forward walk
	# playing sideways underneath the guard.
	var actor := combat.actor
	var speed := actor.velocity.length()
	_step_distance += speed * get_process_delta_time()
	var travel := actor.global_basis.inverse() * actor.velocity.normalized()
	var hips := skeleton.find_bone("office_Hips")
	var root := _to_skeleton(skeleton, Vector3(0, 0.94, 0))
	skeleton.set_bone_pose_position(hips, root)
	for side in ["Left", "Right"]:
		var left: bool = side == "Left"
		var cycle := fposmod(_step_distance / 1.05 + (0.0 if left else 0.5), 1.0)
		var planted := cycle < 0.58
		var t := cycle / 0.58 if planted else (cycle - 0.58) / 0.42
		var stride := lerpf(0.29, -0.29, t) if planted else lerpf(-0.29, 0.29, smoothstep(0, 1, t))
		var foot := Vector3(0.20 if left else -0.20, 0.105, 0.08 if left else -0.08) + travel * stride
		foot.x = maxf(0.09, foot.x) if left else minf(-0.09, foot.x)
		if not planted: foot.y += sin(t * PI) * 0.11
		_solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", _to_skeleton(skeleton, foot), Vector3(0.18 if left else -0.18, 0.2, 1))
		var bone := skeleton.find_bone("office_" + side + "Foot")
		_set_global_basis(skeleton, bone, skeleton.get_bone_global_rest(bone).basis)

func _hand_strike(id: String, guard: Vector3, time: float, contact: float, duration: float) -> Vector3:
	var chamber := guard
	var strike := Vector3(0.08, 1.36, 1.02)
	match id:
		"jab": chamber = Vector3(0.25, 1.40, 0.27)
		"cross":
			chamber = Vector3(-0.26, 1.24, 0.12)
			strike = Vector3(-0.10, 1.35, 1.05)
		"hook":
			chamber = Vector3(0.60, 1.34, 0.38)
			strike = Vector3(-0.08, 1.36, 0.84)
		"uppercut":
			chamber = Vector3(-0.28, 0.91, 0.32)
			strike = Vector3(-0.06, 1.58, 0.70)
		"palm":
			chamber = Vector3(0.30, 1.08, 0.12)
			strike = Vector3(0.06, 1.22, 1.06)
	var key := _sample_keys([[0.0, guard], [contact * 0.40, chamber], [contact, strike], [contact + 0.05, strike], [duration, guard]], time)
	return key[1]

func _foot_strike(id: String, side: String, time: float, contact: float, duration: float) -> Vector3:
	var x := 0.23 if side == "Left" else -0.23
	var rest := Vector3(x, 0.105, 0.26 if side == "Left" else -0.20)
	var chamber := Vector3(x, 0.60, 0.30)
	var strike := Vector3(x, 1.0, 1.40)
	match id:
		"side_kick":
			chamber = Vector3(0.40, 0.65, 0.18)
			strike = Vector3(0.12, 1.05, 1.42)
		"roundhouse":
			chamber = Vector3(-0.65, 0.80, 0.18)
			strike = Vector3(0.16, 1.30, 1.26)
		"sweep":
			chamber = Vector3(0.72, 0.24, 0.20)
			strike = Vector3(-0.20, 0.28, 1.22)
		"spinning_kick":
			chamber = Vector3(-0.75, 0.58, -0.05)
			strike = Vector3(0.0, 1.20, 1.40)
	var key := _sample_keys([[0.0, rest], [contact * 0.48, chamber], [contact, strike], [contact + 0.06, strike], [duration * 0.86, chamber], [duration, rest]], time)
	return key[1]

func _read_pose(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in range(skeleton.get_bone_count()):
		result.append(skeleton.get_bone_pose(bone))
	return result

func _sample_keys(keys: Array, time: float) -> Array:
	for i in range(1, keys.size()):
		if time <= keys[i][0]:
			var weight := smoothstep(keys[i - 1][0], keys[i][0], time)
			var result: Array = [time]
			for value in range(1, keys[i].size()):
				result.append((keys[i - 1][value] as Vector3).lerp(keys[i][value], weight))
			return result
	return keys.back()

func _apply_knockdown(skeleton: Skeleton3D) -> void:
	var recovering := combat.phase == OfficeCombat.Phase.GETTING_UP
	var time := combat.phase_time
	var animation_pose := _read_pose(skeleton)
	var key := _sample_keys(GET_UP_KEYS if recovering else FALL_KEYS, time)
	# Use a stable skeleton while down; a looping idle must not move the body
	# through the floor or continue walking while the character is lying still.
	for bone in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(bone)
		skeleton.set_bone_pose_position(bone, rest.origin)
		skeleton.set_bone_pose_rotation(bone, rest.basis.get_rotation_quaternion())
	var hips := skeleton.find_bone("office_Hips")
	var angles: Vector3 = key[2]
	skeleton.set_bone_pose_position(hips, _to_skeleton(skeleton, key[1]))
	skeleton.set_bone_pose_rotation(hips, Quaternion.from_euler(Vector3(angles.x, 0, angles.y)))
	_rotate(skeleton, "Spine", Vector3.RIGHT, angles.z * 0.6)
	_rotate(skeleton, "Spine1", Vector3.RIGHT, angles.z * 0.4)
	_rotate(skeleton, "Head", Vector3.RIGHT, angles.z * 0.3)
	for side_index in range(2):
		var side := "Left" if side_index == 0 else "Right"
		var sign_x := 1.0 if side_index == 0 else -1.0
		var knee_pole := Vector3(sign_x * 0.10, 1.0, 0.35)
		if recovering:
			var forward_knee := Vector3(sign_x * 0.30, 0, 1)
			knee_pole = knee_pole.lerp(forward_knee, smoothstep(0.25, 0.66, time))
			var kneel := smoothstep(0.66, 1.02, time) * (1.0 - smoothstep(1.02, 1.38, time))
			knee_pole = knee_pole.lerp(Vector3(-0.05, -1.0, 0.15) if side == "Right" else forward_knee, kneel)
		_solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", _to_skeleton(skeleton, key[3 + side_index]), knee_pole)
		# Preserve sole orientation rather than inheriting a twisted knee pose.
		var foot := skeleton.find_bone("office_" + side + "Foot")
		_set_global_basis(skeleton, foot, skeleton.get_bone_global_rest(foot).basis)
		var hand_target: Vector3 = key[5 + side_index]
		_solve_limb(skeleton, side + "Arm", side + "ForeArm", side + "Hand", _to_skeleton(skeleton, hand_target), Vector3(sign_x, -0.3, -0.2))
		var hand_plant := 1.0 - smoothstep(0.14, 0.38, hand_target.y)
		if hand_plant > 0.0:
			var hand := skeleton.find_bone("office_" + side + "Hand")
			var basis := skeleton.get_bone_global_pose(hand).basis.orthonormalized()
			var planted_basis := Basis(Quaternion(basis.y, Vector3.BACK)) * basis
			_set_global_basis(skeleton, hand, Basis(basis.get_rotation_quaternion().slerp(planted_basis.get_rotation_quaternion(), hand_plant)))
	if not recovering:
		var source := _fall_start_pose if _fall_start_pose.size() == animation_pose.size() else animation_pose
		_blend_pose(skeleton, source, 1.0 - smoothstep(0.0, 0.24, time))
	else:
		# Match the live idle pose before returning movement control; no root snap.
		_blend_pose(skeleton, animation_pose, smoothstep(1.48, OfficeCombat.GET_UP_TIME, time))

func _to_skeleton(skeleton: Skeleton3D, point: Vector3) -> Vector3:
	return skeleton.to_local(combat.actor.to_global(point))

func _set_global_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).orthonormalized().get_rotation_quaternion())

func _blend_pose(skeleton: Skeleton3D, source: Array[Transform3D], weight: float) -> void:
	for bone in range(source.size()):
		var current := skeleton.get_bone_pose(bone)
		skeleton.set_bone_pose_position(bone, current.origin.lerp(source[bone].origin, weight))
		skeleton.set_bone_pose_rotation(bone, current.basis.get_rotation_quaternion().slerp(source[bone].basis.get_rotation_quaternion(), weight))

func _rotate(skeleton: Skeleton3D, bone_name: String, axis: Vector3, angle: float) -> void:
	var bone := skeleton.find_bone("office_" + bone_name)
	if bone >= 0:
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(axis, angle))

func _solve_limb(skeleton: Skeleton3D, upper_name: String, lower_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var upper := skeleton.find_bone("office_" + upper_name)
	var lower := skeleton.find_bone("office_" + lower_name)
	var end := skeleton.find_bone("office_" + end_name)
	if upper < 0 or lower < 0 or end < 0:
		return
	var origin := skeleton.get_bone_global_pose(upper).origin
	var joint := skeleton.get_bone_global_pose(lower).origin
	var tip := skeleton.get_bone_global_pose(end).origin
	var a := origin.distance_to(joint)
	var b := joint.distance_to(tip)
	var direction := (target - origin).normalized()
	var distance := clampf(origin.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	var bend := (pole - direction * pole.dot(direction)).normalized()
	if bend.length_squared() < 0.001:
		bend = direction.cross(Vector3.RIGHT).normalized()
	var along := clampf((a * a + distance * distance - b * b) / (2.0 * distance), -a, a)
	var joint_target := origin + direction * along + bend * sqrt(maxf(0, a * a - along * along))
	_aim(skeleton, upper, lower, joint_target)
	_aim(skeleton, lower, end, origin + direction * distance)

func _aim(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := skeleton.get_bone_global_pose(child).origin - pose.origin
	var desired := target - pose.origin
	if current.length_squared() < 0.000001 or desired.length_squared() < 0.000001:
		return
	var turn := Quaternion(current.normalized(), desired.normalized())
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * Basis(turn) * pose.basis).orthonormalized().get_rotation_quaternion())
