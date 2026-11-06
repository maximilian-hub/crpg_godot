extends Node

const Exchange := preload("res://scripts/platform/game_record_exchange.gd")

class FakeBridge extends RefCounted:
	signal document_saved(display_name: String)
	signal document_opened(contents: String, display_name: String)
	signal document_shared(display_name: String)
	signal operation_cancelled(operation: String)
	signal operation_failed(operation: String, message: String)
	var last_call := ""
	var last_filename := ""
	var last_contents := ""
	var last_limit := 0
	func saveDocument(filename: String, contents: String) -> void:
		last_call = "save"; last_filename = filename; last_contents = contents
	func openDocument(limit: int) -> void:
		last_call = "open"; last_limit = limit
	func shareDocument(filename: String, contents: String) -> void:
		last_call = "share"; last_filename = filename; last_contents = contents


func _ready() -> void:
	var failures: Array[String] = []
	var bridge := FakeBridge.new()
	var exchange = Exchange.new(bridge)
	_check(exchange.is_available(), "injected native bridge is available", failures)
	_check(exchange.save_document("../unsafe:name", "game-json") and bridge.last_call == "save", "save delegates to the native bridge", failures)
	_check(bridge.last_filename == "unsafe_name.crpggame" and bridge.last_contents == "game-json", "save sanitizes its suggested filename and preserves contents", failures)
	_check(exchange.operation_pending and not exchange.open_document(), "a second operation cannot overlap an active document request", failures)
	bridge.document_saved.emit("unsafe_name.crpggame")
	_check(not exchange.operation_pending, "native completion releases the operation gate", failures)
	_check(exchange.open_document() and bridge.last_call == "open" and bridge.last_limit == Exchange.MAX_IMPORT_BYTES, "open delegates with the hard import limit", failures)
	bridge.operation_cancelled.emit("open")
	_check(not exchange.operation_pending, "native cancellation releases the operation gate", failures)
	_check(exchange.share_document("match", "shared-json") and bridge.last_filename == "match.crpggame", "share delegates a portable attachment name", failures)
	bridge.operation_failed.emit("share", "fixture failure")
	_check(not exchange.operation_pending, "native failure releases the operation gate", failures)
	var fixed := {"year": 2026, "month": 2, "day": 3, "hour": 4, "minute": 5, "second": 6}
	_check(Exchange.suggested_filename(false, fixed) == "crpg_game_20260203_040506.crpggame", "clean game names are deterministic and sortable", failures)
	_check(Exchange.suggested_filename(true, fixed) == "crpg_report_20260203_040506.crpggame", "annotated report names are distinct", failures)
	if failures.is_empty():
		print("GAME RECORD EXCHANGE CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		printerr("GAME RECORD EXCHANGE CHARACTERIZATION: FAIL")
		for failure in failures: printerr(" - ", failure)
		get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
