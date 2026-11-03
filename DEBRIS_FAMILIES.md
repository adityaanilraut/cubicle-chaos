# Debris families

All **56 active object types** (47 furniture types and 9 loose prop types) have
an explicit assignment across **17 families**. An additional **mixed** family
handles unknown future IDs. No current object uses that fallback.

Families describe what an object breaks into and how its fragments behave.
All 56 types are breakable, including desks, chairs, tables, partitions, rugs,
appliances and bathroom fixtures. Occupied or grabbed furniture can also break:
workers release lost seats and desk assignments, player activities cancel,
grips release and supported cups return to the floor. Editor previews do not
take damage. Destroyed furniture stays absent after saving and loading.

## Complete assignments

| Family | Object IDs | Debris |
| --- | --- | --- |
| Ceramic plant (2) | `plant`, `potted_plant` | Curved pot shards, base, wooden stem; soil and leaves |
| Wooden table (4) | `side_table`, `coffee_table`, `conference_table`, `round_table` | Split tabletop and legs; drawer fronts only for the side table |
| Wooden storage (5) | `bookcase`, `bookcase_wide`, `reception_desk`, `kitchen_counter`, `kitchen_bar` | Side, back and base panels, shelves; paper bundles for bookcases |
| Workstation (5) | `desk_pc`, `laptop_desk`, `exec_desk`, `desk_plain`, `tech_workbench` | Split desk surface, metal legs, screen and keyboard; plain desk omits electronics |
| Electronics (12) | `monitor`, `laptop`, `radio`, `speaker`, `keyboard`, `speaker_tower`, `computer_set`, `tv_presentation`, `server_rack`, `network_rack`, `ups_battery`, `printer_station` | Casing and circuitry; variants for monitor assemblies, laptop display/deck, keyboard keys and speaker cones/grille |
| Metal fixture (6) | `floor_lamp`, `trashcan`, `coat_rack`, `filing_cabinet`, `whiteboard`, `hand_dryer` | Variants for lamp stem/shade/bulb, bin walls/rim, rack arms, cabinet drawers, board panels and dryer circuitry |
| Cardboard (2) | `box`, `storage_boxes` | Bottom panel, four walls and two flaps |
| Upholstered seating (2) | `lounge_chair`, `lounge_sofa` | Fabric seat/back cushions, wooden frame and legs |
| Soft toy (1) | `bear` | Rounded soft body, head and limbs |
| Paper (1) | `book` | Cardboard covers and lightweight page bundles |
| Glass fixture (4) | `glass_partition`, `frosted_partition`, `shower`, `glass_table` | Triangular translucent glass shards and metal frame/legs |
| Ceramic fixture (2) | `toilet`, `bathroom_vanity` | Porcelain shards, pedestal, metal pipe; vanity includes mirror glass |
| Appliance (4) | `water_dispenser`, `coffee_station`, `fridge`, `cooling_unit` | Metal housing/door/compressor, electronic controls and plastic tray |
| Office partition (2) | `partition`, `restroom_divider` | Panel sections, metal uprights and foot |
| Textile (2) | `rug`, `rug_round` | Thin fabric strips |
| Office chair (1) | `chair_desk` | Fabric seat, plastic back/casters, metal lift/base arms |
| Masonry (1) | `wall_half_divider` | Heavy wall blocks and dust |
| Mixed (fallback) | Any unknown future ID | Plastic panels, metal brace and wooden core |

## Material properties

Each fragment uses its own material, so a sofa's wooden frame does not inherit
its cushions' softness. Material controls volume-based mass (clamped to
0.015–3 kg per piece), bounce, friction, drag, surface finish, lifetime and
impact/break sound. Density is a game-tuning value, not a physical material claim.

| Material | Density tuning | Bounce | Friction | Linear drag | Lifetime |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wood | 180 | 0.18 | 0.85 | 0.5 | 5 s |
| Ceramic | 420 | 0.12 | 0.90 | 0.4 | 5 s |
| Electronics | 240 | 0.14 | 0.75 | 0.5 | 5 s |
| Metal | 650 | 0.30 | 0.55 | 0.35 | 6 s |
| Fabric | 45 | 0.04 | 0.98 | 1.8 | 4.5 s |
| Cardboard | 35 | 0.06 | 0.90 | 1.4 | 4 s |
| Paper | 12 | 0.01 | 0.95 | 2.4 | 3.5 s |
| Glass | 360 | 0.22 | 0.45 | 0.4 | 4 s |
| Plastic | 110 | 0.35 | 0.65 | 0.7 | 4.5 s |
| Masonry | 550 | 0.05 | 0.98 | 0.8 | 6 s |

The global caps remain **80 physical fragments** and **24 material emitters**.
Fragments collide only with the environment, sleep when settled and shrink at
the end of their lifetime. Pausing freezes their lifetime; loading clears them.
Cracks/scratches/tears are generated for every breakable type, and particles
include material chips, plant soil/leaves, electronic sparks and wood/masonry
dust. All geometry and sounds are generated locally; no downloaded assets.

## Implementation and extension

- `scripts/destruction_profile.gd`: `FAMILIES` assignments and dominant material,
  `MATERIALS` physics/finish data and `VARIANTS` geometry selection. Every
  profile is breakable by default, including the mixed fallback.
- `scripts/debris_families.gd`: reusable component recipes scaled to footprints.
- `scripts/destruction.gd`: plant/table/monitor recipes, family dispatch and
  bounded spawning in the object's world transform.
- `scripts/debris_chunk.gd`: per-component physics, material finish and cleanup.
- `scripts/destructible_state.gd`, `scripts/material_burst.gd`,
  `scripts/office_audio.gd`: damage appearance, particles and synthesized audio.
- `AssetCatalog` exposes `debris_family` and `breakable` on furniture definitions;
  `FurnitureItem` and `PhysicsProp` expose the actual `debris_profile` resource.

When adding an object, add its ID to one family's `items` list. Use a variant
when it needs different component geometry. Add a new family only when its
parts/behavior do not fit an existing one. New objects are automatically
breakable. The coverage regression rejects missing,
duplicate and stale assignments, invalid recipes and missing material sounds.

## Verification and preview

```sh
godot --headless --path . --script res://tests/debris_families_regression.gd
godot --headless --path . --script res://tests/material_destruction_regression.gd
godot --headless --path . --script res://tests/all_objects_destruction_regression.gd
godot --path . --script res://tests/debris_families_preview.gd
bash tools/run_tests.sh
```

The preview writes `build/previews/debris-families.png`, an exploded component
view of each family, including the fallback. Run the preview with a display.
