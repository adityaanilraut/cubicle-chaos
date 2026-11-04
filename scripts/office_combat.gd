class_name OfficeCombat
extends RefCounted

enum Phase { READY, ATTACK, STAGGER, FALLEN, GETTING_UP, FLEEING }

const IMPACT_SCENE := preload("res://scenes/combat_impact.tscn")
const PUNCH_REACH := 1.20
const KICK_REACH := 1.65
const FALL_TIME := 2.0
const FALL_LANDING_TIME := 0.68
const GET_UP_TIME := 1.8
const LOCK_DISTANCE := 7.0
const FLEE_SPEED := 4.6
const EXIT_POINT := OfficeArrival.ENTRANCE + Vector3(0.65, 0, 0)

var actor: OfficeWorker
var target: OfficeWorker
var strike_target: OfficeWorker
var phase := Phase.READY
var kind := "punch"
var move_id := "cross"
var combo_step := 0
var combo_window := 0.0
var stance_time := 0.0
var stance_style := "Karate"
var buffered_fight := 0.0
var buffered_kind := "auto"
const INPUT_BUFFER := 0.28
const COMBO_WINDOW := 1.6
const STANCE_TIME := 2.4
const STRIKE_ACTIVE_TIME := 0.05
var phase_time := 0.0
var cooldown := 0.0
var invulnerable := 0.0
var balance := 100.0
var health := 100.0
var quiet_time := 0.0
var anger_time := 0.0
var attack_count := 0
var contact_done := false
var last_attack_hit := false
var knockback := Vector3.ZERO
var pose: CombatPose
var trail: CombatTrail
var bat_strike: BatStrike
var hit_motion: HitMotion
var is_player := false
var player_knockdowns := 0
var recovery_attacker: OfficeWorker
var revenge_pending := false
var hit_height := 1.35
var hit_side := 1.0
var _escape_repath := 0.0
var _escape_last_position := Vector3.ZERO
var _escape_stuck := 0.0
var departure_name := ""
var departure_notice_time := 0.0

func setup(character: OfficeWorker) -> void:
	actor = character
	actor.add_to_group("combatants")
	pose = CombatPose.new()
	pose.combat = self
	var skeleton := actor.rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.add_child(pose)
	trail = CombatTrail.new()
	trail.combat = self
	actor.add_child(trail)
	bat_strike = BatStrike.new(self)
	actor.add_child(bat_strike)
	hit_motion = HitMotion.new()
	actor.add_child(hit_motion)
	hit_motion.setup(actor)

func is_down() -> bool:
	return phase == Phase.FALLEN or phase == Phase.GETTING_UP

func is_busy() -> bool:
	return phase != Phase.READY

func is_engaged() -> bool:
	return is_busy() or is_instance_valid(target)

func reset() -> void:
	if is_instance_valid(hit_motion): hit_motion.stop()
	phase = Phase.READY
	phase_time = 0.0
	target = null
	strike_target = null
	recovery_attacker = null
	revenge_pending = false
	buffered_fight = 0.0
	cooldown = 0.0
	invulnerable = 0.0
	combo_window = 0.0
	combo_step = 0
	stance_time = 0.0
	quiet_time = 0.0
	anger_time = 0.0
	knockback = Vector3.ZERO
	departure_notice_time = 0.0
	trail.points.clear()
	trail.ages.clear()

func status() -> String:
	match phase:
		Phase.ATTACK: return String(current_move().label)
		Phase.STAGGER: return "Staggered"
		Phase.FALLEN: return "Knocked down"
		Phase.GETTING_UP: return "Getting up"
		Phase.FLEEING: return "Leaving because of you"
	if revenge_pending: return "Counterattack!"
	return "Fighting back" if is_instance_valid(target) else "Ready"

func locked_target() -> OfficeWorker:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		target = null
	elif target.combat.phase == Phase.FLEEING or actor.global_position.distance_to(target.global_position) > LOCK_DISTANCE:
		target = null
	return target

func face_locked_target(delta: float) -> bool:
	if not is_player or not is_instance_valid(locked_target()): return false
	var direction := target.global_position - actor.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.01:
		actor.rotation.y = lerp_angle(actor.rotation.y, atan2(direction.x, direction.z), minf(delta * 12.0, 1.0))
	return true

