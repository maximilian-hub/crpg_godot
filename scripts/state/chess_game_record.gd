extends RefCounted
class_name ChessGameRecord

const CURRENT_SCHEMA_VERSION := 1

var record_id := ""
var created_utc := ""
var build_id := "dev"
var engine_version := ""
var platform := ""
var frames: Array[Dictionary] = []
var flagged_frame := -1
var issue_note := ""
var provenance: Dictionary = {}


func _init() -> void:
	if record_id.is_empty():
		record_id = "%s-%s" % [Time.get_unix_time_from_system(), randi()]
	created_utc = Time.get_datetime_string_from_system(true)
	engine_version = Engine.get_version_info().get("string", "unknown")
	platform = OS.get_name()
	build_id = String(ProjectSettings.get_setting("application/config/version", "dev"))


func copy():
	var result = get_script().new()
	result.record_id = record_id
	result.created_utc = created_utc
	result.build_id = build_id
	result.engine_version = engine_version
	result.platform = platform
	result.frames = frames.duplicate(true)
	result.flagged_frame = flagged_frame
	result.issue_note = issue_note
	result.provenance = provenance.duplicate(true)
	return result
