class_name DebrisFamilies
extends RefCounted

# Reusable, bottom-anchored recipes. Dimensions and offsets are fractions of
# the source footprint; secondary materials keep cushions, frames and glass
# from behaving like the object's dominant material.
static func parts_for(size: Vector3, profile: DestructionProfile) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var s := Vector3(maxf(size.x, 0.06), maxf(size.y, 0.025), maxf(size.z, 0.06))
	match profile.fracture_id:
		"storage", "cabinet":
			_shell(parts, s, profile)
			for y in [0.3, 0.6, 0.88]:
				_add(parts, s, profile, "DrawerFront" if profile.fracture_id == "cabinet" else "ShelfPanel", Vector3(0.88, 0.045, 0.88) if profile.fracture_id == "storage" else Vector3(0.88, 0.22, 0.04), Vector3(0, y, 0 if profile.fracture_id == "storage" else 0.46))
			if profile.item_id.begins_with("bookcase"):
				for x in [-0.25, 0.25]:
					_add(parts, s, profile, "BookPages", Vector3(0.22, 0.16, 0.32), Vector3(x, 0.45, 0.1), "paper")
		"workstation":
			_add(parts, s, profile, "DeskTopLeft", Vector3(0.5, 0.06, 1), Vector3(-0.25, 0.78, 0))
			_add(parts, s, profile, "DeskTopRight", Vector3(0.5, 0.06, 1), Vector3(0.25, 0.78, 0))
			_legs(parts, s, profile, "DeskLeg", 0.75, "metal")
			if profile.item_id != "desk_plain":
				_add(parts, s, profile, "WorkstationScreen", Vector3(0.35, 0.20, 0.035), Vector3(0, 0.91, -0.15), "glass")
				_add(parts, s, profile, "KeyboardPanel", Vector3(0.30, 0.025, 0.16), Vector3(0, 0.83, 0.22), "electronic")
		"electronic", "laptop", "keyboard", "speaker":
			_add(parts, s, profile, "CasingLeft", Vector3(0.5, 0.85, 0.06), Vector3(-0.25, 0.5, -0.43))
			_add(parts, s, profile, "CasingRight", Vector3(0.5, 0.85, 0.06), Vector3(0.25, 0.5, -0.43))
			_add(parts, s, profile, "CircuitBoard", Vector3(0.65, 0.035, 0.65), Vector3(0, 0.3, 0), "electronic", Color(0.13, 0.40, 0.22))
			match profile.fracture_id:
				"laptop":
					_add(parts, s, profile, "LaptopDisplay", Vector3(0.9, 0.55, 0.035), Vector3(0, 0.7, -0.3), "glass")
					_add(parts, s, profile, "KeyboardDeck", Vector3(0.9, 0.06, 0.9), Vector3(0, 0.12, 0), "plastic")
				"keyboard":
					_add(parts, s, profile, "KeyBed", Vector3(0.85, 0.3, 0.8), Vector3(0, 0.6, 0), "plastic")
					for x in [-0.3, 0, 0.3]:
						_add(parts, s, profile, "KeyCluster", Vector3(0.2, 0.25, 0.35), Vector3(x, 0.85, 0.1), "plastic")
				"speaker":
					for y in [0.3, 0.72]:
						_add(parts, s, profile, "SpeakerCone", Vector3(0.6, 0.28, 0.06), Vector3(0, y, 0.44), "plastic")
					_add(parts, s, profile, "SpeakerGrille", Vector3(0.85, 0.8, 0.025), Vector3(0, 0.5, 0.48), "metal")
				_:
					_add(parts, s, profile, "ControlPanel", Vector3(0.85, 0.5, 0.05), Vector3(0, 0.6, 0.43), "plastic")
					_add(parts, s, profile, "PowerUnit", Vector3(0.3, 0.2, 0.3), Vector3(0.2, 0.2, 0), "metal")
		"lamp":
			_add(parts, s, profile, "LampBase", Vector3(0.8, 0.05, 0.8), Vector3(0, 0.03, 0))
			for y in [0.25, 0.6]:
				_add(parts, s, profile, "LampStem", Vector3(0.1, 0.35, 0.1), Vector3(0, y, 0))
			for x in [-0.22, 0.22]:
				_add(parts, s, profile, "ShadePanel", Vector3(0.45, 0.22, 0.65), Vector3(x, 0.86, 0), "plastic")
			_add(parts, s, profile, "BulbShard", Vector3(0.2, 0.1, 0.2), Vector3(0, 0.86, 0), "glass")
		"bin":
			_add(parts, s, profile, "BinBase", Vector3(0.8, 0.04, 0.8), Vector3(0, 0.025, 0))
			_walls(parts, s, profile, "BinWall", 0.8)
			_add(parts, s, profile, "BinRim", Vector3(0.9, 0.05, 0.9), Vector3(0, 0.95, 0))
		"rack", "board", "metal_fixture":
			_add(parts, s, profile, "FixtureBase", Vector3(0.8, 0.06, 0.7), Vector3(0, 0.03, 0))
			for x in [-0.3, 0.3]:
				_add(parts, s, profile, "MetalUpright", Vector3(0.06, 0.85, 0.08), Vector3(x, 0.48, 0))
			if profile.fracture_id == "board":
				for x in [-0.24, 0.24]:
					_add(parts, s, profile, "BoardPanel", Vector3(0.48, 0.6, 0.06), Vector3(x, 0.65, 0), "plastic")
			else:
				for y in [0.6, 0.9]:
					_add(parts, s, profile, "RackArm", Vector3(0.75, 0.055, 0.08), Vector3(0, y, 0))
		"cardboard":
			_add(parts, s, profile, "BoxBottom", Vector3(0.9, 0.025, 0.9), Vector3(0, 0.02, 0))
			_walls(parts, s, profile, "CardboardPanel", 0.85)
			for x in [-0.23, 0.23]:
				_add(parts, s, profile, "BoxFlap", Vector3(0.45, 0.02, 0.9), Vector3(x, 0.93, 0))
		"upholstery":
			_add(parts, s, profile, "SeatFrame", Vector3(0.85, 0.12, 0.8), Vector3(0, 0.25, 0), "wood")
			for x in [-0.23, 0.23]:
				_add(parts, s, profile, "SeatCushion", Vector3(0.44, 0.2, 0.7), Vector3(x, 0.44, 0.08))
				_add(parts, s, profile, "BackCushion", Vector3(0.44, 0.45, 0.18), Vector3(x, 0.72, -0.33))
			_legs(parts, s, profile, "SeatLeg", 0.22, "wood")
		"soft_toy":
			_add(parts, s, profile, "ToyBody", Vector3(0.55, 0.4, 0.55), Vector3(0, 0.4, 0))
			_add(parts, s, profile, "ToyHead", Vector3(0.45, 0.3, 0.45), Vector3(0, 0.8, 0))
			for x in [-0.3, 0.3]:
				_add(parts, s, profile, "ToyArm", Vector3(0.24, 0.3, 0.24), Vector3(x, 0.5, 0))
				_add(parts, s, profile, "ToyLeg", Vector3(0.25, 0.25, 0.25), Vector3(x * 0.6, 0.14, 0.12))
		"paper":
			for y in [0.05, 0.95]:
				_add(parts, s, profile, "BookCover", Vector3(0.95, 0.04, 0.95), Vector3(0, y, 0), "cardboard", Color(0.48, 0.28, 0.20))
			for i in range(5):
				_add(parts, s, profile, "PageBundle", Vector3(0.85, 0.07, 0.85), Vector3(0, 0.2 + float(i) * 0.14, 0))
		"glass":
			for x in [-0.3, 0, 0.3]:
				for y in [0.28, 0.72]:
					var pane := Vector3(0.31, 0.43, 0.025)
					var at := Vector3(x, y, 0)
					if profile.item_id == "glass_table":
						pane = Vector3(0.31, 0.035, 0.48)
						at = Vector3(x, 0.95, (y - 0.5) * 1.05)
					_add(parts, s, profile, "GlassShard", pane, at)
			if profile.item_id == "glass_table":
				_legs(parts, s, profile, "TableFrameLeg", 0.9, "metal")
			else:
				for x in [-0.46, 0.46]:
					_add(parts, s, profile, "WindowFrame", Vector3(0.04, 0.95, 0.08), Vector3(x, 0.5, 0), "metal")
		"ceramic":
			for x in [-0.25, 0.25]:
				for y in [0.22, 0.65]:
					_add(parts, s, profile, "PorcelainShard", Vector3(0.4, 0.35, 0.14), Vector3(x, y, 0.25))
			_add(parts, s, profile, "FixturePedestal", Vector3(0.45, 0.2, 0.5), Vector3(0, 0.1, 0))
			_add(parts, s, profile, "PlumbingPipe", Vector3(0.09, 0.5, 0.09), Vector3(0, 0.35, -0.3), "metal")
			if profile.item_id == "bathroom_vanity":
				_add(parts, s, profile, "MirrorShard", Vector3(0.6, 0.3, 0.025), Vector3(0, 0.8, -0.4), "glass")
		"appliance":
			_shell(parts, s, profile)
			_add(parts, s, profile, "ApplianceDoor", Vector3(0.9, 0.8, 0.045), Vector3(0, 0.5, 0.46))
			_add(parts, s, profile, "Compressor", Vector3(0.35, 0.25, 0.35), Vector3(0, 0.2, -0.15))
			_add(parts, s, profile, "ControlCircuit", Vector3(0.3, 0.15, 0.03), Vector3(0.2, 0.8, 0.4), "electronic", Color(0.13, 0.40, 0.22))
			_add(parts, s, profile, "PlasticTray", Vector3(0.7, 0.03, 0.5), Vector3(0, 0.3, 0.1), "plastic")
		"partition":
			for x in [-0.25, 0.25]:
				_add(parts, s, profile, "PartitionPanel", Vector3(0.48, 0.85, 0.12), Vector3(x, 0.5, 0))
			for x in [-0.46, 0.46]:
				_add(parts, s, profile, "PartitionFrame", Vector3(0.04, 0.95, 0.15), Vector3(x, 0.5, 0), "metal")
			_add(parts, s, profile, "PartitionFoot", Vector3(0.8, 0.04, 0.85), Vector3(0, 0.025, 0), "metal")
		"textile":
			for x in [-0.3, 0, 0.3]:
				_add(parts, s, profile, "CarpetStrip", Vector3(0.30, 0.8, 0.9), Vector3(x, 0.5, 0))
		"chair":
			_add(parts, s, profile, "ChairSeat", Vector3(0.75, 0.12, 0.7), Vector3(0, 0.45, 0), "fabric")
			_add(parts, s, profile, "ChairBack", Vector3(0.7, 0.4, 0.12), Vector3(0, 0.77, -0.3))
			_add(parts, s, profile, "ChairGasLift", Vector3(0.08, 0.35, 0.08), Vector3(0, 0.25, 0), "metal")
			for x in [-0.3, 0.3]:
				_add(parts, s, profile, "ChairBaseArm", Vector3(0.45, 0.05, 0.12), Vector3(x, 0.07, 0), "metal")
				_add(parts, s, profile, "ChairCaster", Vector3(0.12, 0.06, 0.12), Vector3(x, 0.03, 0))
		"masonry":
			for x in [-0.32, 0, 0.32]:
				for y in [0.25, 0.7]:
					_add(parts, s, profile, "WallBlock", Vector3(0.3, 0.4, 0.8), Vector3(x, y, 0))
		_:
			# Explicit mixed family for future assets, never empty debris.
			for x in [-0.25, 0.25]:
				_add(parts, s, profile, "MixedPanel", Vector3(0.45, 0.5, 0.08), Vector3(x, 0.55, 0.3))
			_add(parts, s, profile, "MixedBrace", Vector3(0.7, 0.08, 0.12), Vector3(0, 0.25, 0), "metal")
			_add(parts, s, profile, "MixedCore", Vector3(0.4, 0.4, 0.4), Vector3(0, 0.4, 0), "wood")
	return parts

