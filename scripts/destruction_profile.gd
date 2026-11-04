class_name DestructionProfile
extends Resource

# Every catalog object has an explicit family. Geometry, impact resistance,
# fragment physics, finish, particles and sound all use this registry.
const MATERIALS := {
	"wood": {"density": 180.0, "bounce": 0.18, "friction": 0.85, "damp": 0.5, "roughness": 0.85, "lifetime": 5.0, "color": Color(0.78, 0.65, 0.48)},
	"ceramic": {"density": 420.0, "bounce": 0.12, "friction": 0.90, "damp": 0.4, "roughness": 0.55, "lifetime": 5.0, "color": Color(0.86, 0.83, 0.76)},
	"electronic": {"density": 240.0, "bounce": 0.14, "friction": 0.75, "damp": 0.5, "roughness": 0.65, "lifetime": 5.0, "color": Color(0.18, 0.21, 0.25)},
	"metal": {"density": 650.0, "bounce": 0.30, "friction": 0.55, "damp": 0.35, "roughness": 0.38, "lifetime": 6.0, "color": Color(0.45, 0.49, 0.53)},
	"fabric": {"density": 45.0, "bounce": 0.04, "friction": 0.98, "damp": 1.8, "roughness": 1.0, "lifetime": 4.5, "color": Color(0.56, 0.40, 0.34)},
	"cardboard": {"density": 35.0, "bounce": 0.06, "friction": 0.90, "damp": 1.4, "roughness": 1.0, "lifetime": 4.0, "color": Color(0.62, 0.48, 0.32)},
	"paper": {"density": 12.0, "bounce": 0.01, "friction": 0.95, "damp": 2.4, "roughness": 1.0, "lifetime": 3.5, "color": Color(0.91, 0.88, 0.78)},
	"glass": {"density": 360.0, "bounce": 0.22, "friction": 0.45, "damp": 0.4, "roughness": 0.12, "lifetime": 4.0, "color": Color(0.61, 0.82, 0.84, 0.65)},
	"plastic": {"density": 110.0, "bounce": 0.35, "friction": 0.65, "damp": 0.7, "roughness": 0.60, "lifetime": 4.5, "color": Color(0.55, 0.57, 0.58)},
	"masonry": {"density": 550.0, "bounce": 0.05, "friction": 0.98, "damp": 0.8, "roughness": 1.0, "lifetime": 6.0, "color": Color(0.72, 0.69, 0.62)},
}

const FAMILIES := {
	"wooden_bat": {"material": "wood", "fracture": "bat", "resistance": 1.3, "items": ["baseball_bat"]},
	"ceramic_plant": {"material": "ceramic", "fracture": "plant", "resistance": 0.75, "color": Color(0.67, 0.33, 0.23), "items": ["plant", "potted_plant"]},
	"wooden_table": {"material": "wood", "fracture": "table", "resistance": 1.15, "items": ["side_table", "coffee_table", "conference_table", "round_table"]},
	"wooden_storage": {"material": "wood", "fracture": "storage", "resistance": 1.25, "items": ["bookcase", "bookcase_wide", "reception_desk", "kitchen_counter", "kitchen_bar"]},
	"workstation": {"material": "wood", "fracture": "workstation", "resistance": 1.4, "items": ["desk_pc", "laptop_desk", "exec_desk", "desk_plain", "tech_workbench"]},
	"electronics": {"material": "electronic", "fracture": "electronic", "resistance": 0.90, "items": ["monitor", "laptop", "radio", "speaker", "keyboard", "speaker_tower", "computer_set", "tv_presentation", "server_rack", "network_rack", "ups_battery", "printer_station"]},
	"metal_fixture": {"material": "metal", "fracture": "metal_fixture", "resistance": 1.65, "items": ["floor_lamp", "trashcan", "coat_rack", "filing_cabinet", "whiteboard", "hand_dryer"]},
	"cardboard": {"material": "cardboard", "fracture": "cardboard", "resistance": 0.65, "items": ["box", "storage_boxes"]},
	"upholstered_seating": {"material": "fabric", "fracture": "upholstery", "resistance": 2.8, "items": ["lounge_chair", "lounge_sofa"]},
	"soft_toy": {"material": "fabric", "fracture": "soft_toy", "resistance": 2.8, "items": ["bear"]},
	"paper": {"material": "paper", "fracture": "paper", "resistance": 0.8, "items": ["book"]},
	"glass_fixture": {"material": "glass", "fracture": "glass", "resistance": 0.55, "items": ["glass_partition", "frosted_partition", "shower", "glass_table"]},
	"ceramic_fixture": {"material": "ceramic", "fracture": "ceramic", "resistance": 0.85, "items": ["toilet", "bathroom_vanity"]},
	"appliance": {"material": "metal", "fracture": "appliance", "resistance": 1.8, "items": ["water_dispenser", "coffee_station", "fridge", "cooling_unit"]},
	"office_partition": {"material": "fabric", "fracture": "partition", "resistance": 1.4, "items": ["partition", "restroom_divider"]},
	"textile": {"material": "fabric", "fracture": "textile", "resistance": 3.0, "items": ["rug", "rug_round"]},
	"office_chair": {"material": "plastic", "fracture": "chair", "resistance": 1.6, "items": ["chair_desk"]},
	"masonry": {"material": "masonry", "fracture": "masonry", "resistance": 2.2, "items": ["wall_half_divider"]},
	# Future/unrecognized objects still get deliberate mixed-material debris.
	"mixed": {"material": "plastic", "fracture": "mixed", "resistance": 1.0, "items": []},
}

const VARIANTS := {"monitor": "monitor", "tv_presentation": "monitor", "computer_set": "monitor", "laptop": "laptop", "keyboard": "keyboard", "speaker": "speaker", "speaker_tower": "speaker", "floor_lamp": "lamp", "trashcan": "bin", "filing_cabinet": "cabinet", "coat_rack": "rack", "whiteboard": "board", "hand_dryer": "electronic"}

@export var family_id := "mixed"
@export var item_id := ""
@export var material_id := "plastic"
@export var fracture_id := "mixed"
@export var resistance := 1.0
@export var color := Color(0.55, 0.57, 0.58)
@export var chip_color := Color(0.72, 0.72, 0.68)
var breakable := true

static func family_for(object_id: String) -> String:
	for family in FAMILIES:
		if object_id in FAMILIES[family].items:
			return family
	return "mixed"

static func for_item(object_id: String) -> DestructionProfile:
	var profile := DestructionProfile.new()
	profile.item_id = object_id
	profile.family_id = family_for(object_id)
	var family: Dictionary = FAMILIES[profile.family_id]
	profile.material_id = family.material
	profile.fracture_id = VARIANTS.get(object_id, family.fracture)
	profile.resistance = family.resistance
	profile.color = family.get("color", MATERIALS[profile.material_id].color)
	profile.chip_color = profile.color.lightened(0.15)
	return profile

func debris_properties(part_material := "") -> Dictionary:
	return MATERIALS.get(part_material, MATERIALS[material_id]).duplicate()

func impact_sound(broken := false) -> String:
	return material_id + ("_break" if broken else "_hit")
