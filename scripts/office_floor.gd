class_name OfficeFloor
extends RefCounted

const PATTERNS: Array[String] = ["Solid", "Square tiles", "Staggered planks", "Checkerboard"]
const TEXTURES: Array[String] = ["Smooth", "Wood grain", "Carpet", "Stone"]
static var _textures: Dictionary = {}

static func surface(pattern: int, finish: int) -> Texture2D:
	if pattern == 0 and finish == 0:
		return null
	var key := Vector2i(pattern, finish)
	if _textures.has(key):
		return _textures[key]
	# A seamless two-meter repeat, projected in world space across every tile.
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.06
	for y in range(256):
		for x in range(256):
			var u := float(x) / 256.0
			var v := float(y) / 256.0
			# Periodic noise coordinates keep opposite edges continuous.
			var grain := noise.get_noise_3d(cos(u * TAU) * 40.0, sin(u * TAU) * 40.0, sin(v * TAU) * 40.0)
			var value := 1.0
			match finish:
				1:
					value = 0.88 + 0.12 * (0.5 + 0.5 * sin(v * TAU * 32.0 + grain * 4.0))
				2:
					var fiber := float((x * 73 + y * 151 + x * y * 19) % 101) / 100.0
					value = 0.80 + fiber * 0.20
				3:
					value = 0.88 + grain * 0.10
					if absf(sin((u + v) * TAU * 2.0 + grain * 5.0)) < 0.10:
						value *= 0.78
			match pattern:
				1:
					if fposmod(u * 2.0, 1.0) < 0.018 or fposmod(v * 2.0, 1.0) < 0.018:
						value *= 0.62
				2:
					var row := int(floor(v * 8.0))
					if fposmod(v * 8.0, 1.0) < 0.045 or fposmod(u * 2.0 + float(row % 2) * 0.5, 1.0) < 0.012:
						value *= 0.65
				3:
					if (int(floor(u * 2.0)) + int(floor(v * 2.0))) % 2 == 0:
						value *= 0.68
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture

static func apply(material: StandardMaterial3D, color: Color, pattern: int, finish: int) -> void:
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.albedo_texture = surface(pattern, finish)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = [0.75, 0.80, 1.0, 0.88][finish]