static func _add(parts: Array[Dictionary], size: Vector3, profile: DestructionProfile, title: String, fraction: Vector3, offset: Vector3, material := "", tint := Color(-1, -1, -1)) -> void:
	var dimensions := size * fraction
	dimensions = Vector3(maxf(dimensions.x, 0.012), maxf(dimensions.y, 0.012), maxf(dimensions.z, 0.012))
	var color := profile.color if material == "" else DestructionProfile.MATERIALS[material].color as Color
	if tint.r >= 0: color = tint
	var part := {"name": title, "size": dimensions, "at": size * offset, "color": color, "material": material}
	if title.ends_with("Shard"):
		var shard := PrismMesh.new()
		shard.size = dimensions
		part["mesh"] = shard
	elif title.begins_with("Toy"):
		var rounded := SphereMesh.new()
		rounded.radius = minf(dimensions.x, dimensions.z) * 0.5
		rounded.height = dimensions.y
		rounded.radial_segments = 8
		rounded.rings = 4
		part["mesh"] = rounded
	parts.append(part)

static func _legs(parts: Array[Dictionary], size: Vector3, profile: DestructionProfile, title: String, height: float, material: String) -> void:
	for x in [-0.39, 0.39]:
		for z in [-0.34, 0.34]:
			_add(parts, size, profile, title, Vector3(0.06, height, 0.06), Vector3(x, height * 0.5, z), material)

static func _walls(parts: Array[Dictionary], size: Vector3, profile: DestructionProfile, title: String, height: float) -> void:
	for x in [-0.46, 0.46]:
		_add(parts, size, profile, title, Vector3(0.025, height, 0.9), Vector3(x, 0.5, 0))
	for z in [-0.46, 0.46]:
		_add(parts, size, profile, title, Vector3(0.9, height, 0.025), Vector3(0, 0.5, z))

static func _shell(parts: Array[Dictionary], size: Vector3, profile: DestructionProfile) -> void:
	for x in [-0.46, 0.46]:
		_add(parts, size, profile, "SidePanel", Vector3(0.045, 0.92, 0.9), Vector3(x, 0.5, 0))
	_add(parts, size, profile, "BackPanel", Vector3(0.9, 0.92, 0.035), Vector3(0, 0.5, -0.46))
	_add(parts, size, profile, "BasePanel", Vector3(0.9, 0.045, 0.9), Vector3(0, 0.03, 0))
