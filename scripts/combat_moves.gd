class_name CombatMoves
extends RefCounted

# Every strike shares the same contact rules; choreography and timing vary.
const SEQUENCE := ["jab", "cross", "hook", "front_kick", "palm", "side_kick", "uppercut", "roundhouse", "sweep", "spinning_kick"]
const LIGHT_SEQUENCE := ["jab", "cross", "hook", "palm", "uppercut"]
const HEAVY_SEQUENCE := ["front_kick", "side_kick", "roundhouse", "sweep", "spinning_kick"]
const LONG_RANGE := ["front_kick", "side_kick", "roundhouse", "spinning_kick"]
const MOVES := {
	"jab": {"label": "Lead jab", "family": "punch", "style": "Karate", "side": "Left", "reach": 1.20, "contact": 0.16, "duration": 0.40, "cooldown": 0.46, "damage": 12.0, "balance": 20.0, "push": 0.8, "height": 1.35},
	"cross": {"label": "Reverse punch", "family": "punch", "style": "Karate", "side": "Right", "reach": 1.20, "contact": 0.19, "duration": 0.54, "cooldown": 0.66, "damage": 18.0, "balance": 36.0, "push": 1.5, "height": 1.35},
	"hook": {"label": "Hook punch", "family": "punch", "style": "Kung fu", "side": "Left", "reach": 1.10, "contact": 0.24, "duration": 0.57, "cooldown": 0.63, "damage": 20.0, "balance": 32.0, "push": 1.3, "height": 1.35},
	"uppercut": {"label": "Rising uppercut", "family": "punch", "style": "Kung fu", "side": "Right", "reach": 1.15, "contact": 0.25, "duration": 0.60, "cooldown": 0.67, "damage": 22.0, "balance": 38.0, "push": 1.4, "height": 1.45},
	"palm": {"label": "Tiger palm", "family": "punch", "style": "Kung fu", "side": "Left", "reach": 1.25, "contact": 0.21, "duration": 0.52, "cooldown": 0.59, "damage": 16.0, "balance": 30.0, "push": 1.7, "height": 1.20},
	"front_kick": {"label": "Front kick", "family": "kick", "style": "Karate", "side": "Right", "reach": 1.65, "contact": 0.32, "duration": 0.82, "cooldown": 1.05, "damage": 30.0, "balance": 55.0, "push": 2.6, "height": 1.0},
	"side_kick": {"label": "Side kick", "family": "kick", "style": "Karate", "side": "Left", "reach": 1.65, "contact": 0.34, "duration": 0.79, "cooldown": 0.91, "damage": 27.0, "balance": 46.0, "push": 2.4, "height": 1.05},
	"roundhouse": {"label": "Roundhouse kick", "family": "kick", "style": "Kung fu", "side": "Right", "reach": 1.65, "contact": 0.38, "duration": 0.88, "cooldown": 0.98, "damage": 28.0, "balance": 48.0, "push": 2.0, "height": 1.30},
	"sweep": {"label": "Low sweep", "family": "kick", "style": "Kung fu", "side": "Left", "reach": 1.40, "contact": 0.35, "duration": 0.84, "cooldown": 0.94, "damage": 18.0, "balance": 60.0, "push": 1.2, "height": 0.28},
	"spinning_kick": {"label": "Spinning heel kick", "family": "kick", "style": "Kung fu", "side": "Right", "reach": 1.65, "contact": 0.48, "duration": 1.02, "cooldown": 1.12, "damage": 32.0, "balance": 54.0, "push": 2.7, "height": 1.20},
}

static func resolve_id(id: String) -> String:
	# Keep scripted punch/kick callers compatible with the expanded move set.
	if id == "punch": return "cross"
	if id == "kick": return "front_kick"
	return id

static func get_move(id: String) -> Dictionary:
	return MOVES.get(resolve_id(id), {})
