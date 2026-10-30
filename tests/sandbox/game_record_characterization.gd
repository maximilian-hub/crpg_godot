extends Node

const SANDBOX := preload("res://scenes/sandbox/board_sandbox.tscn")
const RecordCodec := preload("res://scripts/state/chess_game_record_codec.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var sandbox = SANDBOX.instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	_check(sandbox.history.entries.size() == 1 and sandbox.history.metadata[0].kind == &"baseline", "sandbox starts an always-on recording baseline", failures)
	var before_json := ChessPositionCodec.to_json(sandbox.model.capture_position())
	sandbox.editor.select_palette_piece(&"pawn", "white")
	sandbox.editor.place_selected(Vector2i(4, 4))
	_check(sandbox.history.entries.size() == 2 and sandbox.history.metadata[1].kind == &"edit", "editor mutations append typed recording frames", failures)
	sandbox.game.white_cpu_player.is_thinking = true
	sandbox._refresh_control_states()
	sandbox._set_mode(sandbox.Mode.PLAY)
	sandbox.undo()
	_check(sandbox.mode == sandbox.Mode.EDIT and sandbox.history.cursor == 1 and sandbox.undo_button.disabled and sandbox.mode_button.disabled, "history and mode changes are blocked while an AI search is in flight", failures)
	sandbox.game.white_cpu_player.is_thinking = false
	sandbox._refresh_control_states()
	var record = sandbox._record_from_history()
	record.flagged_frame = 1
	record.issue_note = "Unexpected test behavior"
	record.frames[1].ai = {
		"brain_id": "ryck", "color": "white", "score": 0.0,
		"selected": {"target": [4, 4]}, "candidates": [],
		"pre_decision_context": sandbox.game.white_cpu_player.capture_debug_context(),
	}
	var json := RecordCodec.to_json(record)
	var decoded: Dictionary = RecordCodec.from_json(json)
	_check(decoded.record != null and decoded.record.frames.size() == 2, "record JSON round-trips complete timelines", failures)
	_check(decoded.record.flagged_frame == 1 and decoded.record.issue_note == "Unexpected test behavior", "record JSON preserves the flagged frame and issue note", failures)
	_check(ChessPositionCodec.to_json(decoded.record.frames[0].position) == before_json, "record frames retain authoritative complete positions", failures)
	_check(sandbox.import_record_text(json) and sandbox.replay_mode and sandbox.replay_cursor == 1, "record import enters replay at the flagged frame", failures)
	_check(not sandbox.editor.editor_enabled and not sandbox.piece_palette.palette_enabled, "replay mode is immutable", failures)
	await sandbox.analyze_replay_again()
	_check(sandbox.replay_mode and sandbox.replay_cursor == 1 and sandbox.record_status_label.text.contains("Recorded target"), "Analyze Again compares the current brain without altering replay", failures)
	sandbox._replay_previous()
	_check(sandbox.replay_cursor == 0 and ChessPositionCodec.to_json(sandbox.model.capture_position()) == before_json, "replay navigation restores snapshots instantly", failures)
	sandbox._replay_next()
	sandbox.fork_replay_here()
	_check(not sandbox.replay_mode and sandbox.history.entries.size() == 1 and sandbox.record_provenance.parent_frame == 1, "Fork Here creates a new live baseline with provenance", failures)
	var path := "/private/tmp/game_record_characterization.crpggame"
	_check(RecordCodec.save_file(record, path) == OK and RecordCodec.load_file(path).record != null, "record files save and load through the portable codec", failures)
	_check(not sandbox.import_record_text("{broken"), "malformed imports fail without replacing live state", failures)
	if failures.is_empty():
		print("GAME RECORD CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		printerr("GAME RECORD CHARACTERIZATION: FAIL")
		for failure in failures: printerr(" - ", failure)
		get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
