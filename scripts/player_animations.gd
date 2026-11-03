class_name PlayerAnimations
extends RefCounted

# Bake small, shared loops onto our original character skeleton. These
# are ordinary AnimationTree states, so idle/walk/action transitions blend normally.
static func add_animations(library: AnimationLibrary) -> void:
	var skeleton := OfficeCharacter.create_skeleton()
	for kind in ["run", "flee", "shower", "toilet_idle", "wash_hands"]:
		var source: Animation = library.get_animation("stand_to_sit" if kind == "toilet_idle" else "idle")
		var clip := Animation.new()
		clip.length = 0.60 if kind in ["run", "flee"] else 3.2
		clip.loop_mode = Animation.LOOP_LINEAR
		for bone in range(skeleton.get_bone_count()):
			for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
				var track := clip.add_track(type)
				clip.track_set_path(track, NodePath("Skeleton3D:" + skeleton.get_bone_name(bone)))
		for frame in range(33):
			var phase := float(frame) / 32.0 * TAU
			# Start the procedural run from the same fixed pose every frame.
			# Sampling a separate idle loop made the knees/arms wobble mid-stride.
			var source_time := 0.0 if kind in ["run", "flee"] else (source.length - 0.01 if kind == "toilet_idle" else float(frame) / 32.0 * source.length)
			_sample_source(skeleton, source, source_time)
			match kind:
				"run": _run_pose(skeleton, phase)
				"flee":
					_run_pose(skeleton, phase)
					_rotate(skeleton, "Spine", Vector3.RIGHT, 0.14)
					_rotate(skeleton, "Spine1", Vector3.UP, 0.08 * sin(phase))
					_rotate(skeleton, "Head", Vector3.UP, -0.45)
					_rotate(skeleton, "Head", Vector3.RIGHT, -0.08)
				"shower": _shower_pose(skeleton, phase)
				"wash_hands":
					_rotate(skeleton, "Spine", Vector3.RIGHT, 0.14)
					for side in ["Left", "Right"]:
						var sign_x := 1.0 if side == "Left" else -1.0
						_solve_limb(skeleton, side + "Arm", side + "ForeArm", side + "Hand", Vector3(sign_x * (0.04 + 0.025 * sin(phase * 4)), 1.02, 0.43 + sign_x * 0.04 * cos(phase * 4)), Vector3(sign_x, -1, 0))
				"toilet_idle":
					_rotate(skeleton, "Spine", Vector3.RIGHT, 0.10 + sin(phase) * 0.025)
					_rotate(skeleton, "Head", Vector3.RIGHT, 0.10)
			for bone in range(skeleton.get_bone_count()):
				var time := float(frame) / 32.0 * clip.length
				clip.position_track_insert_key(bone * 2, time, skeleton.get_bone_pose_position(bone))
				clip.rotation_track_insert_key(bone * 2 + 1, time, skeleton.get_bone_pose_rotation(bone))
		library.add_animation(kind, clip)
	skeleton.free()

static func _sample_source(skeleton: Skeleton3D, source: Animation, time: float) -> void:
	for bone in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(bone)
		var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(bone))
		var position := source.find_track(path, Animation.TYPE_POSITION_3D)
		var rotation := source.find_track(path, Animation.TYPE_ROTATION_3D)
		skeleton.set_bone_pose_position(bone, source.position_track_interpolate(position, time) if position >= 0 else rest.origin)
		skeleton.set_bone_pose_rotation(bone, source.rotation_track_interpolate(rotation, time) if rotation >= 0 else rest.basis.get_rotation_quaternion())

