class_name BatStrike
extends Node

# Sample the complete barrel through time, even when a frame skips contact.
# Each body receives at most one hit per swing. A blocking wall stops the bat.
var combat: OfficeCombat
var struck: Dictionary = {}
var blocked := false
var blocked_time := 0.0
var shape := CapsuleShape3D.new()

func _init(owner_combat: OfficeCombat) -> void:
	combat = owner_combat
	shape.radius = BaseballBat.RADIUS
	shape.height = 0.88

func begin() -> void:
	struck.clear()
	blocked = false
	blocked_time = 0.0

func tick(from_time: float, to_time: float) -> void:
	var player := combat.actor as OfficePlayer
	if blocked or not is_instance_valid(player) or not combat.has_bat(): return
	var move := combat.current_move()
	var start := float(move.contact) * 0.5
	var finish := float(move.contact) + 0.13
	if to_time < start or from_time > finish: return
	var low := maxf(from_time, start)
	var high := minf(to_time, finish)
	var steps := maxi(1, ceili((high - low) / BaseballBat.SAMPLE_TIME))
	for i in range(steps + 1):
		var time := lerpf(low, high, float(i) / steps)
		var pose := player.global_transform * BaseballBat.local_pose(combat.move_id, time)
		var prior := player.global_transform * BaseballBat.local_pose(combat.move_id, time - BaseballBat.SAMPLE_TIME)
		var point := pose * Vector3(0, 0.78, 0)
		var velocity := (point - prior * Vector3(0, 0.78, 0)) / BaseballBat.SAMPLE_TIME
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = pose.translated_local(Vector3(0, 0.57, 0))
		query.collision_mask = 1 | 4 | 8
		query.exclude = [player.get_rid(), player.held_prop.get_rid()]
		var hits := player.get_world_3d().direct_space_state.intersect_shape(query, 24)
		# Test obstructions before people so query order cannot hit through walls.
		for hit in hits:
			var body: Object = hit.collider
			if body is StaticBody3D and not body is FurnitureItem:
				blocked = true
				blocked_time = time
				combat._spawn_contact(point, "bat", "Blocked")
				return
		for hit in hits:
			_apply_contact(hit.collider, point, velocity)
		# Seated workers have disabled movement colliders, but remain hittable.
		for node in player.get_tree().get_nodes_in_group("workers"):
			var worker := node as OfficeWorker
			if worker == null or not worker.is_seated: continue
			var center := worker.global_position + Vector3.UP * 0.85
			var closest := Geometry3D.get_closest_point_to_segment(center, pose * Vector3(0, 0.20, 0), pose * Vector3(0, BaseballBat.LENGTH, 0))
			if center.distance_to(closest) < 0.34 + BaseballBat.RADIUS:
				_apply_contact(worker, closest, velocity)

func _apply_contact(body: Object, point: Vector3, velocity: Vector3) -> void:
	if not is_instance_valid(body) or not body is CollisionObject3D or body.is_queued_for_deletion(): return
	var id := body.get_instance_id()
	if struck.has(id): return
	if not combat._environment_visible(body, point): return
	var move := combat.current_move()
	var direction := velocity.normalized()
	if velocity.length_squared() < 0.01: direction = combat.actor.global_basis.z
	var power := clampf(velocity.length() / 12.0, 0.65, 1.35)
	var hit := false
	if body is OfficeWorker:
		hit = body.combat.receive_bat_hit(combat.actor, move, velocity, point)
	elif body is FurnitureItem and body.breakable and not body.is_preview:
		body.take_damage(float(move.damage) * power * 1.6, direction, point)
		hit = true
	elif body is PhysicsProp and not body.is_held():
		body.take_damage(float(move.damage) * power * 1.2, direction)
		hit = true
	if hit:
		struck[id] = true
		combat.last_attack_hit = true
		combat._spawn_contact(point, "bat", "CRACK!" if move.heavy else "WHACK!")
		OfficeAudio.play_at(combat.actor.get_tree(), "wood_hit", point)
