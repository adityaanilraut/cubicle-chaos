class_name PhysicsProp
extends RigidBody3D

# A real rigid-body prop: it rolls, stacks, topples, can be carried with T
# and thrown. It also takes damage and breaks into debris like furniture.

var prop_id := "book"
var prop_title := "Book"
var footprint_size := Vector3(0.3, 0.2, 0.3)
var max_health := 24.0
var destructible: DestructibleState
var debris_profile: DestructionProfile
var health: float:
	get: return destructible.health if is_instance_valid(destructible) else max_health
	set(value):
		if is_instance_valid(destructible): destructible.restore_health(value)
var held_by: Node3D = null
var impact: PropImpact
var collision_shape: CollisionShape3D
var carry_speed_scale := 1.0
var release_owner: PhysicsBody3D
var owner_grace := 0.0

const HANDLING := {
	"book": {"mass": 0.65, "speed": 0.95},
	"box": {"mass": 2.8, "speed": 0.78},
	"plant": {"mass": 2.2, "speed": 0.82},
	"laptop": {"mass": 1.7, "speed": 0.90},
	"radio": {"mass": 1.5, "speed": 0.90},
	"speaker": {"mass": 3.8, "speed": 0.68},
	"keyboard": {"mass": 0.45, "speed": 0.98},
	"bear": {"mass": 0.3, "speed": 1.0},
	"monitor": {"mass": 3.2, "speed": 0.72},
	"baseball_bat": {"mass": 0.95, "speed": 0.96},
}

const GLB_BY_ID := {
	"book": "books.glb",
	"box": "cardboardBoxClosed.glb",
	"plant": "plantSmall1.glb",
	"laptop": "laptop.glb",
	"radio": "radio.glb",
	"speaker": "speakerSmall.glb",
	"keyboard": "computerKeyboard.glb",
	"bear": "bear.glb",
	"monitor": "computerScreen.glb",
	"baseball_bat": "", # Built locally by BaseballBat, with no imported model.
}
const COLOR_BY_ID := {
	"book": Color(0.55, 0.38, 0.25),
	"box": Color(0.62, 0.48, 0.32),
	"plant": Color(0.30, 0.55, 0.28),
	"laptop": Color(0.30, 0.34, 0.42),
	"radio": Color(0.50, 0.30, 0.22),
	"speaker": Color(0.22, 0.24, 0.30),
	"keyboard": Color(0.28, 0.30, 0.36),
	"bear": Color(0.62, 0.45, 0.30),
}

func setup(p_id: String) -> void:
	prop_id = p_id
	prop_title = "Baseball bat" if p_id == "baseball_bat" else p_id.capitalize()
	add_to_group("physics_props")
	var handling: Dictionary = HANDLING.get(prop_id, HANDLING.book)
	mass = handling.mass
	carry_speed_scale = handling.speed
	continuous_cd = true
	linear_damp = 0.05
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.22
	physics_material_override.friction = 0.85
	collision_layer = 8
	collision_mask = 1 | 4 | 8
	contact_monitor = true
	max_contacts_reported = 6
	var file_name: String = GLB_BY_ID.get(prop_id, "books.glb")
	var data := {"node": BaseballBat.create_visual(), "size": Vector3(0.13, BaseballBat.LENGTH, 0.13)} if prop_id == "baseball_bat" else AssetCatalog.instantiate_centered_glb(file_name, 1.4)
	var visual: Node3D = data["node"]
	footprint_size = Vector3(maxf(data["size"].x, 0.12), maxf(data["size"].y, 0.10), maxf(data["size"].z, 0.12))
	add_child(visual)
	var shape := CollisionShape3D.new()
	collision_shape = shape
	var box := BoxShape3D.new()
	box.size = footprint_size
	shape.shape = box
	shape.position = Vector3(0.0, footprint_size.y * 0.5, 0.0)
	# Visual wrapper is bottom-anchored; keep the body origin at its base.
	visual.position = Vector3.ZERO
	add_child(shape)
	max_health = 90.0 if prop_id == "baseball_bat" else clampf(16.0 + footprint_size.x * footprint_size.z * 30.0, 18.0, 40.0)
	destructible = DestructibleState.new()
	add_child(destructible)
	debris_profile = DestructionProfile.for_item(prop_id)
	destructible.configure(self, visual, footprint_size, prop_id, max_health, debris_profile)
	impact = PropImpact.new()
	add_child(impact)
	impact.setup(self)

