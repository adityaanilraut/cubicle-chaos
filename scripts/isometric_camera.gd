class_name IsometricCamera
extends Node3D

const MIN_ZOOM := 4.5
const MAX_ZOOM := 56.0
const ZOOM_STEP := 1.25
const PAN_SPEED := 11.0
const ROTATE_SPEED := 95.0
const BOUNDS_LIMIT := 18.0

var target_pos: Vector3 = Vector3(0.0, 0.0, 0.5)
var target_yaw_deg: float = 45.0
var target_zoom: float = 16.5
var pitch_deg: float = -35.264

var pan_bounds := Rect2(-BOUNDS_LIMIT, -BOUNDS_LIMIT, BOUNDS_LIMIT * 2, BOUNDS_LIMIT * 2)
var follow_player := false
var pan_offset := Vector3.ZERO
var camera: Camera3D = null
var _is_panning_drag: bool = false
var _is_rotating_drag: bool = false

func _ready() -> void:
	position = target_pos
	rotation_degrees = Vector3(pitch_deg, target_yaw_deg, 0.0)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = target_zoom
	camera.position = Vector3(0.0, 0.0, 48.0)
	camera.near = 0.1
	camera.far = 160.0
	camera.current = true
	add_child(camera)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_is_panning_drag = false
		_is_rotating_drag = false

func _unhandled_input(event: InputEvent) -> void:
	if _conversation_open():
		_is_panning_drag = false
		_is_rotating_drag = false
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			var factor := clampf(mb.factor, 0.5, 3.0)
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_by(-ZOOM_STEP * factor)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(ZOOM_STEP * factor)
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_rotating_drag = Input.is_key_pressed(KEY_SHIFT)
				_is_panning_drag = not _is_rotating_drag
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_panning_drag = false
				_is_rotating_drag = false

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _is_rotating_drag:
			target_yaw_deg -= mm.relative.x * 0.35
		elif _is_panning_drag:
			var scale_factor := target_zoom * 0.0018
			var right := Vector3(cos(deg_to_rad(target_yaw_deg)), 0.0, -sin(deg_to_rad(target_yaw_deg)))
			var forward := Vector3(sin(deg_to_rad(target_yaw_deg)), 0.0, cos(deg_to_rad(target_yaw_deg)))
			var motion := -right * mm.relative.x * scale_factor - forward * mm.relative.y * scale_factor * 1.35
			target_pos += motion
			if follow_player: pan_offset += motion
			_clamp_target_pos()

func _process(delta: float) -> void:
	# Use real unscaled delta so camera controls stay responsive at any simulation speed
	var dt: float = delta / maxf(Engine.time_scale, 0.1)
	var controls_available := not _conversation_open()

	var pan_input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan_input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan_input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan_input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan_input.x += 1.0

	if controls_available and not follow_player and pan_input.length_squared() > 0.0:
		pan_input = pan_input.normalized()
		var yaw_rad := deg_to_rad(target_yaw_deg)
		var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
		var forward := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
		var speed := PAN_SPEED * (target_zoom / 13.0)
		target_pos += (right * pan_input.x + forward * pan_input.y) * speed * dt
		_clamp_target_pos()

	if controls_available and OfficeInput.is_pressed("rotate_left"):
		target_yaw_deg -= ROTATE_SPEED * dt
	if controls_available and OfficeInput.is_pressed("rotate_right"):
		target_yaw_deg += ROTATE_SPEED * dt

	if controls_available and (Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD)):
		zoom_by(-ZOOM_STEP * dt * 4.0)
	if controls_available and (Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT)):
		zoom_by(ZOOM_STEP * dt * 4.0)

	position = position.lerp(target_pos, clampf(dt * 10.0, 0.0, 1.0))
	rotation_degrees.x = pitch_deg
	rotation_degrees.y = lerp(rotation_degrees.y, target_yaw_deg, clampf(dt * 10.0, 0.0, 1.0))
	if camera:
		camera.size = lerp(camera.size, target_zoom, clampf(dt * 12.0, 0.0, 1.0))

func _conversation_open() -> bool:
	var office := get_parent()
	if office == null:
		return false
	var player = office.get("player")
	if not is_instance_valid(player):
		return false
	var dialogue = player.get("dialogue")
	return dialogue != null and dialogue.is_open

func zoom_by(delta_zoom: float) -> void:
	target_zoom = clampf(target_zoom + delta_zoom, MIN_ZOOM, MAX_ZOOM)

func rotate_step(step_deg: float) -> void:
	target_yaw_deg += step_deg

func focus_on(world_pos: Vector3) -> void:
	target_pos = Vector3(world_pos.x, 0.0, world_pos.z) + pan_offset
	_clamp_target_pos()

func reset_view() -> void:
	pan_offset = Vector3.ZERO
	target_pos = Vector3(0.0, 0.0, 0.5)
	target_yaw_deg = 45.0
	target_zoom = 16.5

func _clamp_target_pos() -> void:
	target_pos.x = clampf(target_pos.x, pan_bounds.position.x, pan_bounds.end.x)
	target_pos.z = clampf(target_pos.z, pan_bounds.position.y, pan_bounds.end.y)
