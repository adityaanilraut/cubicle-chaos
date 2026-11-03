class_name FurnitureGrip
extends HandReach

# A two-bone reach layered over the walk cycle keeps both hands on the object.

func _process_modification() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.grabbed_furniture):
		return
	var skeleton := get_skeleton()
	var item: FurnitureItem = player.grabbed_furniture
	var center: Vector3 = item.to_global(player.grip_local_point)
	var right := player.global_basis.x.normalized()
	var lean: float = clampf((1.35 - center.y) * 1.8, 0.08, 1.10)
	lean += 0.10 if player.furniture_motion == "push" else -0.04
	for part in [["Spine", 0.60], ["Spine1", 0.25], ["Spine2", 0.15]]:
		var bone := skeleton.find_bone("office_" + part[0])
		if bone >= 0:
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.RIGHT, lean * part[1]))
	for side in ["Left", "Right"]:
		var sign_x := 1.0 if side == "Left" else -1.0
		var target := center + right * sign_x * minf(0.18, minf(item.footprint_size.x, item.footprint_size.z) * 0.35)
		_solve_arm(skeleton, side, skeleton.to_local(target), sign_x)

