class_name PropGrip
extends HandReach

# Layer hands and torso over idle/walk, preserving the existing foot motion.
func _process_modification() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.prop_handling): return
	var handling: PropHandling = player.prop_handling
	var held := is_instance_valid(player.held_prop)
	if not held and handling.gesture != "release" and handling.gesture != "place": return
	var skeleton := get_skeleton()
	var center: Vector3
	var width := 0.17
	var lean := 0.05
	if held:
		var prop: PhysicsProp = player.held_prop
		center = prop.global_position + Vector3.UP * minf(prop.footprint_size.y * 0.45, 0.25)
		width = clampf(prop.footprint_size.x * 0.42, 0.10, 0.28)
		lean += minf(prop.mass * 0.025, 0.16)
		if handling.gesture == "pickup": lean += (1.0 - handling.gesture_time / handling.gesture_duration) * 0.55
		if handling.charging: lean -= handling.charge_fraction() * 0.13
	else:
		var t := clampf(handling.gesture_time / handling.gesture_duration, 0, 1)
		center = player.global_position + player.global_basis.z * lerpf(0.82, 0.40, t) + Vector3.UP * lerpf(1.35, 1.02, t)
	for part in [["Spine", 0.6], ["Spine1", 0.4]]:
		var bone := skeleton.find_bone("office_" + part[0])
		if bone >= 0: skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.RIGHT, lean * part[1]))
	for side in ["Left", "Right"]:
		var sign_x := 1.0 if side == "Left" else -1.0
		var target := center + player.global_basis.x * sign_x * width
		_solve_arm(skeleton, side, skeleton.to_local(target), sign_x)
