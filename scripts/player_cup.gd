class_name PlayerCup
extends RefCounted

# Water-cup pickup, tabletop placement and floor drop for the player.
# Cup state stays on the player; this module runs the timed hand-off.
var player: OfficePlayer

func _init(p_player: OfficePlayer) -> void:
	player = p_player

# Reuse the character's animated bend and stand transitions: the cup remains on
# the floor during the reach, then follows the hand during the lift and walk.
func pick_up_cup(cup: Node3D) -> void:
	player._cup_action_id += 1
	var action := player._cup_action_id
	player._cup_in_transition = cup
	player._resting_cup = null
	player._cup_support = null
	var on_table := cup.global_position.y > 0.2
	player.busy = 1.1 if on_table else 3.5
	player.play_anim("work_standing" if on_table else "stand_to_sit")
	await player.get_tree().create_timer(0.2 if on_table else 0.8, false).timeout
	if action != player._cup_action_id or not is_instance_valid(cup) or not player.is_inside_tree():
		return
	var start := cup.global_position
	var reach := player.create_tween()
	reach.tween_method(func(weight: float):
		if action == player._cup_action_id and is_instance_valid(cup) and is_instance_valid(player.hand_attachment):
			cup.global_position = start.lerp(player.hand_attachment.global_position + Vector3(0, -0.08, 0), weight)
	, 0.0, 1.0, 0.45)
	await reach.finished
	if action != player._cup_action_id or not is_instance_valid(cup) or not player.is_inside_tree():
		return
	player.cup_in_hand = true
	player._cup_in_transition = null
	cup.global_position = player.hand_attachment.global_position + Vector3(0, -0.10, 0)
	player.play_anim("idle" if on_table else "sit_to_stand")
	if not player.drop_queued:
		player.message.text = "Cup in hand. [%s] puts it down." % OfficeInput.key_name("place")

func find_cup_placement(preferred: FurnitureItem = null) -> Dictionary:
	var best := FurnitureItem.CUP_REACH + 0.001
	var result := {}
	var items := [preferred] if is_instance_valid(preferred) else player.get_tree().get_nodes_in_group("furniture")
	for item in items:
		var spot: Dictionary = item.get_cup_spot(player.global_position)
		if spot.is_empty(): continue
		# Ignore only the supporting table, not walls, other furniture or people.
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.35, spot.position + Vector3.UP * 0.15, 1 | 4, [player.get_rid(), item.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var distance := Vector2(spot.position.x - player.global_position.x, spot.position.z - player.global_position.z).length()
		if distance < best:
			best = distance
			result = spot
	return result

func drop_cup(requested: Dictionary = {}) -> void:
	if not is_instance_valid(player.carried_cup) or player.combat.is_busy() or player.dialogue.is_open or player.equipment.is_active() or player.office.edit_mode != player.office.EditMode.SELECT:
		return
	var placement := find_cup_placement(requested.get("item"))
	var support := placement.get("item") as FurnitureItem
	var on_table := is_instance_valid(support)
	var cup := player.carried_cup
	player._cup_action_id += 1
	var action := player._cup_action_id
	player._cup_in_transition = cup
	player.drop_queued = false
	var was_seated := player.seated
	if not was_seated:
		player.play_anim("work_standing" if on_table else "stand_to_sit")
	player.busy = 1.1 if on_table else (1.2 if was_seated else 3.5)
	player.message.text = "Placing the cup on " + support.item_title + "..." if on_table else "Putting the cup down..."
	var forward := Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
	var drop_pos := player.global_position + forward * 0.65
	# Keep the floor fallback on the reachable side of walls and furniture.
	var origin := player.global_position + Vector3.UP * 0.25
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 0.65, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): drop_pos = hit.position - forward * 0.12
	drop_pos.y = 0.0
	await player.get_tree().create_timer(0.2 if was_seated or on_table else 1.0, false).timeout
	if action != player._cup_action_id or not is_instance_valid(cup) or not player.is_inside_tree(): return
	if on_table:
		placement = find_cup_placement(support) if is_instance_valid(support) else {}
		if placement.is_empty():
			player._cup_in_transition = null
			player.busy = 0.0
			if not was_seated: player.play_anim("idle")
			player.message.text = "The table moved or became blocked. Move closer and try again."
			return
		player.rotation.y = atan2(placement.position.x - player.global_position.x, placement.position.z - player.global_position.z)
	player.cup_in_hand = false
	player.carried_cup = null
	var drop := player.create_tween()
	var drop_start := cup.global_position
	# The editor can delete the table while this animation is running. Capture
	# weak references so the tween never retains a freed scene object.
	var support_ref: WeakRef = weakref(support) if on_table else null
	var cup_ref: WeakRef = weakref(cup)
	drop.tween_method(func(weight: float):
		var placed_cup := cup_ref.get_ref() as Node3D
		var live_support := support_ref.get_ref() as FurnitureItem if support_ref != null else null
		if action == player._cup_action_id and is_instance_valid(placed_cup):
			var destination: Vector3 = live_support.to_global(placement.local_point) if is_instance_valid(live_support) else drop_pos
			placed_cup.global_position = drop_start.lerp(destination, weight)
	, 0.0, 1.0, 0.4)
	await drop.finished
	if action != player._cup_action_id or not is_instance_valid(cup) or not player.is_inside_tree(): return
	cup.add_to_group("player_interactable")
	player._cup_in_transition = null
	on_table = on_table and is_instance_valid(support) and not support.is_queued_for_deletion()
	if on_table:
		player._resting_cup = cup
		player._cup_support = support
		player._cup_surface_point = placement.local_point
	if not was_seated: player.play_anim("idle" if on_table else "sit_to_stand")
	player.message.text = "Cup placed on the table. %s picks it up again." % OfficeInput.key_name("interact") if on_table else "Cup placed down. You can pick it up again."
