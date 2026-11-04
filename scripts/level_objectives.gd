class_name LevelObjectives
extends RefCounted

# Levels 3–5 use existing office activities, counted from the start of the level.
const NAMES := ["First day", "Helping out", "Paper trail", "Teamwork", "Wellbeing"]
const TASKS := [
	["Drink coffee", "Talk to a coworker", "Move the box to its spot"],
	["Fix the server", "Get coffee", "Give coffee to a coworker"],
	["Write a report", "Print a report", "File a report"],
	["Share an idea", "Watch a briefing", "Give a presentation"],
	["Take a snack", "Eat a snack", "Take a stretch break"],
]
const STAT_KEYS := [[], [], ["reports_written", "pages_printed", "reports_filed"], ["ideas_shared", "briefings_watched", "presentations"], ["snacks_taken", "snacks_eaten", "stretch_breaks"]]
