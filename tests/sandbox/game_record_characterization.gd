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
	_check(not sandbox.replay_flag_button.disabled, "the current live recording frame can be flagged before export", failures)
	sandbox._flag_replay_frame()
	var record = sandbox._record_from_history()
	record.issue_note = "Unexpected test behavior"
	record.issue_report = {"category": "Tactical mistake", "urgency": "Immediate / tactical", "observed": "Ignored a free queen", "expected": "Capture the queen", "reasoning": "The capture was safe"}
	_check(record.flagged_frame == 1, "live frame flags are retained by the exported recording", failures)
	record.frames[1].ai = {
		"brain_id": "ryck", "color": "white", "score": 0.0,
		"selected": {"target": [4, 4]}, "candidates": [],
		"pre_decision_context": sandbox.game.white_cpu_player.capture_debug_context(),
	}
	record.frames[1].selections = [{"kind": "promotion", "option": "queen"}, {"kind": "raise_dead", "option": [3, 4]}]
	var json := RecordCodec.to_json(record)
	var decoded: Dictionary = RecordCodec.from_json(json)
	_check(decoded.record != null and decoded.record.frames.size() == 2, "record JSON round-trips complete timelines", failures)
	_check(decoded.record.flagged_frame == 1 and decoded.record.issue_note == "Unexpected test behavior" and decoded.record.issue_report.observed == "Ignored a free queen", "record JSON preserves structured and legacy issue notes", failures)
	var decoded_selections: Array = decoded.record.frames[1].selections
	var decoded_target: Array = decoded_selections[1].option if decoded_selections.size() > 1 else []
	_check(decoded_selections.size() == 2 and decoded_target.size() == 2 and int(decoded_target[0]) == 3 and int(decoded_target[1]) == 4, "record JSON preserves ordered secondary-choice transcripts", failures)
	var clean_record = decoded.record.copy()
	clean_record.clear_issue_report()
	_check(clean_record.flagged_frame == -1 and clean_record.issue_report.is_empty() and decoded.record.flagged_frame == 1, "clean sharing removes annotations from a copy without mutating the report", failures)
	_check(ChessPositionCodec.to_json(decoded.record.frames[0].position) == before_json, "record frames retain authoritative complete positions", failures)
	var allocator_position: ChessPosition = decoded.record.frames[0].position.copy()
	allocator_position.next_state_id = 73
	var allocator_round_trip := ChessPositionCodec.from_json(ChessPositionCodec.to_json(allocator_position, false)).position as ChessPosition
	_check(allocator_round_trip != null and allocator_round_trip.next_state_id == 73, "position snapshots preserve the generated-state ID allocator", failures)
	var numeric_expected := allocator_position.copy()
	var numeric_actual := allocator_position.copy()
	if not numeric_expected.pieces.is_empty():
		numeric_expected.pieces[0].custom_state["comparison_counter"] = 10.0
		numeric_actual.pieces[0].custom_state["comparison_counter"] = 10
	_check(sandbox._canonical_position(numeric_expected) == sandbox._canonical_position(numeric_actual), "replay comparison treats equivalent integral JSON numbers as equal", failures)
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
	sandbox.queue_free()
	await get_tree().process_frame
	var playback = SANDBOX.instantiate()
	add_child(playback)
	await get_tree().process_frame
	playback._set_mode(playback.Mode.PLAY)
	var pawn: ModelPiece = playback.model.board[6][0]
	_check(await playback.model.submit_move(pawn, Vector2i(4, 0)), "animated replay fixture executes its source move", failures)
	var black_pawn: ModelPiece = playback.model.board[1][0]
	_check(await playback.model.submit_move(black_pawn, Vector2i(3, 0)), "animated replay fixture records a second turn", failures)
	var played_record = playback._record_from_history().copy()
	_check(played_record.frames.size() == 3 and played_record.frames[1].transition == &"action" and played_record.frames[1].selections.is_empty(), "settled gameplay records an executable turn transcript", failures)
	var played_destination := ChessPositionCodec.to_json(played_record.frames[1].position)
	_check(playback.import_record_text(RecordCodec.to_json(played_record, false)) and playback.replay_cursor == 0, "unflagged game import opens at its starting position", failures)
	var replay_action_count := [0]
	playback.model.action_started.connect(func(_color):
		if playback.replay_playing:
			replay_action_count[0] += 1
			playback.replay_pause_requested = true
	)
	await playback._start_replay_playback()
	_check(playback.replay_cursor == 1 and replay_action_count[0] == 1 and not playback.replay_playing, "Pause requested during animation finishes the current turn without starting the next", failures)
	playback._load_replay_frame(0)
	await playback._replay_next_turn()
	_check(playback.replay_cursor == 1 and ChessPositionCodec.to_json(playback.model.capture_position()) == played_destination, "Next Turn authoritatively replays and settles one animated turn", failures)
	playback._replay_previous_turn()
	_check(playback.replay_cursor == 0, "Previous Turn jumps to the preceding settled position", failures)
	if failures.is_empty():
		print("GAME RECORD CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		printerr("GAME RECORD CHARACTERIZATION: FAIL")
		for failure in failures: printerr(" - ", failure)
		get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