static func _run_pose(skeleton: Skeleton3D, phase: float) -> void:
	var hips := skeleton.find_bone("office_Hips")
	skeleton.set_bone_pose_position(hips, Vector3(0, 0.94 + 0.025 * cos(phase * 2.0), 0))
	skeleton.set_bone_pose_rotation(hips, Quaternion.from_euler(Vector3(0.10, sin(phase) * 0.05, 0)))
	_rotate(skeleton, "Spine", Vector3.RIGHT, 0.06)
	for side in ["Left", "Right"]:
		var cycle := fposmod(phase / TAU + (0.0 if side == "Left" else 0.5), 1.0)
		var x := 0.12 if side == "Left" else -0.12
		# A short planted phase travels backwards at roughly RUN_SPEED; the
		# longer recovery folds the knee and brings the foot forward in the air.
		var planted := cycle < 0.32
		var t := cycle / 0.32 if planted else (cycle - 0.32) / 0.68
		var foot := Vector3(x, 0.105, lerpf(0.48, -0.48, t) if planted else lerpf(-0.48, 0.48, smoothstep(0, 1, t)))
		if not planted: foot.y += 0.34 * sin(t * PI)
		_solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3(x, 0.3, 1))
		var ankle := skeleton.find_bone("office_" + side + "Foot")
		_set_basis(skeleton, ankle, Basis(Vector3.RIGHT, -0.20 * sin(t * PI) if not planted else 0.0) * skeleton.get_bone_global_rest(ankle).basis)
		# Opposite arm/leg swing with bent elbows below the shoulders. Direct
		# shoulder/elbow angles avoid an IK pole flip as the wrist passes the hip.
		var upper := skeleton.find_bone("office_" + side + "Arm")
		var elbow := skeleton.find_bone("office_" + side + "ForeArm")
		skeleton.set_bone_pose_rotation(upper, Quaternion(Vector3.RIGHT, foot.z / 0.48 * 0.65))
		skeleton.set_bone_pose_rotation(elbow, Quaternion(Vector3.RIGHT, -1.25))
		for finger in ["Index", "Middle", "Ring", "Pinky"]:
			for joint in range(1, 4):
				_rotate(skeleton, side + "Hand" + finger + str(joint), Vector3.RIGHT, 0.7)

static func _shower_pose(skeleton: Skeleton3D, phase: float) -> void:
	_rotate(skeleton, "Spine1", Vector3.UP, sin(phase) * 0.12)
	_rotate(skeleton, "Head", Vector3.RIGHT, -0.12 + sin(phase * 2) * 0.06)
	# One hand scrubs the hair while the other washes the opposite shoulder.
	_solve_limb(skeleton, "LeftArm", "LeftForeArm", "LeftHand", Vector3(0.10 + 0.06 * sin(phase * 2), 1.76, 0.05 + 0.08 * cos(phase * 2)), Vector3(1, 0.5, 0))
	_solve_limb(skeleton, "RightArm", "RightForeArm", "RightHand", Vector3(0.13 + 0.07 * sin(phase * 2), 1.34 + 0.09 * cos(phase * 2), 0.19), Vector3(-1, -0.5, 0.3))

static func _rotate(skeleton: Skeleton3D, name: String, axis: Vector3, angle: float) -> void:
	var bone := skeleton.find_bone("office_" + name)
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(axis, angle))

static func _set_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := _pose(skeleton, parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).orthonormalized().get_rotation_quaternion())

static func _solve_limb(skeleton: Skeleton3D, upper_name: String, lower_name: String, tip_name: String, target: Vector3, pole: Vector3) -> void:
	var upper := skeleton.find_bone("office_" + upper_name)
	var lower := skeleton.find_bone("office_" + lower_name)
	var tip := skeleton.find_bone("office_" + tip_name)
	var origin := _pose(skeleton, upper).origin
	var a := origin.distance_to(_pose(skeleton, lower).origin)
	var b := _pose(skeleton, lower).origin.distance_to(_pose(skeleton, tip).origin)
	var direction := (target - origin).normalized()
	var distance := clampf(origin.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var along := (a * a + distance * distance - b * b) / (2 * distance)
	_aim(skeleton, upper, lower, origin + direction * along + bend * sqrt(maxf(0, a * a - along * along)))
	_aim(skeleton, lower, tip, origin + direction * distance)

static func _aim(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := _pose(skeleton, bone)
	var current := _pose(skeleton, child).origin - pose.origin
	var turn := Quaternion(current.normalized(), (target - pose.origin).normalized())
	_set_basis(skeleton, bone, Basis(turn) * pose.basis)

# Baking happens outside the scene tree. Compute hierarchy transforms directly;
# Skeleton3D's rendered global pose is updated once per frame by the engine.
static func _pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var result := Transform3D.IDENTITY
	while bone >= 0:
		var local := Transform3D(Basis(skeleton.get_bone_pose_rotation(bone)).scaled(skeleton.get_bone_pose_scale(bone)), skeleton.get_bone_pose_position(bone))
		result = local * result
		bone = skeleton.get_bone_parent(bone)
	return result
