class_name CombatImpact
extends Node3D

# Reusable, self-cleaning 3D contact object. No textures or external assets needed.
var kind := "punch"
var move_label := ""
var age := 0.0
var lifetime := 0.42
var burst: Node3D
var caption: Label3D

func _ready() -> void:
	add_to_group("combat_impacts")
	name = "KickContact" if kind == "kick" else "PunchContact"
	var color := Color(0.25, 0.85, 1.0) if kind == "kick" else Color(1.0, 0.65, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	burst = Node3D.new()
	add_child(burst)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.20
	torus.rings = 16
	torus.ring_segments = 6
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	ring.material_override = material
	burst.add_child(ring)
	for i in range(8):
		var ray := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.035, 0.16 if kind == "punch" else 0.25, 0.035)
		ray.mesh = mesh
		ray.material_override = material
		var angle := TAU * float(i) / 8.0
		ray.position = Vector3(sin(angle), cos(angle), 0) * 0.30
		ray.rotation.z = -angle
		burst.add_child(ray)
	caption = Label3D.new()
	caption.text = move_label.to_upper() if not move_label.is_empty() else ("KICK!" if kind == "kick" else "POW!")
	caption.font_size = 30 if not move_label.is_empty() else 48
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.pixel_size = 0.0035 if not move_label.is_empty() else 0.005
	caption.modulate = color
	caption.outline_size = 12
	caption.position.y = 0.32
	add_child(caption)

func _process(delta: float) -> void:
	age += delta
	var progress := clampf(age / lifetime, 0.0, 1.0)
	burst.scale = Vector3.ONE * lerpf(0.45, 1.8, progress)
	for child in burst.get_children():
		(child as MeshInstance3D).transparency = progress
	caption.position.y += delta * 0.7
	caption.modulate.a = 1.0 - progress
	if age >= lifetime:
		queue_free()
