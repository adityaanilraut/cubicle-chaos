extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var rig := OfficeCharacter.create_rig()
	root.add_child(rig)
	var skeleton := rig.get_node("Skeleton3D") as Skeleton3D
	var library := AssetCatalog.get_worker_animation_library()
	for name in ["idle", "walk", "typing", "stand_to_sit", "sit_to_stand", "work_standing", "grip", "push", "pull", "run", "flee", "shower", "wash_hands", "toilet_idle", "wave", "stretch", "drink", "talk", "talk2"]:
		check(library.has_animation(name), name + " is available without imported character files")
	for name in library.get_animation_list():
		var clip := library.get_animation(name)
		var valid_targets := true
		var closed_loop := true
		for track in range(clip.get_track_count()):
			var path := clip.track_get_path(track)
			valid_targets = valid_targets and skeleton.find_bone(path.get_subname(0)) >= 0
			var count := clip.track_get_key_count(track)
			if clip.loop_mode == Animation.LOOP_LINEAR:
				closed_loop = closed_loop and clip.track_get_key_value(track, 0).is_equal_approx(clip.track_get_key_value(track, count - 1))
		check(valid_targets, name + " targets existing native bones")
		check(closed_loop, name + " has a seamless loop")
	for role in ["OfficeOutfit", "OfficeSkin", "OfficeTrousers", "OfficeDetails"]:
		var instance := skeleton.get_node(role) as MeshInstance3D
		check(instance.mesh != null and instance.skin.get_bind_count() == skeleton.get_bone_count(), role + " has complete skin bindings")
		var arrays := instance.mesh.surface_get_arrays(0)
		var normalized := true
		for vertex in range(arrays[Mesh.ARRAY_VERTEX].size()):
			var total := 0.0
			for influence in range(4):
				total += arrays[Mesh.ARRAY_WEIGHTS][vertex * 4 + influence]
				normalized = normalized and arrays[Mesh.ARRAY_BONES][vertex * 4 + influence] < skeleton.get_bone_count()
			normalized = normalized and is_equal_approx(total, 1.0)
		check(normalized, role + " has valid normalized vertex weights")
	PlayerAnimations._sample_source(skeleton, library.get_animation("idle"), 0.0)
	var head := skeleton.find_bone("office_Head")
	check(PlayerAnimations._pose(skeleton, head).origin.y > 1.60, "Native character fits the standing gameplay capsule")
	PlayerAnimations._sample_source(skeleton, library.get_animation("stand_to_sit"), 2.05)
	check(skeleton.get_bone_pose_position(0).y < 0.60, "Sitting lowers the pelvis to chair height")
	PlayerAnimations._sample_source(skeleton, library.get_animation("sit_to_stand"), 2.05)
	check(skeleton.get_bone_pose_position(0).y > 0.94, "Standing restores the upright pelvis")
	for side in ["Left", "Right"]:
		PlayerAnimations._sample_source(skeleton, library.get_animation("idle"), 0.0)
		var target := Vector3(0.2 if side == "Left" else -0.2, 1.25, 0.35)
		PlayerAnimations._solve_limb(skeleton, side + "Arm", side + "ForeArm", side + "Hand", target, Vector3(1 if side == "Left" else -1, -1, 0))
		var hand := skeleton.find_bone("office_" + side + "Hand")
		check(PlayerAnimations._pose(skeleton, hand).origin.distance_to(target) < 0.015, side + " hand reaches the gameplay grip target")
	check(not DirAccess.dir_exists_absolute("res://animations"), "Restricted imported character assets are absent")
	rig.queue_free()
	await process_frame
	for path in ["res://LICENSE", "res://THIRD_PARTY_NOTICES.md", "res://assets/fonts/OFL.txt", "res://kenney_furniture-kit/License.txt"]:
		check(FileAccess.file_exists(path), path + " notice is available")
	var notices := OfficeLicenses.text()
	check(notices.contains("SIL OPEN FONT LICENSE") and notices.contains("Google LLC"), "Credits include the font's full license and copyright")
	check(notices.contains(Engine.get_license_text()), "Credits include the running engine's license")
	for license_name in Engine.get_license_info():
		check(notices.contains(String(Engine.get_license_info()[license_name])), String(license_name) + " engine dependency license is accessible")
	var office: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(office)
	await process_frame
	office.game_menu.show_credits()
	check(paused and office.game_menu.menu_state == &"credits", "Credits open from the level menu with the game paused")
	var text := office.game_menu.content.find_child("LicenseText", false, false) as TextEdit
	check(text != null and not text.editable and text.text == notices.replace("\r", ""), "Credits show the complete notices in a read-only viewer")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	office.game_menu._input(escape)
	check(paused and office.game_menu.menu_state == &"title", "Escape returns from credits to the level menu")
	office.queue_free()
	await process_frame
	print("ORIGINAL ASSETS CHECKS: ", checks - failures.size(), "/", checks, " passed")
	quit(0 if failures.is_empty() else 1)
