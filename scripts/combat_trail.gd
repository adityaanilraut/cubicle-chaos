class_name CombatTrail
extends MeshInstance3D

# A short ribbon follows the actual rendered wrist/ankle. Local procedural
# geometry stays lightweight in the web build and needs no downloaded textures.
const LIFE := 0.13
const MAX_POINTS := 12
var combat: OfficeCombat
var points: Array[Vector3] = []
var ages: Array[float] = []
var ribbon := ImmediateMesh.new()
var tint := Color(1.0, 0.72, 0.28)

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = ribbon
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.vertex_color_use_as_albedo = true
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = ink

func sample_tip(skeleton: Skeleton3D) -> void:
	if combat.phase != OfficeCombat.Phase.ATTACK: return
	var move := combat.current_move()
	if combat.phase_time < float(move.contact) * 0.4 or combat.phase_time > float(move.contact) + 0.09: return
	var bone := skeleton.find_bone("office_" + String(move.side) + ("Hand" if move.family == "punch" else "Foot"))
	if bone < 0: return
	var tip := skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
	if not points.is_empty() and points.back().distance_squared_to(tip) < 0.0001: return
	tint = Color(0.30, 0.82, 1.0) if move.family == "kick" else Color(1.0, 0.72, 0.28)
	points.append(tip)
	ages.append(0.0)
	if points.size() > MAX_POINTS:
		points.pop_front()
		ages.pop_front()

func _process(delta: float) -> void:
	for i in range(ages.size()): ages[i] += delta
	while not ages.is_empty() and ages.front() >= LIFE:
		ages.pop_front()
		points.pop_front()
	ribbon.clear_surfaces()
	if points.size() < 2: return
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := combat.actor.global_basis.x * (0.065 if combat.kind == "kick" else 0.04)
	for i in range(1, points.size()):
		for vertex in [0, 1, 2, 2, 1, 3]:
			var index := i - 1 if vertex < 2 else i
			var edge := -1.0 if vertex % 2 == 0 else 1.0
			var color := tint
			color.a = (1.0 - ages[index] / LIFE) * 0.48
			ribbon.surface_set_color(color)
			ribbon.surface_add_vertex(points[index] + width * edge)
	ribbon.surface_end()
