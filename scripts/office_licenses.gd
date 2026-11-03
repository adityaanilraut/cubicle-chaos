# SPDX-License-Identifier: MIT
class_name OfficeLicenses
extends RefCounted

static func text() -> String:
	var sections := PackedStringArray()
	for entry in [["Project license", "res://LICENSE"], ["Credits and sources", "res://THIRD_PARTY_NOTICES.md"], ["Noto Emoji font license", "res://assets/fonts/OFL.txt"], ["Kenney Furniture Kit", "res://kenney_furniture-kit/License.txt"]]:
		sections.append(String(entry[0]) + "\n\n" + FileAccess.get_file_as_string(entry[1]))
	sections.append("Godot Engine\n\n" + Engine.get_license_text())
	var copyrights := PackedStringArray(["Godot Engine third-party copyrights"])
	for component in Engine.get_copyright_info():
		copyrights.append("\n" + String(component.name))
		for part in component.parts:
			copyrights.append("\n".join(part.copyright))
			copyrights.append("License: " + String(part.license))
			copyrights.append("Files: " + ", ".join(part.files))
	sections.append("\n".join(copyrights))
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name in names:
		sections.append(String(name) + "\n\n" + String(licenses[name]))
	return "\n\n────────────────────────────────\n\n".join(sections)
