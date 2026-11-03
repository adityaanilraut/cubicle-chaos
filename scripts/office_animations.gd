# SPDX-License-Identifier: MIT
class_name OfficeAnimations
extends RefCounted

# Original keyframes generated from simple poses and two-bone reach targets.
# Timing is matched to gameplay transitions, not sampled from external clips.
const CLIPS := {
	"idle": [3.2, true], "idle_breath": [3.2, true], "lean": [3.2, true],
	"walk": [0.95, true], "stand_to_sit": [2.05, false],
	"sit_to_type": [1.05, false], "typing": [2.4, true],
	"type_to_sit": [0.85, false], "sit_to_stand": [2.05, false],
	"sitting_idle": [3.2, true], "drink": [3.2, true],
	"watercooler": [3.2, true], "talk": [3.2, true],
	"talk2": [3.2, true], "wave": [2.4, false], "stretch": [3.2, true]
}

static func build_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var skeleton := OfficeCharacter.create_skeleton()
	for kind: String in CLIPS:
		var clip := Animation.new()
		clip.length = float(CLIPS[kind][0])
		clip.loop_mode = Animation.LOOP_LINEAR if CLIPS[kind][1] else Animation.LOOP_NONE
		for bone in range(skeleton.get_bone_count()):
			for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
				var track := clip.add_track(type)
				clip.track_set_path(track, NodePath("Skeleton3D:" + skeleton.get_bone_name(bone)))
		for frame in range(49):
			var t := float(frame) / 48.0
			_pose(skeleton, kind, t)
			for bone in range(skeleton.get_bone_count()):
				clip.position_track_insert_key(bone * 2, t * clip.length, skeleton.get_bone_pose_position(bone))
				clip.rotation_track_insert_key(bone * 2 + 1, t * clip.length, skeleton.get_bone_pose_rotation(bone))
		library.add_animation(kind, clip)
	skeleton.free()
	return library

static func _pose(skeleton: Skeleton3D, kind: String, t: float) -> void:
	skeleton.reset_bone_poses()
	var phase := t * TAU
	var seated := 1.0 if kind in ["sitting_idle", "typing", "sit_to_type", "type_to_sit"] else 0.0
	if kind == "stand_to_sit": seated = smoothstep(0.12, 0.90, t)
	if kind == "sit_to_stand": seated = 1.0 - smoothstep(0.08, 0.90, t)
	var hips := skeleton.find_bone(OfficeCharacter.PREFIX + "Hips")
	skeleton.set_bone_pose_position(hips, Vector3(0, lerpf(0.965, 0.54, seated), -0.035 * seated))
	var breath := sin(phase) * (0.012 if kind == "idle_breath" else 0.006)
	PlayerAnimations._rotate(skeleton, "Spine", Vector3.RIGHT, breath + (0.08 if kind in ["lean", "typing"] else 0.0))
	PlayerAnimations._rotate(skeleton, "Head", Vector3.UP, 0.035 * sin(phase))
	for side in ["Left", "Right"]:
		var sign_x := 1.0 if side == "Left" else -1.0
		var foot := Vector3(sign_x * 0.105, 0.105, 0.0).lerp(Vector3(sign_x * 0.13, 0.105, 0.40), seated)
		var hand := Vector3(sign_x * 0.25, 0.91, 0.065).lerp(Vector3(sign_x * 0.21, 0.68, 0.27), seated)
		if kind == "walk":
			var cycle := fposmod(t + (0.0 if side == "Left" else 0.5), 1.0)
			var planted := cycle < 0.60
			var step := cycle / 0.60 if planted else (cycle - 0.60) / 0.40
			foot.z = lerpf(0.26, -0.26, step) if planted else lerpf(-0.26, 0.26, smoothstep(0, 1, step))
			if not planted: foot.y += 0.13 * sin(step * PI)
			hand.z = 0.08 - foot.z * 0.70
			hand.y += 0.045 * sin(phase * sign_x)
		var typing := 1.0 if kind == "typing" else smoothstep(0.0, 1.0, t) if kind == "sit_to_type" else 1.0 - smoothstep(0.0, 1.0, t) if kind == "type_to_sit" else 0.0
		if typing > 0.0:
			hand = hand.lerp(Vector3(sign_x * 0.16, 0.79 + 0.012 * sin(phase * 4 + sign_x), 0.43), typing)
		if kind in ["talk", "talk2", "watercooler"]:
			hand = Vector3(sign_x * (0.29 + 0.05 * sin(phase + sign_x)), 1.10 + 0.12 * sin(phase + sign_x), 0.26 + 0.08 * cos(phase))
		if kind == "drink" and side == "Right":
			var lift := smoothstep(0.05, 0.30, t) * (1.0 - smoothstep(0.65, 0.95, t))
			hand = hand.lerp(Vector3(-0.10, 1.55, 0.23), lift)
		if kind == "wave" and side == "Right":
			var lift := sin(PI * t)
			hand = hand.lerp(Vector3(-0.40 + 0.09 * sin(phase * 3), 1.88, 0.12), lift)
		if kind == "stretch":
			var lift := 0.5 - 0.5 * cos(phase)
			hand = hand.lerp(Vector3(sign_x * 0.27, 1.95, 0.02), lift)
		PlayerAnimations._solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3(sign_x * 0.10, 0.2, 1))
		var ankle := skeleton.find_bone(OfficeCharacter.PREFIX + side + "Foot")
		PlayerAnimations._set_basis(skeleton, ankle, Basis.IDENTITY)
		PlayerAnimations._solve_limb(skeleton, side + "Arm", side + "ForeArm", side + "Hand", hand, Vector3(sign_x * 0.4, -0.7, -0.2))
