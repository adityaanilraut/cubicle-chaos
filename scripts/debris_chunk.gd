class_name DebrisChunk
extends RigidBody3D

var age := 0.0
var lifetime := 5.0
var _mesh_instance: MeshInstance3D
var part_name := "fragment"
var family_id := "mixed"
var material_id := "plastic"

func setup(size: Vector3, color: Color, velocity: Vector3, part_mesh: Mesh = null, profile: DestructionProfile = null, part_material := "") -> void:
	add_to_group("destruction_debris")
	if profile == null: profile = DestructionProfile.for_item("")
	family_id = profile.family_id
	material_id = part_material if DestructionProfile.MATERIALS.has(part_material) else profile.material_id
	var properties := profile.debris_properties(material_id)
	mass = clampf(size.x * size.y * size.z * float(properties.density), 0.015, 3.0)
	lifetime = properties.lifetime
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = properties.bounce
	physics_material_override.friction = properties.friction
	# Decorative fragments collide with the environment, never characters or
	# other fragments. This avoids debris explosions and accidental damage.
	collision_layer = 16
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	_mesh_instance = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh_instance.mesh = part_mesh if part_mesh != null else mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = properties.roughness
	if material_id == "glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if material_id == "metal": material.metallic = 0.6
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	linear_velocity = velocity
	angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	if material_id in ["paper", "fabric", "cardboard"]:
		angular_velocity *= 1.8 # Light fragments flutter as the plume trails off.
	linear_damp = properties.damp
	angular_damp = maxf(1.1, float(properties.damp))

func _process(delta: float) -> void:
	age += delta
	if age > lifetime - 0.8:
		var weight := clampf((lifetime - age) / 0.8, 0.0, 1.0)
		_mesh_instance.scale = Vector3.ONE * maxf(weight, 0.01)
		_mesh_instance.transparency = 1.0 - weight
	if age > 2.0 and linear_velocity.length_squared() < 0.04:
		sleeping = true
	if age >= lifetime:
		queue_free()
