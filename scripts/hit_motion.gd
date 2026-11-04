class_name HitMotion
extends RigidBody3D

# A temporary physics motor for bat reactions. Jolt solves momentum, gravity,
# wall/furniture contacts, friction and yaw; the skeleton supplies the fall pose.
# This is a single-body reaction, not a full limb ragdoll.
const BODY_MASS := 72.0
var actor: OfficeWorker
var running := false
var last_impulse := Vector3.ZERO
var _saved_layer := 4
var _saved_mask := 1
var _source: PhysicsBody3D

func setup(person: OfficeWorker) -> void:
	actor = person
	name = "BatHitPhysics"
	top_level = true
	mass = BODY_MASS
	freeze = true
	collision_layer = 0
	collision_mask = 0
	continuous_cd = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	linear_damp = 2.2
	angular_damp = 6.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.8
	physics_material_override.bounce = 0.05
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.26
	capsule.height = 1.65
	collider.shape = capsule
	collider.position.y = 0.835
	add_child(collider)

func launch(impulse: Vector3, point: Vector3, source: PhysicsBody3D) -> void:
	stop()
	_saved_layer = actor.collision_layer
	_saved_mask = actor.collision_mask
	actor.collision_layer = 0
	actor.collision_mask = 0
	global_transform = actor.global_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_source = source
	add_collision_exception_with(actor)
	if is_instance_valid(source): add_collision_exception_with(source)
	collision_layer = 4
	collision_mask = 1 | 4 | 8
	freeze = false
	sleeping = false
	running = true
	last_impulse = impulse
	# Position is relative to the body origin, as required by apply_impulse.
	apply_impulse(impulse, point - global_position)

func sync_actor() -> void:
	if not running: return
	actor.global_position = global_position
	actor.rotation.y = global_rotation.y
	actor.velocity = linear_velocity
	actor.nav_agent.velocity = Vector3.ZERO

func stop() -> void:
	if not running: return
	sync_actor()
	running = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if is_instance_valid(_source): remove_collision_exception_with(_source)
	_source = null
	actor.collision_layer = _saved_layer
	actor.collision_mask = _saved_mask
	actor.velocity = Vector3.ZERO
