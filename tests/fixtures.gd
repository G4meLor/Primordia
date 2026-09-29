## Static helper for tests: load a JSON fixture from res://tests/fixtures/.
class_name Fixtures

static func load_json(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	if f == null:
		push_error("Fixtures.load_json: missing res://tests/fixtures/%s.json" % name)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary
