extends RefCounted
class_name ChessGameRecordCodec

const RecordScript = preload("res://scripts/state/chess_game_record.gd")
const MAX_FRAMES := 10000


static func to_dictionary(record) -> Dictionary:
	var encoded_frames: Array[Dictionary] = []
	for index in range(record.frames.size()):
		var frame: Dictionary = record.frames[index]
		var position: ChessPosition = frame.get("position")
		encoded_frames.append({
			"index": index,
			"kind": String(frame.get("kind", &"gameplay")),
			"label": String(frame.get("label", "")),
			"position": ChessPositionCodec.to_dictionary(position),
			"action": _json_safe(frame.get("action", {})),
			"ai": _json_safe(frame.get("ai", {})),
			"context": _json_safe(frame.get("context", {})),
		})
	return {
		"schema": "crpg_chess_record",
		"version": RecordScript.CURRENT_SCHEMA_VERSION,
		"record_id": record.record_id,
		"created_utc": record.created_utc,
		"build": {"id": record.build_id, "engine": record.engine_version, "platform": record.platform},
		"report": {"flagged_frame": record.flagged_frame, "note": record.issue_note},
		"provenance": _json_safe(record.provenance),
		"frames": encoded_frames,
	}


static func to_json(record, pretty := true) -> String:
	return JSON.stringify(to_dictionary(record), "  " if pretty else "")


static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return {"record": null, "errors": ["JSON parse error at line %s: %s" % [json.get_error_line(), json.get_error_message()]], "warnings": []}
	if not json.data is Dictionary:
		return {"record": null, "errors": ["Game record JSON must contain an object."], "warnings": []}
	return from_dictionary(json.data)


static func from_dictionary(data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if data.get("schema", "") != "crpg_chess_record": errors.append("Unknown game record schema.")
	if int(data.get("version", -1)) != RecordScript.CURRENT_SCHEMA_VERSION: errors.append("Unsupported game record version.")
	var raw_frames = data.get("frames", [])
	if not raw_frames is Array or raw_frames.is_empty():
		errors.append("Game record must contain at least one frame.")
		raw_frames = []
	if raw_frames.size() > MAX_FRAMES: errors.append("Game record exceeds the %d-frame limit." % MAX_FRAMES)
	var record = RecordScript.new()
	record.record_id = String(data.get("record_id", record.record_id))
	record.created_utc = String(data.get("created_utc", ""))
	var build = data.get("build", {})
	if build is Dictionary:
		record.build_id = String(build.get("id", "unknown"))
		record.engine_version = String(build.get("engine", "unknown"))
		record.platform = String(build.get("platform", "unknown"))
	var current_build := String(ProjectSettings.get_setting("application/config/version", "dev"))
	if record.build_id != current_build:
		warnings.append("Recording build '%s' differs from current build '%s'; historical reproduction is not guaranteed." % [record.build_id, current_build])
	var report = data.get("report", {})
	if report is Dictionary:
		record.flagged_frame = int(report.get("flagged_frame", -1))
		record.issue_note = String(report.get("note", ""))
	var provenance = data.get("provenance", {})
	record.provenance = provenance.duplicate(true) if provenance is Dictionary else {}
	for index in range(raw_frames.size()):
		var raw = raw_frames[index]
		if not raw is Dictionary:
			errors.append("Frame %d must be an object." % index)
			continue
		var decoded := ChessPositionCodec.from_dictionary(raw.get("position", {}))
		if decoded.position == null:
			for message in decoded.errors: errors.append("Frame %d: %s" % [index, message])
			continue
		record.frames.append({
			"kind": StringName(raw.get("kind", "gameplay")),
			"label": String(raw.get("label", "")),
			"position": decoded.position,
			"action": _dictionary_or_empty(raw.get("action", {})),
			"ai": _dictionary_or_empty(raw.get("ai", {})),
			"context": _dictionary_or_empty(raw.get("context", {})),
		})
	if record.flagged_frame >= record.frames.size(): errors.append("Flagged frame is outside the timeline.")
	return {"record": record if errors.is_empty() else null, "errors": errors, "warnings": warnings}


static func save_file(record, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(to_json(record))
	return OK


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"record": null, "errors": ["Could not open %s." % path], "warnings": []}
	return from_json(file.get_as_text())


static func _dictionary_or_empty(value) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


static func _json_safe(value):
	if value is Vector2i: return [value.x, value.y]
	if value is StringName: return String(value)
	if value is Dictionary:
		var result := {}
		for key in value: result[String(key)] = _json_safe(value[key])
		return result
	if value is Array:
		return value.map(func(item): return _json_safe(item))
	return value