func _in_strike_arc(offset: Vector3, facing: Vector3, other: OfficeWorker) -> bool:
	# Check the target's body, not only its center. At close range a shoulder
	# can be in the strike arc even when the center is just outside it.
	var distance := offset.length()
	if distance <= 0.05: return true
	var radius := 0.0
	if is_instance_valid(other.collision_shape) and other.collision_shape.shape is CapsuleShape3D:
		radius = (other.collision_shape.shape as CapsuleShape3D).radius
	var allowance := asin(clampf(radius / distance, 0.0, 1.0))
	return facing.dot(offset / distance) >= cos(acos(0.40) + allowance)

func can_contact(other: OfficeWorker, reach: float, check_facing := true) -> bool:
	if not is_instance_valid(other) or other.is_queued_for_deletion() or other == actor or other.combat.is_down() or other.combat.phase == Phase.FLEEING:
		return false
	var offset := other.global_position - actor.global_position
	offset.y = 0.0
	if offset.length() > reach:
		return false
	if check_facing and not _in_strike_arc(offset, actor.global_basis.z, other):
		return false
	# Static furniture/walls and other people block the contact line.
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.05, other.global_position + Vector3.UP * 1.05, 1 | 4, [actor.get_rid(), other.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func find_target(reach: float, check_facing := false) -> OfficeWorker:
	# A bystander cannot steal an ongoing fight, even while the opponent is down
	# or temporarily beyond striking distance. Retreat releases the lock.
	if is_player and is_instance_valid(locked_target()):
		return target if can_contact(target, reach, check_facing) else null
	var closest: OfficeWorker
	var distance := INF
	for node in actor.get_tree().get_nodes_in_group("combatants"):
		var other := node as OfficeWorker
		if not can_contact(other, reach, check_facing):
			continue
		var current := actor.global_position.distance_to(other.global_position)
		if is_player:
			var direction := other.global_position - actor.global_position
			direction.y = 0.0
			var facing := actor.global_basis.z
			var player := actor as OfficePlayer
			if is_instance_valid(player.mouse_controls) and player.mouse_controls.aiming:
				var aim := player.mouse_controls.aim_point - actor.global_position
				aim.y = 0.0
				if aim.length_squared() > 0.01: facing = aim.normalized()
			if not _in_strike_arc(direction, facing, other): continue
			# Prefer the direction of aim, then distance.
			current += (1.0 - direction.normalized().dot(facing)) * 0.8
		if current < distance:
			distance = current
			closest = other
	return closest

func current_move() -> Dictionary:
	return CombatMoves.get_move(move_id)

func has_bat() -> bool:
	return is_player and is_instance_valid((actor as OfficePlayer).held_prop) and (actor as OfficePlayer).held_prop.prop_id == "baseball_bat"

func has_fighting_pose() -> bool:
	if phase == Phase.FLEEING: return false
	if is_player:
		var player := actor as OfficePlayer
		if player.seated or player.busy > 0.0 or is_instance_valid(player.carried_cup) or is_instance_valid(player.grabbed_furniture) or (is_instance_valid(player.held_prop) and not has_bat()) or player.equipment.is_active() or player.dialogue.is_open:
			return false
	if is_engaged(): return true
	if stance_time <= 0.0: return false
	if is_player: return true
	return actor.state == OfficeWorker.State.IDLE and not actor.is_seated

func request_fight(requested_kind := "auto") -> bool:
	if start_attack(requested_kind):
		return true
	# One late tap is remembered; early mashing cannot queue a whole fight.
	var remaining := maxf(cooldown, float(current_move().duration) - phase_time) if phase == Phase.ATTACK else cooldown
	if phase in [Phase.ATTACK, Phase.READY] and remaining <= INPUT_BUFFER:
		# Keep the input through the first eligible tick, including a long frame.
		buffered_fight = remaining + INPUT_BUFFER
		buffered_kind = requested_kind
		return true
	return false

func start_attack(attack_kind: String) -> bool:
	if is_busy() or cooldown > 0.0:
		return false
	if attack_kind.begins_with("bat_") and not has_bat(): return false
	var automatic := attack_kind in ["auto", "light", "heavy"]
	var selected := CombatMoves.resolve_id(attack_kind)
	if not automatic and CombatMoves.get_move(selected).is_empty():
		return false
	var opponent: OfficeWorker
	var search_reach := (1.85 if has_bat() else (1.25 if attack_kind == "light" else KICK_REACH)) if automatic else float(CombatMoves.get_move(selected).reach)
	if is_instance_valid(locked_target()):
		opponent = target
	else:
		opponent = find_target(search_reach)
	if automatic:
		if combo_window <= 0.0:
			combo_step = 0
		var sequence: Array = CombatMoves.SEQUENCE
		if attack_kind == "light": sequence = CombatMoves.LIGHT_SEQUENCE
		if attack_kind == "heavy": sequence = CombatMoves.HEAVY_SEQUENCE
		selected = sequence[combo_step % sequence.size()]
		# Choose an appropriate kick when the next hand strike cannot reach.
		if attack_kind == "auto" and is_instance_valid(opponent) and actor.global_position.distance_to(opponent.global_position) > float(CombatMoves.get_move(selected).reach):
			selected = CombatMoves.LONG_RANGE[combo_step % CombatMoves.LONG_RANGE.size()]
		if has_bat(): selected = "bat_overhead" if attack_kind == "heavy" else CombatMoves.BAT_LIGHT_SEQUENCE[combo_step % CombatMoves.BAT_LIGHT_SEQUENCE.size()]
		combo_step += 1
	move_id = selected
	var move := current_move()
	kind = move.family
	stance_style = move.style
	strike_target = opponent
	if is_instance_valid(opponent):
		target = opponent
		var direction := opponent.global_position - actor.global_position
		actor.rotation.y = atan2(direction.x, direction.z)
	if kind == "bat":
		var player := actor as OfficePlayer
		player.mouse_controls.cancel()
		player.prop_handling.reset()
		bat_strike.begin()
	else:
		actor.interrupt_for_combat()
	phase = Phase.ATTACK
	phase_time = 0.0
	cooldown = move.cooldown
	combo_window = cooldown + COMBO_WINDOW
	stance_time = cooldown + STANCE_TIME
	quiet_time = 0.0
	buffered_fight = 0.0
	contact_done = false
	last_attack_hit = false
	actor.play_anim("idle")
	if not is_player:
		actor._update_label()
	return true

func _resolve_contact() -> bool:
	# Retry during the extended pose, but apply damage only once per strike.
	if not is_instance_valid(strike_target):
		strike_target = find_target(float(current_move().reach), true)
		if not is_instance_valid(strike_target):
			return false
	var victim := strike_target
	if not can_contact(victim, float(current_move().reach), true):
		return false
	last_attack_hit = victim.combat.receive_hit(actor, move_id)
	if last_attack_hit:
		revenge_pending = false
		OfficeAudio.play_at(actor.get_tree(), "kick" if kind == "kick" else "punch")
		_spawn_contact(victim.global_position.lerp(actor.global_position, 0.22) + Vector3.UP * float(current_move().height), kind, current_move().label)
	return last_attack_hit

func _spawn_contact(point: Vector3, contact_kind: String, label: String) -> void:
	var effect := IMPACT_SCENE.instantiate() as CombatImpact
	effect.kind = contact_kind
	effect.move_label = label
	effect.top_level = true
	actor.add_child(effect)
	effect.global_position = point
	effect.global_rotation.y = actor.global_rotation.y

func _environment_visible(body: CollisionObject3D, point: Vector3) -> bool:
	# Test the path to the actual object, ignoring only the attacker and candidate.
	var origin := actor.global_position + Vector3.UP * 1.05
	var ray := PhysicsRayQueryParameters3D.create(origin, point, 1 | 4 | 8, [actor.get_rid(), body.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _hit_environment() -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return
	var reach := float(current_move().reach)
	var facing: Vector3 = actor.global_basis.z
	var best: CollisionObject3D
	var best_distance := INF
	for node in actor.get_tree().get_nodes_in_group("furniture"):
		var item := node as FurnitureItem
		if item == null or not item.breakable or item.is_preview: continue
		var offset := item.global_position - actor.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.01 or distance > reach + item.footprint_size.length() * 0.35: continue
		if offset.normalized().dot(facing) < 0.35 or distance >= best_distance: continue
		var point := item.global_position + Vector3.UP * minf(1.05, maxf(0.1, item.footprint_size.y * 0.5))
		if _environment_visible(item, point):
			best = item
			best_distance = distance
	for node in actor.get_tree().get_nodes_in_group("physics_props"):
		var prop := node as PhysicsProp
		if prop == null or prop.is_held(): continue
		var offset := prop.global_position - actor.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.01 or distance > reach or distance >= best_distance: continue
		if offset.normalized().dot(facing) < 0.3 or not _environment_visible(prop, prop.global_position): continue
		best = prop
		best_distance = distance
	if best is FurnitureItem:
		(best as FurnitureItem).take_damage(float(current_move().damage) * 0.7, facing, actor.global_position)
	elif best is PhysicsProp:
		(best as PhysicsProp).take_damage(float(current_move().damage) * 0.5, facing)

func receive_hit(attacker: OfficeWorker, attack_kind: String) -> bool:
	var incoming := CombatMoves.get_move(attack_kind)
	if incoming.is_empty() or not is_instance_valid(attacker): return false
	var direction := actor.global_position - attacker.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001: direction = attacker.global_basis.z
	kind = incoming.family
	hit_height = float(incoming.height)
	hit_side = 1.0 if incoming.side == "Left" else -1.0
	return _apply_hit(float(incoming.damage), float(incoming.balance), float(incoming.push), direction, attacker, 0.30)

func receive_bat_hit(source: OfficeWorker, move: Dictionary, velocity: Vector3, point: Vector3) -> bool:
	if not is_instance_valid(source) or move.is_empty() or move.get("family", "") != "bat": return false
	var relative := velocity - actor.velocity
	var speed := clampf(relative.length(), 5.0, 24.0)
	var power := clampf(speed / 12.0, 0.65, 1.35)
	hit_height = clampf(point.y - actor.global_position.y, 0.3, 1.65)
	hit_side = 1.0 if source.global_basis.x.dot(relative) > 0.0 else -1.0
	if not _apply_hit(float(move.damage) * power, float(move.balance) * power, 0.0, relative, source, 0.30): return false
	# Effective swing mass includes the two-handed grip; reduced mass limits
	# transfer into the 72 kg body. J = (1 + restitution) * reduced_mass * v.
	var effective_mass := 9.5 if move.heavy else 6.5
	var reduced_mass := effective_mass * hit_motion.mass / (effective_mass + hit_motion.mass)
	var horizontal := Vector3(relative.x, 0, relative.z).normalized()
	if horizontal.length_squared() < 0.01: horizontal = source.global_basis.z
	var impulse := horizontal * clampf(1.15 * reduced_mass * speed, 45.0, 280.0)
	if is_down(): impulse.y = 34.0
	hit_motion.launch(impulse, point, source)
	return true

# Props share interruption, fall, recovery and retaliation with melee combat.
func receive_prop_hit(damage: float, balance_damage: float, direction: Vector3, source: OfficeWorker = null) -> bool:
	hit_height = 1.0
	hit_side = 1.0
	var hit := _apply_hit(damage, balance_damage, clampf(balance_damage * 0.055, 0.6, 3.6), direction, source, 0.35)
	if hit:
		_spawn_contact(actor.global_position + Vector3.UP, "prop", "Impact")
	return hit

func _apply_hit(damage: float, balance_damage: float, push: float, direction: Vector3, source: OfficeWorker, protection: float) -> bool:
	if invulnerable > 0.0 or is_down() or phase == Phase.FLEEING or damage <= 0.0: return false
	if hit_motion.running: hit_motion.stop()
	actor.interrupt_for_combat()
	health = maxf(0, health - damage)
	balance -= balance_damage
	buffered_fight = 0.0
	combo_window = 0.0
	combo_step = 0
	stance_time = STANCE_TIME
	quiet_time = 0.0
	invulnerable = protection
	phase_time = 0.0
	var horizontal := Vector3(direction.x, 0, direction.z).normalized()
	if horizontal.length_squared() < 0.01: horizontal = actor.global_basis.z
	actor.rotation.y = atan2(-horizontal.x, -horizontal.z)
	knockback = horizontal * push
	if is_instance_valid(source) and source != actor:
		if not is_player or not is_instance_valid(locked_target()): target = source
		if not is_player: anger_time = 12.0
	if balance <= 0 or health <= 0:
		pose.begin_fall()
		phase = Phase.FALLEN
		recovery_attacker = source
		if not is_player and is_instance_valid(source) and source.combat.is_player:
			player_knockdowns += 1
	else:
		phase = Phase.STAGGER
		if not is_player and is_instance_valid(source) and source != actor:
			target = source
			anger_time = 8
			cooldown = maxf(cooldown, 0.85)
	actor.play_anim("idle")
	actor.show_social_speech("💥 Ouch!" if health > 0.0 else "💥 Down!")
	OfficeAudio.play_at(actor.get_tree(), "ouch", actor.global_position)
	if not is_player: actor._update_label()
	return true

# Returns true while combat owns the actor's movement and normal routine.
func tick(delta: float) -> bool:
	departure_notice_time = maxf(0.0, departure_notice_time - delta)
	if is_player:
		locked_target()
		if not is_busy() and not has_fighting_pose(): target = null
		if is_instance_valid(target) and quiet_time > 6.0 and not target.combat.is_down() and target.combat.target != actor:
			target = null
	cooldown = maxf(0.0, cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	combo_window = maxf(0.0, combo_window - delta)
	stance_time = maxf(0.0, stance_time - delta)
	quiet_time += delta
	if quiet_time > 4.0 and not is_busy():
		balance = minf(100.0, balance + delta * 18.0)
		health = minf(100.0, health + delta * 12.0)
	var previous_time := phase_time
	phase_time += delta
	if phase == Phase.FLEEING:
		_process_escape(delta)
		return true
	if phase == Phase.ATTACK:
		actor._stop_walking_velocity()
		var contact_time := float(current_move().contact)
		if kind == "bat":
			bat_strike.tick(previous_time, phase_time)
			if has_bat(): (actor as OfficePlayer).held_prop.global_transform = BaseballBat.held_pose(actor as OfficePlayer)
		elif not contact_done and phase_time >= contact_time:
			contact_done = _resolve_contact()
			if not contact_done and phase_time >= contact_time + STRIKE_ACTIVE_TIME:
				contact_done = true
				_hit_environment()
		if phase_time >= float(current_move().duration):
			phase = Phase.READY
			actor.play_anim("idle")
		_tick_buffer(delta)
		return true
	if phase == Phase.STAGGER or phase == Phase.FALLEN:
		if hit_motion.running:
			hit_motion.sync_actor()
		else:
			actor.nav_agent.velocity = Vector3.ZERO
			actor.velocity = knockback
			actor.move_and_slide()
			actor.global_position.y = 0.0
			knockback = knockback.move_toward(Vector3.ZERO, delta * 9.0)
		if phase == Phase.STAGGER and phase_time >= 0.38:
			hit_motion.stop()
			phase = Phase.READY
		elif phase == Phase.FALLEN and phase_time >= FALL_TIME:
			# NPC recovery shares the same fair animation lane as desk exits.
			# Remain in the still floor pose until the slot is actually granted.
			if is_player or not is_instance_valid(actor.routines) or actor.routines.request_stand(actor):
				hit_motion.stop()
				phase = Phase.GETTING_UP
				phase_time = 0.0
				knockback = Vector3.ZERO
		return true
	if phase == Phase.GETTING_UP:
		actor._stop_walking_velocity()
		if phase_time >= GET_UP_TIME:
			if not is_player and is_instance_valid(actor.routines):
				actor.routines.finish_stand(actor)
			phase = Phase.READY
			pose.finish_recovery()
			balance = 100.0
			health = maxf(health, 60.0)
			invulnerable = 1.2
			actor._enter_idle(1.5)
			if not is_player and player_knockdowns >= 2:
				begin_escape()
			elif not is_player and is_instance_valid(recovery_attacker):
				target = recovery_attacker
				anger_time = 20.0
				revenge_pending = true
				cooldown = 0.22
				combo_step = 0
				combo_window = 0.0
				actor.show_social_speech("🥊 Enough!")
				actor._update_label()
		return true
	if _tick_buffer(delta):
		return true
	if not is_player and is_instance_valid(target):
		anger_time -= delta
		if anger_time <= 0.0 or target.is_queued_for_deletion() or target.combat.phase == Phase.FLEEING or actor.global_position.distance_to(target.global_position) > LOCK_DISTANCE:
			target = null
			revenge_pending = false
			actor._enter_idle(1.5)
			return false
		if target.combat.is_down():
			actor._stop_walking_velocity()
			actor.play_anim("idle")
			return true
		_process_retaliation(delta)
		return true
	return false

func _tick_buffer(delta: float) -> bool:
	if buffered_fight <= 0.0:
		return false
	if phase == Phase.READY and cooldown <= 0.0:
		buffered_fight = 0.0
		return start_attack(buffered_kind)
	buffered_fight = maxf(0.0, buffered_fight - delta)
	return false

func _process_retaliation(delta: float) -> void:
	var direction := target.global_position - actor.global_position
	direction.y = 0.0
	actor.rotation.y = lerp_angle(actor.rotation.y, atan2(direction.x, direction.z), minf(delta * 10.0, 1.0))
	var reach := KICK_REACH
	if can_contact(target, reach - 0.08, false):
		actor._stop_walking_velocity()
		actor.play_anim("idle")
		var response := "front_kick" if direction.length() > 1.12 else "cross"
		if start_attack(response if revenge_pending else "auto"):
			attack_count += 1
		return
	# Use the office navigation map to pursue around desks, never through walls.
	var nav_map := actor.nav_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		actor._stop_walking_velocity()
		return
	actor.nav_agent.target_position = target.global_position
	var next := actor.nav_agent.get_next_path_position() - actor.global_position
	next.y = 0.0
	actor.velocity = next.normalized() * minf(1.65, next.length() / maxf(delta, 0.001))
	actor.nav_agent.velocity = actor.velocity
	actor.move_and_slide()
	actor.global_position.y = 0.0
	actor.play_anim("walk" if actor.velocity.length_squared() > 0.01 else "idle")

func begin_escape() -> void:
	if is_player: return
	hit_motion.stop()
	actor.interrupt_for_combat()
	phase = Phase.FLEEING
	phase_time = 0.0
	target = null
	strike_target = null
	buffered_fight = 0.0
	stance_time = 0.0
	revenge_pending = false
	_escape_repath = 0.0
	_escape_stuck = 0.0
	_escape_last_position = actor.global_position
	actor.nav_agent.avoidance_enabled = false
	actor.show_social_speech("😨 Leaving!")
	actor._update_label()
	# Let the player see the retreat without leaving an attack queued for a
	# different coworker. The fleeing worker is no longer a combat target.
	if is_instance_valid(recovery_attacker) and recovery_attacker.combat.is_player:
		recovery_attacker.combat.departure_name = actor.worker_name
		recovery_attacker.combat.departure_notice_time = 4.0
		if recovery_attacker.combat.target == actor:
			recovery_attacker.combat.target = null
			recovery_attacker.combat.buffered_fight = 0.0

func _process_escape(delta: float) -> void:
	var remaining := EXIT_POINT - actor.global_position
	remaining.y = 0.0
	if remaining.length() < 0.35:
		_finish_escape()
		return
	var nav_map := actor.nav_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		actor._stop_walking_velocity()
		return
	_escape_repath -= delta
	if _escape_repath <= 0.0:
		actor.nav_agent.target_position = EXIT_POINT
		_escape_repath = 0.8
	var direction := actor.nav_agent.get_next_path_position() - actor.global_position
	direction.y = 0.0
	# A temporarily blocked exit never teleports a coworker through furniture.
	if direction.length_squared() > 0.0025:
		actor.rotation.y = lerp_angle(actor.rotation.y, atan2(direction.x, direction.z), minf(delta * 14.0, 1.0))
		actor.velocity = direction.normalized() * minf(FLEE_SPEED, direction.length() / maxf(delta, 0.001))
	else:
		actor.velocity = Vector3.ZERO
	actor.nav_agent.velocity = actor.velocity
	actor.move_and_slide()
	actor.global_position.y = 0.0
	var moved := actor.global_position.distance_squared_to(_escape_last_position) > 0.000004
	_escape_stuck = 0.0 if moved else _escape_stuck + delta
	_escape_last_position = actor.global_position
	actor.play_anim("flee" if moved else "idle")
	if _escape_stuck > 1.5:
		_escape_repath = 0.0
		_escape_stuck = 0.0

func _finish_escape() -> void:
	actor._release_routine()
	for item in actor.get_tree().get_nodes_in_group("furniture"):
		if item is FurnitureItem:
			if item.owner_worker == actor: item.owner_worker = null
			if item.reserved_by == actor: item.reserved_by = null
	actor.remove_from_group("combatants")
	actor.remove_from_group("workers")
	actor.queue_free()
