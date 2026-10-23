extends RefCounted
class_name DupreOpeningBook

## Runtime reader for the compact, offline-generated Dupre repertoire. Source
## parsing and authoritative validation live in tools/opening_import.

const RUNTIME_PATH := "res://assets/data/openings/dupre_openings_runtime.json"
const RUNTIME_DATA = preload("res://assets/data/openings/dupre_openings_runtime.json")

static var _data: Dictionary = {}
static var _families_by_id: Dictionary = {}
static var _load_usec := 0
static var _data_bytes := 0


static func families() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	result.assign(_data.get("families", []))
	return result


static func family(family_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _families_by_id.get(family_id, {})


static func child_descriptors(family_id: StringName, node_id: int, color: String) -> Array[Dictionary]:
	var selected := family(family_id)
	var result: Array[Dictionary] = []
	var nodes: Array = selected.get("nodes", [])
	if node_id < 0 or node_id >= nodes.size():
		return result
	for descriptor_value in nodes[node_id].get("children", []):
		var descriptor := _descriptor_from_compact(descriptor_value)
		if descriptor.get("color", "") == color:
			result.append(descriptor)
	return result


static func matching_child_node(family_id: StringName, node_id: int, descriptor: Dictionary) -> int:
	for child in child_descriptors(family_id, node_id, String(descriptor.get("color", ""))):
		if descriptors_equal(child, descriptor):
			return int(child.get("node", -1))
	return -1


static func recovery_descriptors(family_id: StringName, color: String, own_move_index: int) -> Array[Dictionary]:
	var selected := family(family_id)
	var result: Array[Dictionary] = []
	var move_catalog: Dictionary = selected.get("moves", {})
	for uci in selected.get("recovery", {}).get("%s:%s" % [color, own_move_index], []):
		if move_catalog.has(uci):
			var identity: Array = move_catalog[uci]
			result.append(_descriptor_from_compact([uci, identity[0], identity[1], -1]))
	return result


static func load_metrics() -> Dictionary:
	_ensure_loaded()
	return {"load_usec": _load_usec, "data_bytes": _data_bytes, "family_count": _families_by_id.size()}


static func clear_cache_for_tests() -> void:
	_data.clear()
	_families_by_id.clear()
	_load_usec = 0
	_data_bytes = 0


static func descriptors_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("kind", -1)) == int(b.get("kind", -1))
		and String(a.get("color", "")) == String(b.get("color", ""))
		and StringName(a.get("piece", "")) == StringName(b.get("piece", ""))
		and a.get("from", Vector2i(-1, -1)) == b.get("from", Vector2i(-1, -1))
		and a.get("to", Vector2i(-1, -1)) == b.get("to", Vector2i(-1, -1))
		and a.get("path", [a.get("to")]) == b.get("path", [b.get("to")])
	)


static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	var started := Time.get_ticks_usec()
	_data_bytes = FileAccess.get_file_as_bytes(RUNTIME_PATH).size()
	var parsed = RUNTIME_DATA.data
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		push_error("Dupre opening book is missing or invalid: " + RUNTIME_PATH)
		_data = {"families": []}
		_load_usec = Time.get_ticks_usec() - started
		return
	# Duplicate only the top-level dictionary so test cache resets never mutate
	# the preloaded JSON resource; nested generated data remains immutable.
	_data = parsed.duplicate(false)
	for family_value in _data.get("families", []):
		var selected: Dictionary = family_value
		_families_by_id[StringName(selected.get("id", ""))] = selected
	_load_usec = Time.get_ticks_usec() - started


static func _descriptor_from_compact(compact: Array) -> Dictionary:
	var uci := String(compact[0])
	var from := _uci_coordinate(uci.substr(0, 2))
	var to := _uci_coordinate(uci.substr(2, 2))
	return {
		"kind": ChessPrimaryAction.Kind.MOVE,
		"color": "white" if String(compact[2]) == "w" else "black",
		"piece": StringName(compact[1]),
		"from": from,
		"to": to,
		"path": [to],
		"uci": uci,
		"node": int(compact[3]),
	}


static func _uci_coordinate(square: String) -> Vector2i:
	return Vector2i(7 - (square.unicode_at(1) - "1".unicode_at(0)), square.unicode_at(0) - "a".unicode_at(0))
