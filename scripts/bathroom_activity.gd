class_name BathroomActivity
extends RefCounted

# The player keeps their body collider: only the fixture being used is ignored.
# All movement and effects share the equipment clock, including pause/cancel.
var player: OfficePlayer
var item: FurnitureItem
var action := ""
var entry := Vector3.ZERO
var anchor := Vector3.ZERO
var entry_yaw := 0.0
var effects: Node3D
var drops: Array[MeshInstance3D] = []
var steam: Array[MeshInstance3D] = []
var ripples: Array[MeshInstance3D] = []
var _announced := false

static func handles(id: String) -> bool:
	return id in ["eq_toilet", "eq_shower", "eq_wash_hands"]

static func use_position(fixture: FurnitureItem) -> Vector3:
	match fixture.equipment_group:
		"toilet": return fixture.to_global(Vector3(0, 0, 0.10))
		"shower": return fixture.to_global(Vector3(0, 0.055, 0.04))
	return fixture.get_interact_world_pos()

static func entry_issue(actor: OfficePlayer, fixture: FurnitureItem) -> String:
	var local := fixture.to_local(actor.global_position)
	if local.z < fixture.footprint_size.z * 0.5 + 0.05 or absf(local.x) > fixture.footprint_size.x * 0.5 + 0.55:
		return "Approach the front of " + fixture.item_title + "."
	if not clear_path(actor, fixture, actor.global_position, use_position(fixture)):
		return "There is not enough space to use this fixture."
	return ""

