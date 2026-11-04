class_name MaterialBurst
extends Node3D

# Dust, soil, leaves and sparks have no collision bodies. The emitter's own
# lifetime guarantees cleanup even when a renderer doesn't emit finished.
var age := 0.0
var lifetime := 1.2
var flow: CPUParticles3D
var flow_started := false
var shock_ring: MeshInstance3D

func setup(profile: DestructionProfile, broken: bool, direction: Vector3) -> void:
	add_to_group("material_effects")
	var chip_size := Vector3(0.025, 0.025, 0.025)
	if profile.material_id in ["paper", "cardboard", "fabric"]:
		chip_size = Vector3(0.05, 0.006, 0.035)
	elif profile.material_id == "glass":
		chip_size = Vector3(0.035, 0.04, 0.006)
	_emit(profile.chip_color, 14 if broken else 4, chip_size, direction)
	if broken and profile.fracture_id == "plant":
		_emit(Color(0.23, 0.14, 0.08), 16, Vector3(0.05, 0.035, 0.04), direction)
		_emit(Color(0.28, 0.52, 0.18), 8, Vector3(0.08, 0.015, 0.04), direction)
	if profile.material_id == "electronic":
		_emit(Color(1.0, 0.69, 0.18), 9 if broken else 3, Vector3(0.012, 0.05, 0.012), direction)
	if broken and profile.material_id in ["wood", "masonry"]:
		_emit(profile.chip_color.lightened(0.15), 12, Vector3(0.04, 0.04, 0.04), direction)
	if broken:
		# A sharp chip burst is followed by a slower plume along the impact.
		_build_flow(profile, direction)
		shock_ring = MeshInstance3D.new()
		shock_ring.name = "BreakPulse"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.22
		ring.outer_radius = 0.27
		ring.rings = 20
		ring.ring_segments = 6
		shock_ring.mesh = ring
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = profile.chip_color
		shock_ring.material_override = material
		shock_ring.position.y = -global_position.y + 0.035
		add_child(shock_ring)

func _build_flow(profile: DestructionProfile, direction: Vector3) -> void:
	flow = CPUParticles3D.new()
	flow.name = "DebrisFlow"
	flow.amount = 12
	flow.lifetime = 0.95
	flow.one_shot = true
	flow.explosiveness = 0.65
	flow.emitting = false
	flow.direction = (direction + Vector3.UP * 0.35).normalized()
	flow.spread = 24.0
	flow.initial_velocity_min = 0.4
	flow.initial_velocity_max = 1.8
	flow.gravity = Vector3(0, -0.7, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.material = material
	flow.mesh = mesh
	var ramp := Gradient.new()
	var tint := profile.chip_color
	tint.a = 0.36
	ramp.set_color(0, tint)
	tint.a = 0.0
	ramp.set_color(1, tint)
	flow.color_ramp = ramp
	var growth := Curve.new()
	growth.max_value = 2.5
	growth.add_point(Vector2(0, 0.3))
	growth.add_point(Vector2(0.65, 1.8))
	growth.add_point(Vector2(1, 2.3))
	flow.scale_amount_curve = growth
	add_child(flow)

func _emit(color: Color, count: int, size: Vector3, direction: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = count
	particles.lifetime = 0.7
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = (direction + Vector3.UP).normalized()
	particles.spread = 65
	particles.initial_velocity_min = 0.7
	particles.initial_velocity_max = 2.2
	particles.gravity = Vector3(0, -4.0, 0)
	particles.angular_velocity_min = -160
	particles.angular_velocity_max = 160
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	mesh.material = material
	particles.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.add_point(0.55, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	add_child(particles)
	particles.emitting = true

func _process(delta: float) -> void:
	age += delta
	if is_instance_valid(flow) and not flow_started and age >= 0.055:
		flow_started = true
		flow.emitting = true
	if is_instance_valid(shock_ring):
		var progress := clampf(age / 0.32, 0, 1)
		shock_ring.scale = Vector3.ONE * lerpf(0.3, 3.2, progress)
		shock_ring.transparency = progress
	if age >= lifetime: queue_free()
