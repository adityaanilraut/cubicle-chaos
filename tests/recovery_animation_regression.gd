extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func frame() -> void:
	await physics_frame
	await process_frame

# Reconstruct the final modifier output; Skeleton3D restores its animated input
# after skinning, so reading the skeleton outside the modifier misses the pose.
func joint_positions(actor: OfficeWorker) -> Dictionary:
	var skeleton := actor.combat.pose.get_skeleton()
	var local: Array[Transform3D] = actor.combat.pose._last_pose
	var global: Array[Transform3D] = []
	var result := {}
	for bone in range(local.size()):
		var parent := skeleton.get_bone_parent(bone)
		var transform := global[parent] * local[bone] if parent >= 0 else local[bone]
		global.append(transform)
		result[String(skeleton.get_bone_name(bone)).trim_prefix("office_")] = transform.origin
	return result

func validate_recovery(actor: OfficeWorker, attacker: OfficeWorker) -> void:
	actor.combat.phase = OfficeCombat.Phase.READY
	actor.combat.invulnerable = 0.0
	actor.combat.balance = 1.0
	actor.combat.target = null
	actor._enter_idle(100.0)
	actor.combat.start_attack("kick")
	actor.combat.phase_time = 0.32
	await frame()
	var before := joint_positions(actor)
	actor.combat.receive_hit(attacker, "kick")
	await frame()
	var initial := joint_positions(actor)
	var interrupted_pose_matches := true
	for joint in ["Hips", "Head", "LeftHand", "RightHand", "RightFoot"]:
		interrupted_pose_matches = interrupted_pose_matches and initial[joint].distance_to(before[joint]) < 0.005
	check(interrupted_pose_matches, actor.worker_name + ": fall starts from the interrupted strike pose")
	var previous := initial
	var settled := {}
	var stays_grounded := true
	var continuous := true
	var stays_still := true
	var planted_feet := true
	var hand_support := false
	var knees_separated := false
	var kneels := false
	var rig_stable := true
	var face_follows_head := true
	var saw_recovery := false
	var final_recovery := {}
	for step in range(240):
		actor.combat.tick(1.0 / 60.0)
		await frame()
		var points := joint_positions(actor)
		var face := actor.get_node("Variety") as Node3D
		var face_position := actor.combat.pose.get_skeleton().to_local(face.global_position)
		face_follows_head = face_follows_head and face_position.distance_to(points.Head) < 0.005
		for joint in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot", "Head"]:
			stays_grounded = stays_grounded and points[joint].y >= -0.015
		for joint in ["Hips", "Head", "LeftFoot", "RightFoot", "LeftHand", "RightHand", "LeftLeg", "RightLeg", "LeftForeArm", "RightForeArm"]:
			if points[joint].distance_to(previous[joint]) >= 0.22:
				print("JOINT JUMP ", actor.worker_name, " ", joint, " phase ", actor.combat.phase, " time ", actor.combat.phase_time, " from ", previous[joint], " to ", points[joint])
			continuous = continuous and points[joint].distance_to(previous[joint]) < 0.22
		rig_stable = rig_stable and actor.rig_root.transform.is_equal_approx(Transform3D.IDENTITY)
		if actor.combat.phase == OfficeCombat.Phase.FALLEN and actor.combat.phase_time > OfficeCombat.FALL_LANDING_TIME:
			if settled.is_empty():
				settled = points
			for joint in ["Hips", "Head", "LeftFoot", "RightFoot", "LeftHand", "RightHand"]:
				stays_still = stays_still and points[joint].distance_to(settled[joint]) < 0.0001
		if actor.combat.phase == OfficeCombat.Phase.GETTING_UP:
			saw_recovery = true
			var time := actor.combat.phase_time
			planted_feet = planted_feet and points.LeftFoot.y >= 0.08 and points.LeftFoot.y < 0.15 and points.RightFoot.y >= 0.08 and points.RightFoot.y < 0.15
			if absf(time - 0.66) < 0.02:
				hand_support = points.LeftHand.y < 0.18 and points.RightHand.y < 0.18
				knees_separated = points.LeftLeg.x > 0.04 and points.RightLeg.x < -0.04
			if absf(time - 1.02) < 0.02:
				kneels = points.RightLeg.y < 0.18 and points.LeftLeg.y > points.RightLeg.y + 0.10
			final_recovery = points
		elif saw_recovery:
			break
		previous = points
	check(stays_grounded, actor.worker_name + ": feet, toes and head stay above the floor")
	check(continuous, actor.worker_name + ": fall, recovery and idle transitions have no position jumps")
	check(not settled.is_empty() and stays_still, actor.worker_name + ": body stays still while down")
	check(planted_feet, actor.worker_name + ": feet remain grounded throughout getting up")
	check(hand_support, actor.worker_name + ": hands support the seated recovery pose at floor level")
	check(knees_separated, actor.worker_name + ": knees stay apart instead of crossing during sit up")
	check(kneels, actor.worker_name + ": recovery passes through a half kneel")
	check(rig_stable, actor.worker_name + ": motion does not tilt or lift the entire character rig")
	check(face_follows_head, actor.worker_name + ": hair, eyes and glasses follow the final head pose throughout the fall and rise")
	check(saw_recovery and actor.combat.phase == OfficeCombat.Phase.READY, actor.worker_name + ": returns to normal control after the complete recovery")
	var after := joint_positions(actor)
	var end_matches := true
	for joint in ["Hips", "Head", "LeftFoot", "RightFoot", "LeftHand", "RightHand"]:
		end_matches = end_matches and after[joint].distance_to(final_recovery[joint]) < 0.025
	check(end_matches, actor.worker_name + ": final recovery pose matches the resumed idle")

func _run() -> void:
	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	office.start_in_menu = false
	root.add_child(office)
	await create_timer(0.6).timeout
	var player: OfficePlayer = office.player
	player.set_physics_process(false)
	for person in office.workers_container.get_children():
		person.set_physics_process(false)
		person.nav_agent.avoidance_enabled = false
	var worker: OfficeWorker = office.workers_container.get_child(0)
	player.global_position = Vector3(0.5, 0, 4.0)
	worker.global_position = Vector3(0.5, 0, 5.0)
	await frame()
	await validate_recovery(worker, player)
	worker.global_position = Vector3(0.5, 0, 5.0)
	player.global_position = Vector3(0.5, 0, 4.0)
	# Test the same choreography with a different facing direction on the player.
	worker.combat.invulnerable = 10.0
	await validate_recovery(player, worker)
	print("RECOVERY ANIMATION CHECKS: ", checks - failures.size(), "/", checks, " passed")
	office.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
