class_name WorkerVariety
extends Node3D

# Procedural variety on the original shared office rig: hair style, hair and
# outfit shade, face (eyes), and optional glasses are derived from the
# worker index, so every coworker reads as a different person with no
# extra downloaded models.

const HAIR_COLORS: Array[Color] = [
	Color(0.16, 0.11, 0.08), Color(0.42, 0.26, 0.14), Color(0.72, 0.55, 0.30),
	Color(0.12, 0.12, 0.14), Color(0.55, 0.22, 0.16), Color(0.85, 0.82, 0.78),
	Color(0.25, 0.35, 0.55), Color(0.45, 0.25, 0.45),
]
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.80, 0.66), Color(0.88, 0.66, 0.50), Color(0.72, 0.50, 0.36),
	Color(0.55, 0.36, 0.24), Color(0.98, 0.86, 0.74), Color(0.62, 0.42, 0.30),
]

static func variety_for(index: int) -> Dictionary:
	var i := absi(index)
	return {
		"hair_style": i % 4,
		"hair_color": HAIR_COLORS[i % HAIR_COLORS.size()],
		"skin_tone": SKIN_TONES[i % SKIN_TONES.size()],
		"has_glasses": i % 3 == 1,
		"height_scale": 0.99 + float(i % 3) * 0.01,
	}

var worker: OfficeWorker
var _skeleton: Skeleton3D
var _head_bone := -1
var _hair: MeshInstance3D
var _bun: MeshInstance3D
var _mohawk: MeshInstance3D
var _appearance_scale := 1.0

func setup(p_worker: OfficeWorker, index: int) -> void:
	worker = p_worker
	name = "Variety"
	var variety := variety_for(index)
	_skeleton = worker.rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton != null:
		_head_bone = _skeleton.find_bone("office_Head")
	var hair_color: Color = variety["hair_color"]
	_hair = _sphere(0.115, hair_color)
	_hair.scale = Vector3(1.0, 0.62, 1.0)
	_hair.position = Vector3(0.0, 0.085, -0.012)
	add_child(_hair)
	_bun = _sphere(0.055, hair_color)
	_bun.position = Vector3(0.0, 0.10, -0.105)
	add_child(_bun)
	_mohawk = MeshInstance3D.new()
	var mohawk_mesh := BoxMesh.new()
	mohawk_mesh.size = Vector3(0.03, 0.09, 0.16)
	_mohawk.mesh = mohawk_mesh
	_mohawk.material_override = _material(hair_color)
	_mohawk.position = Vector3(0.0, 0.13, 0.0)
	add_child(_mohawk)
	var style: int = int(variety["hair_style"])
	_hair.visible = style != 3
	_bun.visible = style == 1
	_mohawk.visible = style == 2
	# Face: two eyes on the front of the head.
	for side in [-1.0, 1.0]:
		var eye := _sphere(0.013, Color(0.08, 0.07, 0.07))
		eye.position = Vector3(side * 0.036, 0.015, 0.098)
		add_child(eye)
	if bool(variety["has_glasses"]):
		for side in [-1.0, 1.0]:
			var lens := MeshInstance3D.new()
			var lens_mesh := TorusMesh.new()
			lens_mesh.inner_radius = 0.026
			lens_mesh.outer_radius = 0.032
			lens.mesh = lens_mesh
			lens.material_override = _material(Color(0.10, 0.10, 0.12))
			lens.rotation.x = PI * 0.5
			lens.position = Vector3(side * 0.036, 0.015, 0.10)
			add_child(lens)
	# Skin tone shows as a small nose so faces differ, not just hair.
	var nose := _sphere(0.016, variety["skin_tone"])
	nose.position = Vector3(0.0, -0.005, 0.105)
	add_child(nose)
	_appearance_scale = float(variety["height_scale"])
	if _skeleton != null and _head_bone >= 0:
		_skeleton.skeleton_updated.connect(_sync_head)
		_sync_head()

func _ready() -> void:
	_sync_head()

func _sync_head() -> void:
	if not is_inside_tree() or not is_instance_valid(worker) or _skeleton == null or _head_bone < 0:
		return
	# Follow the final skinned pose, after combat/IK modifiers. Reading the
	# animation input in _process left hair, eyes and glasses floating above a
	# lowered guard or fallen body. Remove the rest axes to preserve how these
	# face meshes were authored, while inheriting animated head pitch and roll.
	var head := _skeleton.get_bone_global_pose(_head_bone)
	var rest := _skeleton.get_bone_global_rest(_head_bone)
	var orientation := (_skeleton.global_basis * head.basis * rest.basis.inverse()).orthonormalized()
	global_transform = Transform3D(orientation.scaled(Vector3.ONE * _appearance_scale), _skeleton.to_global(head.origin))

func _sphere(radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	instance.mesh = mesh
	instance.material_override = _material(color)
	return instance

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
