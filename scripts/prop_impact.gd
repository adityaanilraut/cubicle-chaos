class_name PropImpact
extends Node

# Samples contacts in the body's direct-state callback, but resolves gameplay
# outside the physics flush. Per-pair cooldowns suppress multi-point contacts.
const MIN_SPEED := 2.0
const CONTACT_COOLDOWN := 0.22
var prop: PhysicsProp
var previous_velocity := Vector3.ZERO
var cooldowns: Dictionary = {}
var quiet_time := 0.0
var last_damage := 0.0
var impact_count := 0
var thrower: WeakRef

func setup(owner_prop: PhysicsProp) -> void:
	prop = owner_prop

func reset(velocity := Vector3.ZERO, grace := 0.0) -> void:
	previous_velocity = velocity
	quiet_time = grace
	cooldowns.clear()

func tick(delta: float) -> void:
	quiet_time = maxf(0, quiet_time - delta)
	for id in cooldowns.keys():
		cooldowns[id] -= delta
		if cooldowns[id] <= 0.0: cooldowns.erase(id)

func capture_contacts(state: PhysicsDirectBodyState3D) -> void:
	if prop.is_held() or prop.is_queued_for_deletion(): return
	var incoming := previous_velocity
	previous_velocity = state.linear_velocity
	if quiet_time > 0: return
	for index in range(state.get_contact_count()):
		var body := state.get_contact_collider_object(index) as Node
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var other_velocity := state.get_contact_collider_velocity_at_position(index)
		var other_history := other_velocity
		if body is PhysicsProp: other_history = body.impact.previous_velocity
		elif body is OfficeWorker: other_history = body.velocity
		# Godot's contact normals and positions are world-space values despite
		# the historical "local" method names (both Jolt and Godot Physics).
		var normal := state.get_contact_local_normal(index)
		var relative := incoming - other_velocity
		var contact_relative := state.get_contact_local_velocity_at_position(index) - other_velocity
		var historical_relative := incoming - other_history
		var speed := maxf(maxf(-relative.dot(normal), -contact_relative.dot(normal)), -historical_relative.dot(normal))
		queue_contact(body, speed, -normal, state.get_contact_collider_position(index))

func queue_contact(body: Node, speed: float, direction: Vector3, point: Vector3) -> bool:
	if quiet_time > 0 or speed < MIN_SPEED or prop.is_held() or prop.is_queued_for_deletion() or not is_instance_valid(body) or body.is_queued_for_deletion(): return false
	if body == prop.release_owner and prop.owner_grace > 0: return false
	var id := body.get_instance_id()
	if cooldowns.has(id): return false
	if body is PhysicsProp:
		if body.is_held() or body.impact.cooldowns.has(prop.get_instance_id()): return false
		body.impact.cooldowns[prop.get_instance_id()] = CONTACT_COOLDOWN
	cooldowns[id] = CONTACT_COOLDOWN
	_resolve_contact.call_deferred(weakref(body), speed, direction, point)
	return true

func damage_for(speed: float, resistance := 1.0, other_mass := 0.0) -> float:
	if speed < MIN_SPEED: return 0.0
	# Reduced mass for two moving props; an immovable surface absorbs the
	# source's full effective mass. The multiplier is game tuning, not a unit.
	var effective_mass := prop.mass if other_mass <= 0.0 else prop.mass * other_mass / (prop.mass + other_mass)
	var energy := 0.5 * effective_mass * maxf(0.0, speed * speed - MIN_SPEED * MIN_SPEED)
	return clampf(energy * 0.85 / maxf(resistance, 0.1), 0.0, 95.0)

func _resolve_contact(body_ref: WeakRef, speed: float, direction: Vector3, point: Vector3) -> void:
	var body := body_ref.get_ref() as Node
	if not is_instance_valid(prop) or prop.is_held() or prop.is_queued_for_deletion() or not is_instance_valid(body) or body.is_queued_for_deletion(): return
	var other_mass: float = body.mass if body is PhysicsProp else 0.0
	var resistance := 1.0
	if body is FurnitureItem and is_instance_valid(body.destructible): resistance = body.destructible.profile.resistance
	elif body is PhysicsProp: resistance = body.destructible.profile.resistance
	var damage := damage_for(speed, resistance, other_mass)
	if damage <= 0.0: return
	impact_count += 1
	last_damage = damage
	if body is FurnitureItem:
		body.take_damage(damage, direction, point)
	elif body is PhysicsProp:
		body.take_damage(damage, direction)
	elif body is OfficeWorker:
		var source := thrower.get_ref() as OfficeWorker if thrower != null else null
		# Soft objects remain playful; heavy solid objects can topple a worker.
		var softness := 0.25 if prop.destructible.profile.material_id == "fabric" else 1.0
		body.combat.receive_prop_hit(damage * 0.42 * softness, damage * 1.4 * softness, direction, source)
	# Contact also damages the projectile, including wall/floor impacts.
	# Two dynamic bodies must receive symmetric energy accounting regardless
	# of which body's direct-state callback queues their shared contact first.
	var self_factor := 1.0 if body is PhysicsProp else 0.48
	var self_damage := damage_for(speed, prop.destructible.profile.resistance, other_mass) * self_factor
	prop.take_damage(self_damage, -direction)