func _physics_process(delta: float) -> void:
	impact.tick(delta)
	owner_grace = maxf(0.0, owner_grace - delta)
	if owner_grace <= 0.0 and is_instance_valid(release_owner):
		remove_collision_exception_with(release_owner)
		release_owner = null
	if global_position.y < -2.0:
		var office := get_parent().get_parent()
		var bounds: Rect2 = office.FLOOR_BOUNDS.grow(-0.7)
		global_position = Vector3(clampf(global_position.x, bounds.position.x, bounds.end.x), 1.0, clampf(global_position.z, bounds.position.y, bounds.end.y))
		linear_velocity = Vector3.ZERO
		impact.reset(Vector3.ZERO, 0.4)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if is_instance_valid(impact): impact.capture_contacts(state)

func is_held() -> bool:
	return is_instance_valid(held_by)

func pick_up(holder: Node3D) -> void:
	held_by = holder
	freeze = true
	sleeping = false
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	impact.reset()

func launch_velocity(direction: Vector3, charge := 0.0) -> Vector3:
	var horizontal := Vector3(direction.x, 0, direction.z).normalized()
	var weight_factor := clampf(1.0 / sqrt(mass), 0.50, 1.35)
	return horizontal * lerpf(4.6, 10.5, charge) * weight_factor + Vector3.UP * lerpf(2.1, 4.0, charge)

func _release(origin: Vector3, owner_body: PhysicsBody3D = null) -> void:
	held_by = null
	freeze = false
	sleeping = false
	collision_layer = 8
	collision_mask = 1 | 4 | 8
	global_position = origin
	if is_instance_valid(release_owner): remove_collision_exception_with(release_owner)
	release_owner = owner_body
	owner_grace = 0.30 if owner_body != null else 0.0
	if owner_body != null: add_collision_exception_with(owner_body)

func throw_from(origin: Vector3, direction: Vector3, charge := 0.0, owner_body: PhysicsBody3D = null, launch_override: Variant = null) -> void:
	_release(origin, owner_body)
	linear_velocity = launch_override if launch_override is Vector3 else launch_velocity(direction, charge)
	impact.reset(linear_velocity)
	impact.thrower = weakref(owner_body) if is_instance_valid(owner_body) else null
	angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))

func drop_gently(origin: Vector3, owner_body: PhysicsBody3D = null) -> void:
	_release(origin, owner_body)
	impact.reset(Vector3.ZERO, 0.30)
	impact.thrower = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func volume_query(origin: Vector3, yaw: float, exclusions: Array[RID] = []) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), origin) * collision_shape.transform
	query.collision_mask = 1 | 4 | 8
	var ignored: Array[RID] = [get_rid()]
	ignored.append_array(exclusions)
	query.exclude = ignored
	return query

func fits_transform(pose: Transform3D, exclusions: Array[RID] = []) -> bool:
	var query := volume_query(pose.origin, 0.0, exclusions)
	query.transform = pose * collision_shape.transform
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func fits_at(origin: Vector3, yaw: float, exclusions: Array[RID] = []) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(volume_query(origin, yaw, exclusions), 1).is_empty()

func can_move_to(destination: Vector3, yaw: float, exclusions: Array[RID] = []) -> bool:
	return can_transform_to(Transform3D(Basis(Vector3.UP, yaw), destination), exclusions)

func can_transform_to(destination: Transform3D, exclusions: Array[RID] = []) -> bool:
	var start := global_transform
	var angle := start.basis.get_rotation_quaternion().angle_to(destination.basis.get_rotation_quaternion())
	var steps := maxi(1, ceili(absf(angle) / 0.12))
	var previous := start
	for index in range(1, steps + 1):
		var pose := start.interpolate_with(destination, float(index) / steps)
		if not fits_transform(pose, exclusions): return false
		var query := volume_query(previous.origin, 0.0, exclusions)
		query.transform = Transform3D(pose.basis, previous.origin) * collision_shape.transform
		query.motion = pose.origin - previous.origin
		var fractions := get_world_3d().direct_space_state.cast_motion(query)
		if not fractions.is_empty() and fractions[0] < 0.999: return false
		previous = pose
	return true

func take_damage(amount: float, direction: Vector3 = Vector3.ZERO) -> bool:
	if is_held() or is_queued_for_deletion() or health <= 0.0 or amount <= 0.0:
		return false
	if destructible.apply_damage(amount, direction):
		break_apart(direction)
		return true
	if direction.length_squared() > 0.01:
		apply_central_impulse(direction.normalized() * minf(amount * 0.08, 1.6) + Vector3.UP * 0.5)
	return false

func break_apart(direction: Vector3 = Vector3.ZERO) -> void:
	if is_queued_for_deletion() or destructible.broken: return
	destructible.spawn_fracture(direction)
	queue_free()

