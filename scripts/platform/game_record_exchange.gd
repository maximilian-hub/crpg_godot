extends RefCounted
class_name GameRecordExchange

signal document_saved(display_name: String)
signal document_opened(contents: String, display_name: String)
signal document_shared(display_name: String)
signal operation_cancelled(operation: String)
signal operation_failed(operation: String, message: String)

const SINGLETON_NAME := "CrpgDocumentExchange"
const MAX_IMPORT_BYTES := 16 * 1024 * 1024

var bridge: Object
var operation_pending := false


func _init(bridge_override: Object = null) -> void:
	bridge = bridge_override
	if bridge == null and Engine.has_singleton(SINGLETON_NAME):
		bridge = Engine.get_singleton(SINGLETON_NAME)
	_connect_bridge()


func is_available() -> bool:
	return bridge != null


func save_document(filename: String, contents: String) -> bool:
	if not _begin(&"save"): return false
	bridge.saveDocument(sanitize_filename(filename), contents)
	return true


func open_document() -> bool:
	if not _begin(&"open"): return false
	bridge.openDocument(MAX_IMPORT_BYTES)
	return true


func share_document(filename: String, contents: String) -> bool:
	if not _begin(&"share"): return false
	bridge.shareDocument(sanitize_filename(filename), contents)
	return true


func _begin(operation: StringName) -> bool:
	if bridge == null:
		operation_failed.emit(String(operation), "Native document exchange is unavailable.")
		return false
	if operation_pending:
		operation_failed.emit(String(operation), "Another document operation is already active.")
		return false
	operation_pending = true
	return true


func _connect_bridge() -> void:
	if bridge == null: return
	bridge.document_saved.connect(func(display_name: String):
		operation_pending = false
		document_saved.emit(display_name)
	)
	bridge.document_opened.connect(func(contents: String, display_name: String):
		operation_pending = false
		if contents.to_utf8_buffer().size() > MAX_IMPORT_BYTES:
			operation_failed.emit("open", "Selected file exceeds the 16 MiB import limit.")
			return
		document_opened.emit(contents, display_name)
	)
	bridge.document_shared.connect(func(display_name: String):
		operation_pending = false
		document_shared.emit(display_name)
	)
	bridge.operation_cancelled.connect(func(operation: String):
		operation_pending = false
		operation_cancelled.emit(operation)
	)
	bridge.operation_failed.connect(func(operation: String, message: String):
		operation_pending = false
		operation_failed.emit(operation, message)
	)


static func suggested_filename(report := false, datetime: Dictionary = {}) -> String:
	var stamp := datetime if not datetime.is_empty() else Time.get_datetime_dict_from_system(true)
	return "crpg_%s_%04d%02d%02d_%02d%02d%02d.crpggame" % [
		"report" if report else "game", int(stamp.year), int(stamp.month), int(stamp.day),
		int(stamp.hour), int(stamp.minute), int(stamp.second),
	]


static func sanitize_filename(value: String) -> String:
	var filename := value.get_file().strip_edges()
	if filename.is_empty(): filename = "crpg_game.crpggame"
	for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		filename = filename.replace(character, "_")
	if not filename.to_lower().ends_with(".crpggame"):
		filename += ".crpggame"
	return filename
