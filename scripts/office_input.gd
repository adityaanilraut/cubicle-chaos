class_name OfficeInput
extends RefCounted

# Single source for remappable gameplay keys. Movement (WASD/arrows),
# run (Shift) and pause (Esc/P) stay fixed so a bad remap can never
# strand the player; every other gameplay key can be rebound in Settings.
const ACTIONS: Array[Dictionary] = [
	{"id": "interact", "label": "Interact / talk / use", "default": KEY_F},
	{"id": "secondary", "label": "Second equipment action", "default": KEY_H},
	{"id": "prop", "label": "Pick up / throw prop", "default": KEY_T},
	{"id": "place", "label": "Place prop or cup gently", "default": KEY_G},
	{"id": "grab", "label": "Grab / release furniture", "default": KEY_B},
	{"id": "fight", "label": "Light attack", "default": KEY_J},
	{"id": "heavy_attack", "label": "Heavy attack", "default": KEY_K},
	{"id": "rotate_left", "label": "Rotate camera left", "default": KEY_Q},
	{"id": "rotate_right", "label": "Rotate camera right", "default": KEY_E},
]
const RESERVED_KEYS := [
	KEY_NONE, KEY_ESCAPE, KEY_P, KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT,
	KEY_F5, KEY_F9, KEY_EQUAL, KEY_MINUS, KEY_KP_ADD, KEY_KP_SUBTRACT,
]

static var _bindings: Dictionary = {}

static func action_ids() -> Array[String]:
	var ids: Array[String] = []
	for action in ACTIONS:
		ids.append(String(action["id"]))
	return ids

static func label_for(action_id: String) -> String:
	for action in ACTIONS:
		if String(action["id"]) == action_id:
			return String(action["label"])
	return action_id

static func default_key(action_id: String) -> int:
	for action in ACTIONS:
		if String(action["id"]) == action_id:
			return int(action["default"])
	return KEY_NONE

static func key_for(action_id: String) -> int:
	if _bindings.is_empty():
		_bindings = sanitized({})
	return int(_bindings.get(action_id, default_key(action_id)))

static func key_name(action_id: String) -> String:
	return OS.get_keycode_string(key_for(action_id))

static func is_pressed(action_id: String) -> bool:
	return Input.is_key_pressed(key_for(action_id))

static func matches(event: InputEvent, action_id: String) -> bool:
	if not event is InputEventKey:
		return false
	var key_event := event as InputEventKey
	var bound := key_for(action_id)
	return key_event.keycode == bound or key_event.physical_keycode == bound

static func apply_bindings(stored: Dictionary) -> void:
	_bindings = sanitized(stored)

static func reset_bindings() -> void:
	_bindings = sanitized({})

static func is_reserved(keycode: int) -> bool:
	return RESERVED_KEYS.has(keycode)

# Keep fixed controls available and avoid assigning a key to two actions.
static func sanitized(stored: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for stored_key in stored:
		normalized[String(stored_key)] = stored[stored_key]
	var result: Dictionary = {}
	var claimed: Array[int] = []
	for action in ACTIONS:
		var id := String(action["id"])
		var keycode := int(normalized.get(id, int(action["default"])))
		if is_reserved(keycode) or claimed.has(keycode):
			keycode = int(action["default"])
		if claimed.has(keycode):
			# A newly added default may already be used by an older saved binding.
			for fallback in [KEY_L, KEY_U, KEY_I, KEY_O, KEY_Z, KEY_X, KEY_C, KEY_V]:
				if not claimed.has(fallback) and not normalized.values().has(fallback):
					keycode = fallback
					break
		if claimed.has(keycode):
			continue
		claimed.append(keycode)
		result[id] = keycode
	return result
