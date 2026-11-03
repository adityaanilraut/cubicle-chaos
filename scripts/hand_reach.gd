class_name HandReach
extends SkeletonModifier3D

# Shared two-bone arm solver for independent furniture and prop pose layers.
var player: Node3D

func _solve_arm(skeleton: Skeleton3D, side: String, target: Vector3, sign_x: float) -> void:
	var upper := skeleton.find_bone("office_" + side + "Arm")
	var lower := skeleton.find_bone("office_" + side + "ForeArm")
	var hand := skeleton.find_bone("office_" + side + "Hand")
	if upper < 0 or lower < 0 or hand < 0:
		return
	var shoulder_pos := skeleton.get_bone_global_pose(upper).origin
	var elbow_pos := skeleton.get_bone_global_pose(lower).origin
	var wrist_pos := skeleton.get_bone_global_pose(hand).origin
	var a := shoulder_pos.distance_to(elbow_pos)
	var b := elbow_pos.distance_to(wrist_pos)
	var direction := (target - shoulder_pos).normalized()
	var distance := clampf(shoulder_pos.distance_to(target), absf(a - b) + 0.01, a + b - 0.015)
	var bend := Vector3(sign_x * 0.65, -1.0, -0.2)
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := clampf((a * a + distance * distance - b * b) / (2.0 * distance), -a, a)
	var elbow_target := shoulder_pos + direction * along + bend * sqrt(maxf(0.0, a * a - along * along))
	_aim_bone(skeleton, upper, lower, elbow_target)
	_aim_bone(skeleton, lower, hand, shoulder_pos + direction * distance)

func _aim_bone(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current_dir := skeleton.get_bone_global_pose(child).origin - pose.origin
	var desired_dir := target - pose.origin
	if current_dir.length_squared() < 0.00001 or desired_dir.length_squared() < 0.00001:
		return
	var rotation_delta := Quaternion(current_dir.normalized(), desired_dir.normalized())
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local_basis := parent_basis.inverse() * Basis(rotation_delta) * pose.basis
	skeleton.set_bone_pose_rotation(bone, local_basis.orthonormalized().get_rotation_quaternion())
