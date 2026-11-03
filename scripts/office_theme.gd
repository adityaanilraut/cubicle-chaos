class_name OfficeTheme
extends RefCounted

# One consistent theme for the whole office. Every room, corridor and the
# south wing share the same single floor colour, wall tone and accent
# palette. The player picks a theme in Settings > Office theme;
# Edit office can override the shared floor color, pattern and texture.
const THEMES: Array[Dictionary] = [
	{
		"name": "Nordic Light Oak",
		"floor": Color(0.85, 0.78, 0.65),
		"wall": Color(0.93, 0.90, 0.84),
		"plinth": Color(0.72, 0.66, 0.56),
		"frame": Color(0.72, 0.62, 0.48),
		"accent": Color(0.55, 0.65, 0.53),
		"accent_warm": Color(0.85, 0.62, 0.45),
		"sign": Color(0.98, 0.94, 0.84),
		"architecture": Color(0.88, 0.85, 0.78),
		"glass_tint": Color(0.82, 0.89, 0.88, 0.18),
	},
	{
		"name": "Scandinavian White",
		"floor": Color(0.91, 0.89, 0.84),
		"wall": Color(0.96, 0.96, 0.95),
		"plinth": Color(0.78, 0.78, 0.76),
		"frame": Color(0.76, 0.68, 0.56),
		"accent": Color(0.62, 0.72, 0.78),
		"accent_warm": Color(0.80, 0.72, 0.60),
		"sign": Color(0.99, 0.98, 0.94),
		"architecture": Color(0.92, 0.92, 0.90),
		"glass_tint": Color(0.85, 0.91, 0.93, 0.16),
	},
	{
		"name": "Warm Sand Minimal",
		"floor": Color(0.85, 0.75, 0.60),
		"wall": Color(0.94, 0.89, 0.78),
		"plinth": Color(0.70, 0.60, 0.48),
		"frame": Color(0.68, 0.56, 0.40),
		"accent": Color(0.62, 0.66, 0.48),
		"accent_warm": Color(0.82, 0.55, 0.38),
		"sign": Color(0.99, 0.93, 0.80),
		"architecture": Color(0.89, 0.83, 0.72),
		"glass_tint": Color(0.84, 0.89, 0.82, 0.18),
	},
]

static func theme_names() -> Array[String]:
	var names: Array[String] = []
	for t in THEMES:
		names.append(String(t["name"]))
	return names

static func get_theme(idx: int) -> Dictionary:
	return THEMES[clampi(idx, 0, THEMES.size() - 1)]

static func floor_color(idx: int) -> Color:
	return get_theme(idx)["floor"]
