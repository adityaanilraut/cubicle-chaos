class_name OfficeAudio
extends Node

# All sound is synthesized at runtime into AudioStreamWAV data.
# No downloaded audio files are needed, which keeps the web export small.

var enabled := true
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _streams: Dictionary = {}
const MATERIAL_SOUNDS := {"wood": [125.0, 0.70], "ceramic": [1850.0, 0.35], "electronic": [430.0, 0.65], "metal": [760.0, 0.20], "fabric": [75.0, 0.82], "cardboard": [105.0, 0.92], "paper": [220.0, 0.98], "glass": [2600.0, 0.30], "plastic": [340.0, 0.55], "masonry": [95.0, 0.95]}

static func play_at(tree: SceneTree, sound_name: String, _world_pos: Vector3 = Vector3.ZERO) -> void:
	if tree == null:
		return
	var nodes := tree.get_nodes_in_group("office_audio")
	if nodes.is_empty():
		return
	(nodes[0] as OfficeAudio).play(sound_name)

func _ready() -> void:
	add_to_group("office_audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	for i in range(10):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)

func play(sound_name: String, volume_db: float = -8.0) -> void:
	if not enabled or not is_inside_tree() or not _streams.has(sound_name) or _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound_name]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.94, 1.06)
	player.play()

func _exit_tree() -> void:
	# Stop and free players before the streams go away, so no active WAV
	# playback handle lingers when a shift/test scene is freed or the
	# application shuts down (a playing stream otherwise leaks at exit).
	for player in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			remove_child(player)
			player.free()
	_players.clear()
	_streams.clear()

func _build_streams() -> void:
	_streams["punch"] = _noise_burst(0.11, 900.0, 0.7)
	_streams["kick"] = _noise_burst(0.17, 480.0, 0.9)
	_streams["thud"] = _tone(72.0, 0.14, 0.8, true)
	_streams["break"] = _noise_burst(0.38, 1400.0, 1.0)
	_streams["pickup"] = _tone(720.0, 0.08, 0.45)
	_streams["throw"] = _noise_burst(0.22, 700.0, 0.55)
	_streams["ding"] = _tone(880.0, 0.28, 0.5)
	_streams["pop"] = _tone(520.0, 0.06, 0.4)
	_streams["click"] = _tone(620.0, 0.045, 0.35)
	_streams["splash"] = _noise_burst(0.25, 1000.0, 0.6)
	_streams["ouch"] = _tone(300.0, 0.12, 0.5, true)
	# Distinct resonances and noise balance for each destruction material.
	for material in MATERIAL_SOUNDS:
		var spec: Array = MATERIAL_SOUNDS[material]
		_streams[material + "_hit"] = _material_sound(spec[0], 0.16, spec[1], false, material == "electronic")
		_streams[material + "_break"] = _material_sound(spec[0], 0.40, spec[1], true, material == "electronic")

func _material_sound(frequency: float, duration: float, noise_mix: float, broken: bool, electronic: bool) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var noise := 0.0
	for i in range(frames):
		var t := float(i) / rate
		var progress := float(i) / maxf(frames, 1)
		noise = lerpf(noise, randf_range(-1, 1), 0.5)
		var ring := sin(TAU * frequency * t) + sin(TAU * frequency * 1.47 * t) * 0.3
		if electronic: ring *= 1.0 if int(t * 90) % 3 == 0 else 0.15
		var envelope := pow(1.0 - progress, 2.1)
		var crackle := (0.4 + 0.6 * absf(sin(t * 87))) if broken else 1.0
		_write_sample(data, i, (ring * (1.0 - noise_mix) * 0.4 + noise * noise_mix * crackle) * envelope * 0.8)
	return _make_stream(data, rate)

func _tone(frequency: float, duration: float, volume: float, slide_down: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * float(rate))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(rate)
		var progress := float(i) / maxf(float(frames), 1.0)
		var freq := frequency * (lerpf(1.0, 0.55, progress) if slide_down else 1.0)
		var envelope := 1.0 - progress
		var sample := sin(TAU * freq * t) * volume * envelope
		_write_sample(data, i, sample)
	return _make_stream(data, rate)

func _noise_burst(duration: float, cutoff: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * float(rate))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var previous := 0.0
	var alpha := 1.0 - exp(-TAU * cutoff / float(rate))
	for i in range(frames):
		var progress := float(i) / maxf(float(frames), 1.0)
		var envelope := pow(1.0 - progress, 1.6)
		var white := randf_range(-1.0, 1.0)
		previous = lerpf(previous, white, alpha)
		_write_sample(data, i, previous * volume * envelope)
	return _make_stream(data, rate)

func _write_sample(data: PackedByteArray, frame: int, sample: float) -> void:
	var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
	if value < 0:
		value += 65536
	data[frame * 2] = value & 0xff
	data[frame * 2 + 1] = (value >> 8) & 0xff

func _make_stream(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
