extends Node

const EndgamePolicy = preload("res://scripts/ai/dupre_endgame_policy.gd")
const MATERIAL := {"pawn": 1.0, "bone_pawn": 1.0, "knight": 3.0, "bishop": 3.0, "rook": 5.0, "queen": 9.0}

var failures: Array[String] = []
var soak_profile := false
var trace_requested := false


func _ready() -> void:
	soak_profile = "--endgame-profile=soak" in OS.get_cmdline_user_args()
	var seeds := [41021, 73013, 99041] if soak_profile else [41021]
	var max_plies := 40 if soak_profile else 8
	var fixtures := [&"pawn_race", &"winning_race", &"losing_race", &"rook_conversion", &"rook_pressure", &"advanced_passer", &"arakne_endgame", &"necromancer_endgame"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--endgame-fixture="):
			fixtures = [StringName(argument.trim_prefix("--endgame-fixture="))]
			trace_requested = true
	var runs: Array[Dictionary] = []
	for fixture in fixtures:
		for seed in seeds:
			for enabled in [false, true]:
				runs.append(await _play(fixture, seed, enabled, max_plies))
	var summary := _summarize(runs)
	_validate(runs, summary)
	print("DUPRE ENDGAME GAMEPLAY SOAK: ", JSON.stringify(summary))
	if failures.is_empty():
		print("DUPRE ENDGAME GAMEPLAY SOAK: PASS")
		get_tree().quit(0)
		return
	printerr("DUPRE ENDGAME GAMEPLAY SOAK: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _play(fixture: StringName, seed: int, enabled: bool, max_plies: int) -> Dictionary:
	var model := _fixture(fixture)
	var white := _cpu(model, "white", seed, enabled)
	var black := _cpu(model, "black", seed + 1, enabled)
	var focus_color := "white" if fixture != &"advanced_passer" else "black"
	var initial_material := _material_balance(model, focus_color)
	var initial_queens := _piece_count(model, focus_color, "queen")
	var repeated_positions := 0
	var reversals := 0
	var unverified := 0
	var null_thoughts := 0
	var execution_failures := 0
	var state_copy_usec := 0
	var replies := 0
	var decision_usec := 0
	var maximum_decision_usec := 0
	var maximum_uninterrupted_usec := 0
	var endgame_evaluation_usec := 0
	var position_counts := {}
	var previous_by_piece := {}
	var plies := 0
	var actions := []
	for _ply in range(max_plies):
		if model.battle_over: break
		var cpu := white if model.current_turn == "white" else black
		var started := Time.get_ticks_usec()
		var thought = await cpu.think()
		var elapsed := Time.get_ticks_usec() - started
		decision_usec += elapsed
		maximum_decision_usec = maxi(maximum_decision_usec, elapsed)
		if thought == null:
			null_thoughts += 1
			break
		var profile: Dictionary = thought.search_profile
		if bool(profile.get("unverified_selection", false)): unverified += 1
		actions.append({
			"color": thought.color, "piece": String(thought.piece_type_id),
			"from": str(thought.piece_coordinate), "to": str(thought.target),
			"score": thought.score, "unverified": bool(profile.get("unverified_selection", false)),
			"fallback_risk": int(profile.get("selected_fallback_risk", -1)),
			"forcing_complete": bool(profile.get("selected_forcing_coverage_complete", false)),
			"known_loss": float(profile.get("selected_known_loss", 0.0)),
			"repetition_count": int(profile.get("selected_repetition_count", 0)),
			"repetition_penalty": float(profile.get("selected_repetition_penalty", 0.0)),
		})
		state_copy_usec += int(profile.get("state_copy_usec", 0))
		replies += int(profile.get("evaluated_reply_count", 0)) + int(profile.get("quiescence_node_count", 0))
		maximum_uninterrupted_usec = maxi(maximum_uninterrupted_usec, int(profile.get("maximum_uninterrupted_usec", 0)))
		endgame_evaluation_usec += int(profile.get("endgame_evaluation_usec", 0)) + int(profile.get("endgame_policy_usec", 0))
		var moving_piece: ModelPiece = model.board[thought.piece_coordinate.x][thought.piece_coordinate.y]
		var piece_id := moving_piece.piece_id if moving_piece != null else "%s|%s" % [thought.color, thought.piece_type_id]
		var previous: Dictionary = previous_by_piece.get(piece_id, {})
		if previous.get("from", Vector2i(-1, -1)) == thought.target and previous.get("to", Vector2i(-1, -1)) == thought.piece_coordinate:
			reversals += 1
		previous_by_piece[piece_id] = {"from": thought.piece_coordinate, "to": thought.target}
		if not await cpu.execute_thought():
			execution_failures += 1
			break
		plies += 1
		var key := ChessPositionCodec.to_json(model.capture_position(), false)
		position_counts[key] = int(position_counts.get(key, 0)) + 1
		if int(position_counts[key]) > 1: repeated_positions += 1
	var analysis := EndgamePolicy.analyze_model(model, focus_color)
	var result := {
		"fixture": String(fixture), "seed": seed, "enabled": enabled,
		"plies": plies, "result": model.battle_result, "focus_color": focus_color,
		"material_delta": _material_balance(model, focus_color) - initial_material,
		"promotions": maxi(0, _piece_count(model, focus_color, "queen") - initial_queens),
		"endgame_score": float(analysis.score),
		"friendly_passers": int(analysis.friendly_passed_pawns),
		"enemy_passers": int(analysis.enemy_passed_pawns),
		"reversals": reversals, "repeated_positions": repeated_positions,
		"unverified": unverified, "null_thoughts": null_thoughts,
		"execution_failures": execution_failures,
		"decision_usec": decision_usec, "maximum_decision_usec": maximum_decision_usec,
		"maximum_uninterrupted_usec": maximum_uninterrupted_usec,
		"searched_work": replies, "state_copy_usec": state_copy_usec,
		"endgame_evaluation_usec": endgame_evaluation_usec,
	}
	if trace_requested: result["actions"] = actions
	white.queue_free(); black.queue_free(); model.queue_free()
	await get_tree().process_frame
	return result


func _summarize(runs: Array[Dictionary]) -> Dictionary:
	var totals := {"disabled": _empty_totals(), "enabled": _empty_totals()}
	for run in runs:
		var key := "enabled" if bool(run.enabled) else "disabled"
		var total: Dictionary = totals[key]
		total.runs += 1; total.plies += int(run.plies)
		total.material_delta += float(run.material_delta); total.promotions += int(run.promotions)
		total.endgame_score += float(run.endgame_score)
		total.reversals += int(run.reversals); total.repeated_positions += int(run.repeated_positions)
		total.unverified += int(run.unverified); total.null_thoughts += int(run.null_thoughts)
		total.execution_failures += int(run.execution_failures)
		total.decision_usec += int(run.decision_usec); total.searched_work += int(run.searched_work)
		total.state_copy_usec += int(run.state_copy_usec); total.endgame_evaluation_usec += int(run.endgame_evaluation_usec)
		total.maximum_decision_usec = maxi(int(total.maximum_decision_usec), int(run.maximum_decision_usec))
		total.maximum_uninterrupted_usec = maxi(int(total.maximum_uninterrupted_usec), int(run.maximum_uninterrupted_usec))
	return {"profile": "soak" if soak_profile else "gate", "totals": totals, "runs": runs}


func _empty_totals() -> Dictionary:
	return {"runs": 0, "plies": 0, "material_delta": 0.0, "promotions": 0, "endgame_score": 0.0, "reversals": 0, "repeated_positions": 0, "unverified": 0, "null_thoughts": 0, "execution_failures": 0, "decision_usec": 0, "maximum_decision_usec": 0, "maximum_uninterrupted_usec": 0, "searched_work": 0, "state_copy_usec": 0, "endgame_evaluation_usec": 0}


func _validate(runs: Array[Dictionary], summary: Dictionary) -> void:
	for run in runs:
		if int(run.null_thoughts) > 0: failures.append("%s produced no action with endgame policy %s" % [run.fixture, run.enabled])
		if int(run.execution_failures) > 0: failures.append("%s rejected Dupre's selected action" % run.fixture)
	var disabled: Dictionary = summary.totals.disabled
	var enabled: Dictionary = summary.totals.enabled
	if int(enabled.plies) < int(disabled.plies): failures.append("enabled policy completed fewer aggregate plies than the A/B baseline")
	# Outcomes in a short soak are descriptive. This broad tolerance catches only
	# a severe aggregate conversion regression while allowing different good play.
	var disabled_conversion := float(disabled.material_delta) + float(disabled.promotions) * 5.0 + float(disabled.endgame_score)
	var enabled_conversion := float(enabled.material_delta) + float(enabled.promotions) * 5.0 + float(enabled.endgame_score)
	if enabled_conversion < disabled_conversion - 5.0: failures.append("enabled policy severely regressed aggregate conversion indicators")


func _cpu(model: ChessBoardModel, color: String, seed: int, enabled: bool) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, color)
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE); cpu.set_random_seed(seed)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0; brain.simulation_backend = DupreAiBrain.SimulationBackend.CLASSIC_CORE
	# The A/B comparison keeps the established endgame evaluator active in both
	# arms and isolates only this milestone's technique layer.
	brain.endgame_policy_enabled = true; brain.endgame_technique_enabled = enabled; brain.candidate_limit = 4
	# The soak measures policy quality, not emergency-timeout quality. Give each
	# candidate enough room to complete ordinary two-ply verification.
	brain.max_reply_leaves = 64 if soak_profile else 24
	brain.think_budget_msec = 600 if soak_profile else 250
	return cpu


