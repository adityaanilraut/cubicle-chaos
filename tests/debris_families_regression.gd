extends SceneTree

var failures: Array[String] = []
var checks := 0
var world: Node3D

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func clear_world() -> void:
	for child in world.get_children(): child.free()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ids: Dictionary = {}
	var mapping: Dictionary = {}
	for family in DestructionProfile.FAMILIES:
		for id in DestructionProfile.FAMILIES[family].items:
			check(not mapping.has(id), "%s belongs to one debris family" % id)
			mapping[id] = family
	var catalog := AssetCatalog.get_catalog_items()
	for def in catalog: ids[def.id] = true
	for id in PhysicsProp.GLB_BY_ID: ids[id] = true
	check(mapping.size() == ids.size(), "Family registry covers exactly the active furniture and prop catalog")
	var family_counts := {}
	for id in ids:
		var body: Node3D
		if PhysicsProp.GLB_BY_ID.has(id):
			body = PhysicsProp.new()
		else:
			body = FurnitureItem.new()
		body.setup(id)
		world.add_child(body)
		var profile: DestructionProfile = body.debris_profile
		check(profile.family_id != "mixed" and mapping.get(id) == profile.family_id, "%s has an explicit family" % id)
		family_counts[profile.family_id] = family_counts.get(profile.family_id, 0) + 1
		if body is FurnitureItem:
			var def := AssetCatalog.get_item_def(id)
			check(def.debris_family == profile.family_id and def.breakable and body.breakable, "%s is breakable and exposes its family in the catalog" % id)
		check(is_instance_valid(body.destructible), "%s has an active destruction state" % id)
		if is_instance_valid(body.destructible):
			body.take_damage(body.max_health * 0.25)
			check(body.destructible.damage_visual.visible and body.destructible.damage_visual.get_child_count() > 0, "%s has visible nonlethal damage" % id)
		var parts := Destruction._fracture_parts(body.footprint_size, profile)
		check(parts.size() >= 3 and parts.size() <= 12, "%s has a bounded recognizable fracture recipe" % id)
		for part in parts:
			var size: Vector3 = part.size
			check(size.is_finite() and minf(size.x, minf(size.y, size.z)) > 0, "%s has valid fragment dimensions" % id)
			check(part.name != "fragment", "%s has named components" % id)
		# Validate geometry and source transforms before exercising gameplay damage.
		var transform := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(3, 2, 5))
		Destruction.spawn_fracture(world, transform, body.footprint_size, profile, Vector3.RIGHT)
		var chunks := get_nodes_in_group("destruction_debris")
		check(chunks.size() == parts.size(), "%s spawns all family components" % id)
		for i in range(chunks.size()):
			var chunk: DebrisChunk = chunks[i]
			check(chunk.family_id == profile.family_id, "%s debris retains its family" % id)
			check(chunk.global_position.is_equal_approx(transform * parts[i].at), "%s debris respects source rotation and origin" % id)
			check(chunk.collision_layer == 16 and chunk.collision_mask == 1, "%s debris only collides with the environment" % id)
			check(chunk.mass > 0 and chunk.lifetime > 0 and chunk._mesh_instance.mesh != null, "%s debris has physical properties and geometry" % id)
		if is_instance_valid(body.destructible):
			for chunk in chunks: chunk.free()
			for effect in get_nodes_in_group("material_effects"): effect.free()
			check(body.take_damage(1000, Vector3.RIGHT) and body.is_queued_for_deletion(), "%s breaks through the actual gameplay damage path" % id)
			var broken_parts := get_nodes_in_group("destruction_debris")
			check(broken_parts.size() == parts.size(), "%s gameplay destruction spawns its family recipe" % id)
			check(broken_parts.all(func(chunk): return chunk.family_id == profile.family_id), "%s gameplay destruction applies family properties" % id)
		clear_world()
	var unknown := DestructionProfile.for_item("future_unknown_asset")
	check(unknown.family_id == "mixed" and unknown.breakable, "Future objects receive a breakable mixed-material family")
	check(Destruction._fracture_parts(Vector3.ONE, unknown).size() >= 3, "Future objects have actual fallback parts")
	var metal := DebrisChunk.new()
	var paper := DebrisChunk.new()
	world.add_child(metal)
	world.add_child(paper)
	metal.setup(Vector3.ONE * 0.1, Color.GRAY, Vector3.ZERO, null, DestructionProfile.for_item("trashcan"))
	paper.setup(Vector3.ONE * 0.1, Color.WHITE, Vector3.ZERO, null, DestructionProfile.for_item("book"))
	check(metal.mass > paper.mass * 5 and paper.linear_damp > metal.linear_damp, "Paper is lighter and settles with more drag than metal")
	check(metal.physics_material_override.bounce > paper.physics_material_override.bounce, "Metal and paper have different bounce behavior")
	clear_world()
	var sofa_parts := Destruction._fracture_parts(Vector3.ONE, DestructionProfile.for_item("lounge_sofa"))
	check(sofa_parts.any(func(part): return part.get("material") == "wood") and sofa_parts.any(func(part): return part.name == "SeatCushion"), "Upholstery combines soft cushions with a wooden frame")
	var coffee_parts := Destruction._fracture_parts(Vector3.ONE, DestructionProfile.for_item("coffee_table"))
	check(not coffee_parts.any(func(part): return part.name == "DrawerPanel"), "Coffee tables do not produce side-table drawers")
	var audio := OfficeAudio.new()
	world.add_child(audio)
	for material in DestructionProfile.MATERIALS:
		check(audio._streams.has(material + "_hit") and audio._streams.has(material + "_break"), "%s has impact and break audio" % material)
	clear_world()
	for i in range(30):
		Destruction.spawn_fracture(world, Transform3D.IDENTITY, Vector3.ONE, DestructionProfile.for_item("bookcase"), Vector3.ZERO)
	check(get_nodes_in_group("destruction_debris").size() <= Destruction.MAX_DEBRIS, "Family destruction respects global debris budget")
	check(get_nodes_in_group("material_effects").size() <= Destruction.MAX_EFFECTS, "Family destruction respects global effects budget")
	for chunk in get_nodes_in_group("destruction_debris"): chunk._process(chunk.lifetime)
	for effect in get_nodes_in_group("material_effects"): effect._process(effect.lifetime)
	await process_frame
	check(get_nodes_in_group("destruction_debris").is_empty() and get_nodes_in_group("material_effects").is_empty(), "Family debris and effects expire")
	print("DEBRIS FAMILY COVERAGE: %d objects across %d families (+ mixed fallback)" % [ids.size(), family_counts.size()])
	print("DEBRIS FAMILY CHECKS: %d/%d passed" % [checks - failures.size(), checks])
	world.free()
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
