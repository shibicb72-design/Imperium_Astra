class_name JsonData
extends RefCounted
## Loads res://data/*.json files. Fails loudly (push_error) and returns {} on any problem.


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JsonData: missing file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("JsonData: %s is not a JSON object" % path)
	return {}