func _fixture(kind: StringName) -> ChessBoardModel:
	var pieces: Array
	match kind:
		&"pawn_race": pieces = [ClassicKing.new("white", Vector2i(6, 6)), Pawn.new("white", Vector2i(2, 2)), ClassicKing.new("black", Vector2i(1, 1)), Pawn.new("black", Vector2i(5, 5))]
		&"winning_race": pieces = [ClassicKing.new("white", Vector2i(7, 7)), Pawn.new("white", Vector2i(2, 2)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(5, 6))]
		&"losing_race": pieces = [ClassicKing.new("white", Vector2i(6, 3)), Pawn.new("white", Vector2i(4, 0)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(5, 5))]
		&"rook_conversion": pieces = [ClassicKing.new("white", Vector2i(5, 4)), Rook.new("white", Vector2i(6, 2)), Pawn.new("white", Vector2i(3, 2)), ClassicKing.new("black", Vector2i(0, 5)), Rook.new("black", Vector2i(1, 7))]
		&"rook_pressure": pieces = [ClassicKing.new("white", Vector2i(7, 7)), Rook.new("white", Vector2i(6, 0)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(4, 2))]
		&"advanced_passer": pieces = [ClassicKing.new("white", Vector2i(7, 6)), Rook.new("white", Vector2i(6, 0)), Pawn.new("white", Vector2i(5, 5)), ClassicKing.new("black", Vector2i(1, 3)), Rook.new("black", Vector2i(1, 5)), Pawn.new("black", Vector2i(5, 2))]
		&"arakne_endgame":
			var arakne := ArakneKing.new("white", Vector2i(5, 4)); arakne.set_cooldown(0); arakne.initial_cooldown_turn_pending = false
			pieces = [arakne, Rook.new("white", Vector2i(6, 1)), Pawn.new("white", Vector2i(3, 1)), ClassicKing.new("black", Vector2i(1, 5)), Rook.new("black", Vector2i(2, 6)), Pawn.new("black", Vector2i(4, 5))]
		&"necromancer_endgame":
			var necromancer := NecromancerKing.new("black", Vector2i(1, 4)); necromancer.set_cooldown(0); necromancer.initial_cooldown_turn_pending = false
			pieces = [ClassicKing.new("white", Vector2i(6, 4)), Rook.new("white", Vector2i(6, 0)), Pawn.new("white", Vector2i(3, 0)), necromancer, Rook.new("black", Vector2i(1, 7)), Pawn.new("black", Vector2i(4, 6))]
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null: model.unregister_piece(piece)
	model.board.clear()
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	model.current_turn = "white"
	return model


func _material_balance(model: ChessBoardModel, perspective: String) -> float:
	var result := 0.0
	for row in model.board:
		for piece in row:
			if piece == null or piece.is_king: continue
			var value := float(MATERIAL.get(piece.type, 1.0))
			result += value if piece.color == perspective else -value
	return result


func _piece_count(model: ChessBoardModel, color: String, type: String) -> int:
	var result := 0
	for row in model.board:
		for piece in row:
			if piece != null and piece.color == color and piece.type == type: result += 1
	return result
