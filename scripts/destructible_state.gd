class_name DestructibleState
extends Node3D

signal damaged(ratio: float)

var profile: DestructionProfile
var health := 1.0
var max_health := 1.0
var damage_state := "intact"
var broken := false
var body: Node3D
var visual: Node3D
var footprint := Vector3.ONE
var damage_visual: Node3D
var screen: MeshInstance3D
var flicker_time := 0.0

func configure(owner_body: Node3D, owner_visual: Node3D, size: Vector3, item_id: String, durability: float, debris_profile: DestructionProfile = null) -> void:
	body = owner_body
	visual = owner_visual
	footprint = size
	profile = debris_profile if debris_profile != null else DestructionProfile.for_item(item_id)
	max_health = durability
	health = max_health
	apply_materials()
	_build_damage_visual()
	refresh()

func apply_materials() -> void:
	if profile.fracture_id != "plant": return
	# The source furniture kit labels its pot surfaces as wood. Give just the
	# pot a ceramic finish so the intact object matches its fracture pieces.
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		for index in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.mesh.surface_get_material(index)
			if original != null and original.resource_name == "wood":
				mesh.set_surface_override_material(index, AssetCatalog.get_shared_material("ceramic_pot", profile.color, 0.55))

func ratio() -> float:
	return clampf(1.0 - health / maxf(max_health, 0.001), 0, 1)

func restore_health(value: float) -> void:
	health = clampf(value, 0, max_health)
	refresh()

func apply_damage(amount: float, direction: Vector3, hit_position: Vector3 = Vector3.ZERO) -> bool:
	if broken or health <= 0.0 or amount <= 0.0: return false
	health = maxf(0, health - amount)
	refresh()
	var origin := hit_position if hit_position != Vector3.ZERO else body.global_position + Vector3.UP * maxf(footprint.y * 0.5, 0.15)
	OfficeAudio.play_at(get_tree(), profile.impact_sound(), origin)
	if health > 0:
		Destruction.spawn_material_effect(get_parent().get_parent(), origin, profile, false, direction)
	damaged.emit(ratio())
	return health <= 0.0

func refresh() -> void:
	damage_state = "broken" if health <= 0.0 else "damaged" if health < max_health else "intact"
	if is_instance_valid(damage_visual): damage_visual.visible = damage_state == "damaged"
	if is_instance_valid(screen): screen.visible = damage_state != "broken"

func fracture() -> void:
	if broken: return
	broken = true
	health = 0.0
	refresh()

func spawn_fracture(direction: Vector3) -> void:
	if broken: return
	fracture()
	Destruction.spawn_fracture(body.get_parent(), body.global_transform, footprint, profile, direction)
	OfficeAudio.play_at(get_tree(), profile.impact_sound(true), body.global_position)

func _build_damage_visual() -> void:
	damage_visual = Node3D.new()
	damage_visual.name = "MaterialDamage"
	add_child(damage_visual)
	var crack_color := Color(0.18, 0.11, 0.07)
	if profile.material_id == "ceramic":
		var radius := maxf(minf(footprint.x, footprint.z) * 0.38, 0.06)
		var height := footprint.y * 0.33
		for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var a := Vector3(sin(angle) * radius, height * 0.95, cos(angle) * radius)
			var b := Vector3(sin(angle + 0.13) * radius, height * 0.52, cos(angle + 0.13) * radius)
			var c := Vector3(sin(angle - 0.10) * radius, height * 0.16, cos(angle - 0.10) * radius)
			_line(damage_visual, a, b, crack_color, 0.012)
			_line(damage_visual, b, c, crack_color, 0.012)
	elif profile.fracture_id == "table":
		var y := footprint.y + 0.007
		for z in [-0.18, 0.12]:
			_line(damage_visual, Vector3(-footprint.x * 0.43, y, z * footprint.z), Vector3(footprint.x * 0.1, y, (z + 0.08) * footprint.z), crack_color, 0.016)
			_line(damage_visual, Vector3(footprint.x * 0.1, y, (z + 0.08) * footprint.z), Vector3(footprint.x * 0.4, y, z * footprint.z), crack_color, 0.012)
	elif profile.fracture_id == "monitor":
		var size := Vector3(footprint.x * 0.87, footprint.y * 0.55, 0.012)
		screen = _box(self, "MonitorDisplay", size, Vector3(0, footprint.y * 0.62, footprint.z * 0.5 + 0.008), Color(0.23, 0.54, 0.66))
		var center := Vector3(-size.x * 0.14, footprint.y * 0.63, footprint.z * 0.5 + 0.019)
		for i in range(7):
			var angle := float(i) / 7 * TAU
			_line(damage_visual, center, center + Vector3(cos(angle) * size.x * 0.42, sin(angle) * size.y * 0.45, 0), Color(0.02, 0.06, 0.08), 0.009)
		for i in range(3):
			_box(damage_visual, "DeadPixels", Vector3(size.x, 0.008, 0.008), Vector3(0, footprint.y * (0.46 + float(i) * 0.15), center.z), Color(0.06, 0.12, 0.14))
	else:
		# Scratches, seams and tears are present for every remaining family.
		var mark_color := profile.color.darkened(0.55)
		var front := footprint.z * 0.5 + 0.008
		for i in range(3):
			var center := Vector3((float(i) - 1.0) * footprint.x * 0.22, footprint.y * (0.3 + float(i) * 0.18), front)
			_line(damage_visual, center - Vector3(footprint.x * 0.12, footprint.y * 0.08, 0), center + Vector3(footprint.x * 0.10, footprint.y * 0.05, 0), mark_color, 0.009)

func _process(delta: float) -> void:
	if not is_instance_valid(screen): return
	flicker_time += delta
	var material := screen.material_override as StandardMaterial3D
	var level := 0.16 if damage_state == "damaged" and fmod(flicker_time, 0.27) < 0.08 else 0.7
	material.emission_energy_multiplier = level

func _box(parent: Node, title: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if title == "MonitorDisplay":
		material.emission_enabled = true
		material.emission = color
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

func _line(parent: Node, a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var line := _box(parent, "Crack", Vector3(width, a.distance_to(b), width), (a + b) * 0.5, color)
	line.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