static func clear_path(actor: OfficePlayer, fixture: FurnitureItem, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.collision_shape.shape
	query.transform = actor.collision_shape.global_transform
	query.transform.origin += from - actor.global_position + Vector3.UP * 0.015
	query.motion = to - from
	query.collision_mask = 1 | 4
	var exclusions: Array[RID] = [actor.get_rid()]
	if is_instance_valid(fixture): exclusions.append(fixture.get_rid())
	query.exclude = exclusions
	var space := actor.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	var sweep := space.cast_motion(query)
	return sweep[0] >= 0.999

func begin(actor: OfficePlayer, fixture: FurnitureItem, id: String) -> void:
	player = actor
	item = fixture
	action = id
	entry = actor.global_position
	entry_yaw = actor.rotation.y
	anchor = use_position(fixture)
	actor.add_collision_exception_with(fixture)
	_announced = false
	_make_effects()
	update(0, 10)

func update(elapsed: float, remaining: float) -> void:
	var enter_time := 0.8
	var exit_time := 2.3 if action == "eq_toilet" else 0.9
	var entering := elapsed < enter_time
	var exiting := remaining < exit_time
	var position := entry.lerp(anchor, smoothstep(0, enter_time, elapsed))
	if exiting:
		position = anchor.lerp(_exit_position(), smoothstep(exit_time, 0, remaining))
	# Check again during entry/exit: a thrown prop or coworker may block the route.
	if not position.is_equal_approx(player.global_position) and not clear_path(player, item, player.global_position, position):
		player.equipment.cancel("The way is blocked. Activity cancelled.")
		return
	player.global_position = position
	var yaw := item.global_rotation.y if action == "eq_toilet" else item.global_rotation.y + PI
	player.rotation.y = lerp_angle(entry_yaw, yaw, smoothstep(0, enter_time, elapsed))
	match action:
		"eq_toilet":
			player.play_anim("sit_to_stand" if exiting else "stand_to_sit" if elapsed < 2.3 else "toilet_idle")
			if elapsed >= 2.3 and not _announced:
				player.show_social_speech("💩 Ahh!")
				_announced = true
		"eq_shower": player.play_anim("walk" if entering or exiting else "shower")
		"eq_wash_hands": player.play_anim("walk" if entering or exiting else "wash_hands")
	if not entering and not exiting and not _announced:
		player.show_social_speech("🚿 Ahh!" if action == "eq_shower" else "🧼 Wash!")
		_announced = true
	var water_on := not entering and not exiting and action != "eq_toilet"
	effects.visible = water_on
	_update_water(elapsed)

func _exit_position() -> Vector3:
	if clear_path(player, item, anchor, entry): return entry
	# Prefer a nearby point on the same front side if the original spot is occupied.
	for offset in [Vector3(0.65, 0, 0), Vector3(-0.65, 0, 0), Vector3(0, 0, 0.65)]:
		var point: Vector3 = entry + item.global_basis * offset if is_instance_valid(item) else entry + offset
		if player.office.FLOOR_BOUNDS.grow(-0.3).has_point(Vector2(point.x, point.z)) and clear_path(player, item, anchor, point): return point
	return entry

func finish() -> void:
	if is_instance_valid(player) and player.is_inside_tree() and not action.is_empty():
		player.global_position = _exit_position()
		player.rotation.y = entry_yaw
		if is_instance_valid(item): player.remove_collision_exception_with(item)
		player.show_social_speech("")
	if is_instance_valid(effects):
		effects.visible = false
		effects.queue_free()
	effects = null
	drops.clear()
	steam.clear()
	ripples.clear()
	item = null
	action = ""

func _make_effects() -> void:
	effects = Node3D.new()
	effects.name = "BathroomWater"
	item.add_child(effects)
	effects.visible = false
	if action == "eq_toilet": return
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.28, 0.75, 1.0, 0.88)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water.render_priority = 4
	var mesh := SphereMesh.new()
	mesh.radius = 0.018 if action == "eq_shower" else 0.008
	mesh.height = 0.12 if action == "eq_shower" else 0.045
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = water
	for i in range(72 if action == "eq_shower" else 16):
		var drop := MeshInstance3D.new()
		drop.mesh = mesh
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effects.add_child(drop)
		drops.append(drop)
	if action == "eq_shower":
		var mist := StandardMaterial3D.new()
		mist.albedo_color = Color(0.91, 0.96, 1.0, 0.18)
		mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mist.render_priority = 3
		var puff := SphereMesh.new()
		puff.radius = 0.15
		puff.height = 0.25
		puff.radial_segments = 8
		puff.rings = 4
		puff.material = mist
		for i in range(7):
			var node := MeshInstance3D.new()
			node.mesh = puff
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			effects.add_child(node)
			steam.append(node)
	for i in range(3):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.16
		torus.outer_radius = 0.175
		torus.rings = 16
		torus.ring_segments = 6
		torus.material = water
		ring.mesh = torus
		ring.scale.y = 0.3
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effects.add_child(ring)
		ripples.append(ring)

func _update_water(time: float) -> void:
	var shower := action == "eq_shower"
	var center := Vector3(0, 0.09, 0.02) if shower else Vector3(0, 0.92, -0.04)
	for i in range(drops.size()):
		var progress := fposmod(time * (1.8 if shower else 3.0) + float(i) * 0.618, 1.0)
		var angle := float(i) * 2.4
		var radius := 0.14 + float(i % 5) * 0.025 + progress * 0.07 if shower else 0.024
		drops[i].position = center + Vector3(cos(angle) * radius, (1.68 if shower else 0.20) * (1.0 - progress), sin(angle) * radius)
	for i in range(steam.size()):
		var p := fposmod(time * 0.25 + float(i) / 7.0, 1.0)
		steam[i].position = Vector3(sin(i * 2.4 + p) * 0.23, 1.0 + p * 1.15, cos(i * 2.4 + p) * 0.23)
		steam[i].scale = Vector3.ONE * (0.5 + sin(p * PI))
	for i in range(ripples.size()):
		var p := fposmod(time * 1.4 + float(i) / 3.0, 1.0)
		ripples[i].position = center + Vector3.UP * 0.005
		ripples[i].scale = Vector3(1, 0.3, 1) * (0.3 + p * (1.5 if shower else 0.6))
