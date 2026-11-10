extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_material_and_center_metrics()
	_test_check_includes_active_abilities()
	_test_mate_threat_requires_every_response_to_fail()
	_test_starting_position_cost()
	await _test_runtime_counters()
	await _test_panel_scene_wiring()
	if failures.is_empty():
		print("MATCH INSIGHTS CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _test_material_and_center_metrics() -> void:
	var state := _state([
		_piece(&"classic_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 7)),
		_piece(&"queen", "white", Vector2i(4, 3)),
		_piece(&"pawn", "white", Vector2i(4, 4)),
		_piece(&"rook", "black", Vector2i(3, 3)),
	])
	var material := ChessMatchInsights.material_counts(state)
	var center := ChessMatchInsights.center_counts(state)
	_expect(int(material.white) == 10 and int(material.black) == 5, "material uses ordinary chess values and excludes Kings")
	_expect(int(center.white) == 2 and int(center.black) == 1 and ChessMatchInsights.leading_color(center) == "white", "center control counts occupancy on d4/e4/d5/e5")


func _test_check_includes_active_abilities() -> void:
	var minotaur := _piece(&"minotaur_king", "black", Vector2i(0, 4), 3)
	minotaur.current_cooldown = 0
	minotaur.cooldown_reset_pending = false
	var state := _state([
		_piece(&"classic_king", "white", Vector2i(4, 4)),
		minotaur,
	])
	_expect(ChessMatchInsights.is_king_in_check(state, "white"), "a ready damaging active ability counts as check even without an ordinary attack")


func _test_mate_threat_requires_every_response_to_fail() -> void:
	var safe := _state([
		_piece(&"classic_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 0)),
	])
	_expect(not ChessMatchInsights.is_king_mate_threatened(safe, "white"), "one safe King move prevents a mate-threat classification")

	var trapped_king := _piece(&"classic_king", "white", Vector2i(7, 7))
	trapped_king.stunned = true
	trapped_king.stun_timer = 2
	var inevitable := _state([
		trapped_king,
		_piece(&"classic_king", "black", Vector2i(0, 0)),
		_piece(&"queen", "black", Vector2i(5, 5)),
	])
	_expect(ChessMatchInsights.is_king_mate_threatened(inevitable, "white"), "a forced pass with unavoidable next-turn King damage counts as a mate threat")


func _test_starting_position_cost() -> void:
	var pieces: Array[ChessCorePiece] = []
	var back_types: Array[StringName] = [&"rook", &"knight", &"bishop", &"queen", &"classic_king", &"bishop", &"knight", &"rook"]
	for color in ["black", "white"]:
		var back := 0 if color == "black" else 7
		var pawn_row := 1 if color == "black" else 6
		for column in range(8):
			pieces.append(_piece(back_types[column], color, Vector2i(back, column)))
			pieces.append(_piece(&"pawn", color, Vector2i(pawn_row, column)))
	var state := _state(pieces)
	var started := Time.get_ticks_usec()
	var mate_threat := ChessMatchInsights.is_king_mate_threatened(state, "white")
	var elapsed := Time.get_ticks_usec() - started
	print("MATCH INSIGHTS START-POSITION ANALYSIS: %.2f ms" % (float(elapsed) / 1000.0))
	_expect(not mate_threat, "the normal starting position is not classified as a mate threat")
	_expect(elapsed < 500000, "normal-position mate analysis remains suitable for a per-turn diagnostic (%d usec)" % elapsed)


func _test_runtime_counters() -> void:
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var target_king := MinotaurKing.new("black", Vector2i(3, 3))
	var ability_model := _model([
		arakne,
		target_king,
	])
	ability_model.active_ability_cooldowns_disabled = true
	var ability_tracker := ChessMatchInsights.new()
	add_child(ability_tracker)
	ability_tracker.configure(ability_model)
	_expect(await ability_model.submit_active_ability(arakne, target_king.coordinate), "runtime counter fixture accepts a King ability")
	_expect(int(ability_tracker.ability_uses.white) == 1, "a settled active ability increments its side's use counter")
	ability_tracker.queue_free()
	ability_model.queue_free()

	var waiting_king := ArakneKing.new("white", Vector2i(7, 7))
	var pawn := Pawn.new("white", Vector2i(6, 0))
	var move_model := _model([
		waiting_king,
		ClassicKing.new("black", Vector2i(0, 7)),
		pawn,
	])
	move_model.active_ability_cooldowns_disabled = true
	var move_tracker := ChessMatchInsights.new()
	add_child(move_tracker)
	move_tracker.configure(move_model)
	_expect(await move_model.submit_move(pawn, Vector2i(5, 0)), "runtime counter fixture accepts a normal move")
	_expect(int(move_tracker.ready_turns_unused.white) == 1, "a normal action while the King ability is ready increments ready-turns-unused")
	move_tracker.queue_free()
	move_model.queue_free()


func _test_panel_scene_wiring() -> void:
	var original_size := Vector2i(get_viewport().size)
	get_viewport().size = Vector2i(1920, 1080)
	var game := load("res://scenes/chess_game.tscn").instantiate() as ChessGame
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	game.play_opening_presentation = false
	game.apply_initial_piece_placement_variation = false
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := game.get_node("LunacyLayer/LunacyUI/MatchInsightsPanel") as ChessMatchInsightsPanel
	_expect(panel != null and panel.tracker != null, "the battle scene wires the insights panel to a live tracker")
	_expect(panel.is_enabled_for_platform(true) and panel.is_enabled_for_platform(false), "the insights panel defaults on for Android and desktop")
	_expect(panel.visible, "the insights panel is visible in the usual desktop build by default")
	_expect(panel != null and "Even" in (panel.value_labels.material as Label).text, "the panel renders its initial material summary")
	var board := game.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	var board_left := 1920.0
	for point in board.projection.get_board_outline():
		board_left = minf(board_left, point.x)
	_expect(
		is_equal_approx(panel.position.x, ChessMatchInsightsPanel.EDGE_MARGIN)
		and is_equal_approx(panel.position.y + panel.size.y, 1080.0 - ChessMatchInsightsPanel.EDGE_MARGIN)
		and panel.position.x + panel.size.x < board_left,
		"the desktop panel is anchored to the screen's bottom-left without overlapping the board"
	)
	game.free()
	get_viewport().size = original_size


func _state(pieces: Array[ChessCorePiece]) -> ChessCoreState:
	var state := ChessCoreState.new()
	state.current_turn = "white"
	var next_id := 1
	for piece in pieces:
		piece.piece_id = "piece_%d" % next_id
		next_id += 1
		state.add_piece(piece)
	state.next_state_id = next_id
	return state


func _piece(type_id: StringName, color: String, coordinate: Vector2i, hp := 1) -> ChessCorePiece:
	var piece := ChessCorePiece.new()
	piece.type_id = type_id
	piece.color = color
	piece.coordinate = coordinate
	piece.max_hp = hp
	piece.current_hp = hp
	return piece


func _model(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	model.active_ability_cooldowns_disabled = true
	add_child(model)
	for _row in range(8):
		model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true
	model.current_turn = "white"
	for piece in pieces:
		model.add_piece(piece, piece.coordinate)
	return model


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
