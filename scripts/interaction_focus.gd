class_name InteractionFocus
extends Node3D

# A white silhouette (yellow and thicker in high-contrast mode), plus a thin
# floor border that remains legible on rugs.
const OUTLINE_SHADER := "shader_type spatial; render_mode unshaded, cull_front, world_vertex_coords; uniform float expand = 0.018; uniform vec4 tint : source_color = vec4(1.0); void vertex() { VERTEX += NORMAL * expand; } void fragment() { ALBEDO = tint.rgb; }"
const NORMAL_COLOR := Color.WHITE
const CONTRAST_COLOR := Color(1.0, 0.85, 0.0)
var high_contrast := false
var target: Node3D
var outlined_meshes: Array[MeshInstance3D] = []
var previous_overlays: Array[Material] = []
var outline_material: ShaderMaterial
var border_material: StandardMaterial3D
var border: Node3D

func _ready() -> void:
	top_level = true
	var shader := Shader.new()
	shader.code = OUTLINE_SHADER
	outline_material = ShaderMaterial.new()
	outline_material.shader = shader
	border_material = StandardMaterial3D.new()
	border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_material.albedo_color = Color.WHITE
	border = Node3D.new()
	add_child(border)
	visible = false

func highlight_color() -> Color:
	return CONTRAST_COLOR if high_contrast else NORMAL_COLOR

func outline_expand() -> float:
	return 0.042 if high_contrast else 0.018

func set_high_contrast(enabled: bool) -> void:
	high_contrast = enabled
	if outline_material:
		outline_material.set_shader_parameter("expand", outline_expand())
		outline_material.set_shader_parameter("tint", highlight_color())
	if border_material:
		border_material.albedo_color = highlight_color()
	if border:
		border.scale = Vector3.ONE * (1.6 if high_contrast else 1.0)

func set_target(value: Node3D) -> void:
	if target == value and is_instance_valid(value):
		return
	_clear_outline()
	target = value
	visible = is_instance_valid(target)
	if not visible:
		return
	var visual: Node = target.visual_root if target is FurnitureItem else target.rig_root if target is OfficeWorker else target
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D:
			outlined_meshes.append(mesh)
			previous_overlays.append(mesh.material_overlay)
			mesh.material_overlay = outline_material
	for child in border.get_children():
		border.remove_child(child)
		child.queue_free()
	if target is FurnitureItem:
		var size: Vector3 = target.footprint_size + Vector3(0.16, 0, 0.16)
		for side in [-1.0, 1.0]:
			_add_edge(Vector3(size.x, 0.025, 0.025), Vector3(0, 0.04, side * size.z * 0.5))
			_add_edge(Vector3(0.025, 0.025, size.z), Vector3(side * size.x * 0.5, 0.04, 0))
	else:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.41 if target is OfficeWorker else 0.21
		torus.outer_radius = torus.inner_radius + 0.035
		ring.mesh = torus
		ring.material_override = border_material
		ring.position.y = 0.04
		border.add_child(ring)
	_process(0.0)

func _add_edge(size: Vector3, at: Vector3) -> void:
	var edge := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	edge.mesh = mesh
	edge.material_override = border_material
	edge.position = at
	border.add_child(edge)

func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		if visible:
			set_target(null)
		return
	global_position = target.global_position
	global_rotation = Vector3(0, target.global_rotation.y, 0)

func _clear_outline() -> void:
	for i in range(outlined_meshes.size()):
		if is_instance_valid(outlined_meshes[i]) and outlined_meshes[i].material_overlay == outline_material:
			outlined_meshes[i].material_overlay = previous_overlays[i]
	outlined_meshes.clear()
	previous_overlays.clear()

func _exit_tree() -> void:
	_clear_outline()
