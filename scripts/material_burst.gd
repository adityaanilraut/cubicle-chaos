class_name MaterialBurst
extends Node3D

# Dust, soil, leaves and sparks have no collision bodies. The emitter's own
# lifetime guarantees cleanup even when a renderer doesn't emit finished.
var age := 0.0
var lifetime := 1.2

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
	material.roughness = 0.9
	mesh.material = material
	particles.mesh = mesh
	add_child(particles)
	particles.emitting = true

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime: queue_free()
