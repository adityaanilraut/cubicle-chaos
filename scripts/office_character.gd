# SPDX-License-Identifier: MIT
class_name OfficeCharacter
extends RefCounted

# Original, metre-scale character geometry. Each rigid mesh section is skinned
# to our own skeleton; no imported mesh, bind pose or motion data is used.
const PREFIX := "office_"
static var _meshes: Dictionary = {}
static var _skin: Skin

static func create_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	_bone(skeleton, "Hips", "", Vector3(0, 0.965, 0))
	_bone(skeleton, "Spine", "Hips", Vector3(0, 0.13, 0))
	_bone(skeleton, "Spine1", "Spine", Vector3(0, 0.15, 0))
	_bone(skeleton, "Spine2", "Spine1", Vector3(0, 0.14, 0))
	_bone(skeleton, "Neck", "Spine2", Vector3(0, 0.12, 0))
	_bone(skeleton, "Head", "Neck", Vector3(0, 0.14, 0))
	_bone(skeleton, "HeadTop_End", "Head", Vector3(0, 0.15, 0))
	for side in ["Left", "Right"]:
		var sign_x := 1.0 if side == "Left" else -1.0
		_bone(skeleton, side + "Shoulder", "Spine2", Vector3(sign_x * 0.11, 0.015, 0))
		_bone(skeleton, side + "Arm", side + "Shoulder", Vector3(sign_x * 0.11, -0.005, 0))
		_bone(skeleton, side + "ForeArm", side + "Arm", Vector3(0, -0.29, 0.015))
		_bone(skeleton, side + "Hand", side + "ForeArm", Vector3(0, -0.27, 0.015))
		for finger_index in range(5):
			var finger: String = ["Thumb", "Index", "Middle", "Ring", "Pinky"][finger_index]
			for joint in range(1, 4):
				var parent: String = side + "Hand" if joint == 1 else side + "Hand" + finger + str(joint - 1)
				var offset := Vector3(sign_x * (float(finger_index) - 2.0) * 0.014, -0.075, 0.0) if joint == 1 else Vector3(0, -0.023, 0)
				_bone(skeleton, side + "Hand" + finger + str(joint), parent, offset)
		_bone(skeleton, side + "UpLeg", "Hips", Vector3(sign_x * 0.105, -0.02, 0))
		_bone(skeleton, side + "Leg", side + "UpLeg", Vector3(0, -0.425, 0))
		_bone(skeleton, side + "Foot", side + "Leg", Vector3(0, -0.415, 0))
		_bone(skeleton, side + "ToeBase", side + "Foot", Vector3(0, -0.025, 0.135))
	return skeleton

static func _bone(skeleton: Skeleton3D, name: String, parent: String, offset: Vector3) -> void:
	var index := skeleton.add_bone(PREFIX + name)
	if not parent.is_empty(): skeleton.set_bone_parent(index, skeleton.find_bone(PREFIX + parent))
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))
	skeleton.set_bone_pose_position(index, offset)

static func create_rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "CharacterRig"
	var skeleton := create_skeleton()
	rig.add_child(skeleton)
	if _meshes.is_empty(): _build_meshes(skeleton)
	for role in _meshes:
		var instance := MeshInstance3D.new()
		instance.name = role
		instance.mesh = _meshes[role]
		instance.skin = _skin
		instance.skeleton = NodePath("..")
		# Include the full animated reach, rather than culling by the rest pose.
		instance.custom_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3, 2.5, 3))
		skeleton.add_child(instance)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	rig.add_child(player)
	return rig

static func _build_meshes(skeleton: Skeleton3D) -> void:
	var parts := {"OfficeOutfit": [], "OfficeSkin": [], "OfficeTrousers": [], "OfficeDetails": []}
	_part(parts, "OfficeOutfit", "Spine1", Vector3(0, 0.035, 0), Vector3(0.35, 0.32, 0.23))
	_part(parts, "OfficeOutfit", "Spine", Vector3(0, 0.015, 0), Vector3(0.29, 0.17, 0.21))
	_part(parts, "OfficeTrousers", "Hips", Vector3(0, -0.015, 0), Vector3(0.29, 0.16, 0.22))
	_part(parts, "OfficeSkin", "Neck", Vector3(0, 0.02, 0), Vector3(0.10, 0.13, 0.10), true)
	_part(parts, "OfficeSkin", "Head", Vector3(0, 0.012, 0), Vector3(0.22, 0.25, 0.215), true)
	# White collar and a narrow tie keep the silhouette recognisably office wear.
	_part(parts, "OfficeDetails", "Spine2", Vector3(0, 0.012, 0.11), Vector3(0.13, 0.055, 0.025))
	_part(parts, "OfficeTrousers", "Spine1", Vector3(0, 0.055, 0.13), Vector3(0.026, 0.19, 0.018))
	for side in ["Left", "Right"]:
		_part(parts, "OfficeOutfit", side + "Arm", Vector3(0, -0.135, 0.005), Vector3(0.13, 0.28, 0.14))
		_part(parts, "OfficeOutfit", side + "ForeArm", Vector3(0, -0.10, 0.005), Vector3(0.105, 0.22, 0.115))
		_part(parts, "OfficeSkin", side + "Hand", Vector3(0, -0.042, 0), Vector3(0.075, 0.085, 0.045), true)
		_part(parts, "OfficeTrousers", side + "UpLeg", Vector3(0, -0.20, 0), Vector3(0.14, 0.40, 0.16))
		_part(parts, "OfficeTrousers", side + "Leg", Vector3(0, -0.195, 0), Vector3(0.12, 0.40, 0.14))
		_part(parts, "OfficeTrousers", side + "Foot", Vector3(0, -0.045, 0.065), Vector3(0.14, 0.10, 0.25))
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for joint in range(1, 4):
				_part(parts, "OfficeSkin", side + "Hand" + finger + str(joint), Vector3(0, -0.01, 0), Vector3(0.012, 0.024, 0.018))
	_skin = skeleton.create_skin_from_rest_transforms()
	for role in parts:
		_meshes[role] = _merge_parts(skeleton, parts[role])

static func _part(parts: Dictionary, role: String, bone: String, center: Vector3, size: Vector3, rounded := false) -> void:
	var primitive: PrimitiveMesh
	if rounded:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 12
		sphere.rings = 6
		primitive = sphere
	else:
		primitive = BoxMesh.new()
	parts[role].append({"mesh": primitive, "bone": bone, "transform": Transform3D(Basis.from_scale(size), center)})

static func _merge_parts(skeleton: Skeleton3D, parts: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for part in parts:
		var bone := skeleton.find_bone(PREFIX + String(part.bone))
		var transform: Transform3D = skeleton.get_bone_global_rest(bone) * part.transform
		var normal_basis := transform.basis.inverse().transposed()
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var offset := vertices.size()
		for index in range(arrays[Mesh.ARRAY_VERTEX].size()):
			vertices.append(transform * arrays[Mesh.ARRAY_VERTEX][index])
			normals.append((normal_basis * arrays[Mesh.ARRAY_NORMAL][index]).normalized())
			bones.append_array(PackedInt32Array([bone, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
		for index in arrays[Mesh.ARRAY_INDEX]: indices.append(offset + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
