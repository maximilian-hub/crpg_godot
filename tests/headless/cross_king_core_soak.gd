extends Node

const KING_TYPES: Array[StringName] = [
	&"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king",
	&"quarterly_initiative_king", &"cannon_king", &"rhetorician_king", &"wraith_king",
	&"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge",
]
const DEFAULT_SEED := 90420261
const ARTIFACT_DIRECTORY := "/tmp/crpg_cross_king_core_soak"

var failures: Array[String] = []
var checks := 0
var first_artifact := {}
var stats := {
	"matchups": 0, "sequences": 0, "actions": 0, "positions_compared": 0,
	"forced_passes": 0, "terminal_games": 0, "abilities": {}, "choices": {}, "events": {}, "timings": {},
}
var _model_choices: Array[Dictionary] = []


func _ready() -> void:
	var options := _options()
	var started := Time.get_ticks_msec()
	if String(options.replay).is_empty():
		await _lifecycle_checks()
		await _run_matrix(options)
	else:
		await _replay_artifact(String(options.replay))
	stats["elapsed_ms"] = Time.get_ticks_msec() - started
	stats["actions_per_second"] = snappedf(float(stats.actions) * 1000.0 / maxf(1.0, float(stats.elapsed_ms)), 0.01)
	print("CROSS KING CORE SOAK SUMMARY: ", JSON.stringify(stats))
	if failures.is_empty():
		print("CROSS KING CORE SOAK: PASS (", checks, " checks; profile=", options.profile, "; seed=", options.seed, ")")
		get_tree().quit(0)
		return
	if not first_artifact.is_empty(): printerr("Reproduce with: -- --cross-replay=", _write_artifact(first_artifact))
	printerr("CROSS KING CORE SOAK: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _run_matrix(options: Dictionary) -> void:
	var master := RandomNumberGenerator.new(); master.seed = int(options.seed)
	for white_type in KING_TYPES:
		if not String(options.white).is_empty() and String(white_type) != String(options.white): continue
		for black_type in KING_TYPES:
			if not String(options.black).is_empty() and String(black_type) != String(options.black): continue
			stats.matchups += 1
			for sequence in range(int(options.seeds_per_matchup)):
				var seed := int(master.randi())
				var result := await _run_sequence(white_type, black_type, seed, int(options.plies))
				stats.sequences += 1
				if not result: return
	if String(options.white).is_empty() and String(options.black).is_empty():
		_expect(int(stats.matchups) == KING_TYPES.size() * KING_TYPES.size(), "all ordered King matchups execute")
		_assert_coverage()


func _lifecycle_checks() -> void:
	for king_type in KING_TYPES:
		var position := _matchup_position(king_type, &"classic_king")
		var started := Time.get_ticks_usec()
		var decoded := ChessPositionCodec.from_json(ChessPositionCodec.to_json(position, false))
		_record_timing("codec_round_trip", Time.get_ticks_usec() - started)
		_expect(decoded.position != null, "%s position codec round-trip succeeds" % king_type)
		if decoded.position == null: continue
		started = Time.get_ticks_usec()
		var imported := ClassicChessCore.import_position(decoded.position)
		_record_timing("core_import", Time.get_ticks_usec() - started)
		_expect(imported.ok, "%s decoded position imports" % king_type)
		if not imported.ok: continue
		started = Time.get_ticks_usec()
		var exported := ClassicChessCore.export_position(imported.state)
		_record_timing("core_export", Time.get_ticks_usec() - started)
		_expect(ChessPositionCodec.to_json(exported, false) == ChessPositionCodec.to_json(decoded.position, false), "%s settled import/export is exact" % king_type)
		started = Time.get_ticks_usec()
		var copied: ChessCoreState = imported.state.copy()
		_record_timing("state_copy", Time.get_ticks_usec() - started)
		var first_piece: ChessCorePiece = copied.pieces[0]
		var original_hp: int = imported.state.pieces_by_id[first_piece.piece_id].current_hp
		first_piece.current_hp -= 1
		_expect(imported.state.pieces_by_id[first_piece.piece_id].current_hp == original_hp, "%s core copy owns independent pieces" % king_type)

		var live := _new_model(position)
		_expect(live.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "%s enables live pure authority" % king_type)
		var replacement := _matchup_position(&"classic_king", king_type)
		_expect(live.load_position(replacement) and String(live.get_live_authority_diagnostics().active) == "classic_core", "%s live authority resynchronizes after replacement" % king_type)
		_expect(int(live.get_live_authority_diagnostics().projection_mismatches) == 0, "%s live resynchronization has no projection mismatch" % king_type)
		_free_model(live); await get_tree().process_frame

	# Pending choices are intentionally not ChessPosition save points, but pure
	# speculative states must remain independently copyable and resumable.
	var quarterly_position := _matchup_position(&"quarterly_initiative_king", &"classic_king")
	var quarterly_import := ClassicChessCore.import_position(quarterly_position)
	var quarterly: ChessCorePiece
	for piece in quarterly_import.state.pieces:
		if piece.type_id == &"quarterly_initiative_king": quarterly = piece; break
	var grant_action: ChessCoreAction
	for action in ClassicChessCore.legal_actions(quarterly_import.state, "white"):
		if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY: grant_action = action; break
	var pending := ClassicChessCore.resolve_action(quarterly_import.state, grant_action)
	_expect(pending.status == ChessCoreStepResult.Status.PENDING_CHOICE, "pending grant fixture reaches a choice")
	if pending.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		var pending_copy := pending.state.copy()
		var bishop := ClassicChessCore.resolve_choice(pending.state, &"bishop")
		var knight := ClassicChessCore.resolve_choice(pending_copy, &"knight")
		_expect(bishop.status == ChessCoreStepResult.Status.COMPLETED and knight.status == ChessCoreStepResult.Status.COMPLETED, "copied pending choices resume independently")
		var bishop_target := bishop.state.piece_by_id(pending.choice.target_piece_id)
		var knight_target := knight.state.piece_by_id(pending.choice.target_piece_id)
		_expect(&"bishop" in bishop_target.granted_movement_types and &"knight" not in bishop_target.granted_movement_types and &"knight" in knight_target.granted_movement_types, "resumed pending copies do not share mutable choice state")

	var stopped_white := ClassicKing.new("white", Vector2i(7, 7)); stopped_white.stunned = true; stopped_white.stun_timer = 20
	var stopped_black := ClassicKing.new("black", Vector2i(0, 0)); stopped_black.stunned = true; stopped_black.stun_timer = 20
	var pass_position := _position([stopped_white, stopped_black])
	var pass_model := _new_model(pass_position)
	var pass_import := ClassicChessCore.import_position(pass_position)
	var pass_result := ClassicChessCore.resolve_forced_passes(pass_import.state)
	await pass_model.resolve_unplayable_turns()
	stats.forced_passes += 6
	_expect(pass_result.status == ChessCoreStepResult.Status.COMPLETED and _state_parity(pass_model, pass_result.state, "curated forced-pass draw"), "forced-pass lifecycle remains identical")
	_free_model(pass_model); await get_tree().process_frame

	var promotion_position := _position([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("white", Vector2i(1, 3))])
	var promotion_model := _new_model(promotion_position)
	var promotion_import := ClassicChessCore.import_position(promotion_position)
	var promotion_action: ChessCoreAction
	for action in ClassicChessCore.legal_actions(promotion_import.state, "white"):
		if action.piece_id == promotion_import.state.occupant(Vector2i(1, 3)).piece_id and action.target == Vector2i(0, 3): promotion_action = action; break
	var promotion_result := ClassicChessCore.resolve_action(promotion_import.state, promotion_action)
	_expect(promotion_result.status == ChessCoreStepResult.Status.PENDING_CHOICE and promotion_result.choice.kind == &"promotion", "curated promotion reaches a typed choice")
	if promotion_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		_model_choices.clear()
		var promoted: Variant = _choose_option(promotion_result.choice.options)
		promotion_result = ClassicChessCore.resolve_choice(promotion_result.state, promoted)
		var model_pawn := promotion_model.board[1][3] as ModelPiece
		await promotion_model.submit_move(model_pawn, Vector2i(0, 3))
		await _wait_settled(promotion_model)
		_increment(stats.choices, "promotion")
		_expect(_choice_sequence_parity(_model_choices, [{"kind": "promotion", "options": _normalized_options([&"queen", &"rook", &"bishop", &"knight"])}], "curated promotion"), "promotion choice sequence remains identical")
		_expect(_state_parity(promotion_model, promotion_result.state, "curated promotion"), "promotion outcome remains identical")
	_free_model(promotion_model); await get_tree().process_frame


func _run_sequence(white_type: StringName, black_type: StringName, seed: int, plies: int, start_override: ChessPosition = null) -> bool:
	var start := start_override.copy() if start_override != null else _matchup_position(white_type, black_type)
	var model := _new_model(start)
	var imported := ClassicChessCore.import_position(start)
	var label := "%s-v-%s" % [white_type, black_type]
	if not _expect(imported.ok, "%s imports: %s" % [label, imported.get("error", "")]):
		_free_model(model); return false
	var core: ChessCoreState = imported.state
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var history: Array[Dictionary] = []
	for ply in range(plies):
		if core.battle_over: stats.terminal_games += 1; break
		var phase_started := Time.get_ticks_usec()
		var model_map := _model_map(model.get_legal_primary_actions(model.current_turn))
		_record_timing("model_legal", Time.get_ticks_usec() - phase_started)
		phase_started = Time.get_ticks_usec()
		var core_map := _core_map(ClassicChessCore.legal_actions(core, core.current_turn))
		_record_timing("core_legal", Time.get_ticks_usec() - phase_started)
		if not _same_keys(model_map, core_map, "%s seed %s ply %d legal actions" % [label, seed, ply]):
			_capture_failure(label, white_type, black_type, seed, ply, start, history, model, core, model_map, core_map, "legal_action_mismatch")
			_free_model(model); return false
		if model_map.is_empty():
			_model_choices.clear()
			phase_started = Time.get_ticks_usec()
			var pass_result := ClassicChessCore.resolve_forced_passes(core)
			_record_timing("core_forced_pass", Time.get_ticks_usec() - phase_started)
			await model.resolve_unplayable_turns()
			var pass_choices: Array[Dictionary] = []
			while pass_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
				var chosen = _choose_option(pass_result.choice.options)
				pass_choices.append({"kind": String(pass_result.choice.kind), "options": _normalized_options(pass_result.choice.options)})
				pass_result = ClassicChessCore.resolve_choice(pass_result.state, chosen)
			await _wait_settled(model)
			if not _choice_sequence_parity(_model_choices, pass_choices, label): _free_model(model); return false
			if not _expect(pass_result.status == ChessCoreStepResult.Status.COMPLETED, "%s forced pass completes" % label): _free_model(model); return false
			core = pass_result.state; stats.forced_passes += 1; stats.actions += 1
			await _wait_settled(model)
			if not _state_parity(model, core, "%s forced pass" % label):
				_capture_failure(label, white_type, black_type, seed, ply, start, history, model, core, model_map, core_map, "forced_pass_mismatch")
				_free_model(model); return false
			continue
		var key := _choose_action_key(model_map, rng)
		var model_action: ChessPrimaryAction = model_map[key]
		var core_action: ChessCoreAction = core_map[key]
		var descriptor := ChessActionCodec.describe(model_action)
		phase_started = Time.get_ticks_usec()
		var result := ClassicChessCore.resolve_action(core, core_action)
		_record_timing("core_resolution", Time.get_ticks_usec() - phase_started)
		_count_events(result.events)
		_model_choices.clear()
		phase_started = Time.get_ticks_usec()
		var accepted := await _submit_model_action(model, model_action)
		_record_timing("model_resolution", Time.get_ticks_usec() - phase_started)
		history.append({"kind": "action", "action": _json_descriptor(descriptor)})
		if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
			_increment(stats.abilities, String(model_action.piece.get_position_type_id()))
		var core_choices: Array[Dictionary] = []
		while result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			var chosen = _choose_option(result.choice.options)
			core_choices.append({"kind": String(result.choice.kind), "options": _normalized_options(result.choice.options)})
			_increment(stats.choices, String(result.choice.kind))
			history.append({"kind": "choice", "choice_kind": String(result.choice.kind), "value": _json_value(chosen)})
			phase_started = Time.get_ticks_usec()
			var choice_result := ClassicChessCore.resolve_choice(result.state, chosen)
			_record_timing("core_choice", Time.get_ticks_usec() - phase_started)
			_count_events(choice_result.events); result = choice_result
		await _wait_settled(model)
		if not _choice_sequence_parity(_model_choices, core_choices, label):
			_capture_failure(label, white_type, black_type, seed, ply, start, history, model, result.state, model_map, core_map, "choice_mismatch")
			_free_model(model); return false
		if not _expect(accepted and result.status == ChessCoreStepResult.Status.COMPLETED, "%s seed %s ply %d completes" % [label, seed, ply]):
			_capture_failure(label, white_type, black_type, seed, ply, start, history, model, core, model_map, core_map, "completion_mismatch")
			_free_model(model); return false
		core = result.state; stats.actions += 1
		if not _state_parity(model, core, "%s seed %s ply %d" % [label, seed, ply]):
			_capture_failure(label, white_type, black_type, seed, ply, start, history, model, core, model_map, core_map, "state_mismatch")
			_free_model(model); return false
	_free_model(model); await get_tree().process_frame
	return true


func _choice_sequence_parity(model_choices: Array[Dictionary], core_choices: Array[Dictionary], context: String) -> bool:
	checks += 1
	if model_choices != core_choices:
		failures.append("%s choice sequence differs: model=%s core=%s" % [context, model_choices, core_choices]); return false
	return true


func _wait_settled(model: ChessBoardModel) -> void:
	for _index in range(120):
		if model.is_settled(): return
		await get_tree().process_frame


func _choose_action_key(actions: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys := actions.keys(); keys.sort()
	var weighted: Array[String] = []
	for key in keys:
		var action: ChessPrimaryAction = actions[key]
		var weight := 1
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY: weight = 16
		elif action.piece.model.board[action.target.x][action.target.y] != null: weight = 8
		for _index in range(weight): weighted.append(key)
	return weighted[rng.randi_range(0, weighted.size() - 1)]


func _choose_option(options: Array):
	var ordered := _normalized_options(options)
	var first = ordered[0]
	if first is Array: return Vector2i(int(first[0]), int(first[1]))
	return StringName(first) if options[0] is StringName else first


func _normalized_options(options: Array) -> Array:
	var output := []
	for option in options: output.append([option.x, option.y] if option is Vector2i else String(option) if option is StringName else option)
	output.sort_custom(func(a, b): return JSON.stringify(a) < JSON.stringify(b))
	return output


func _state_parity(model: ChessBoardModel, core: ChessCoreState, context: String) -> bool:
	checks += 1; stats.positions_compared += 1
	var model_json := ChessPositionCodec.to_json(model.capture_position(), false)
	var core_position := ClassicChessCore.export_position(core)
	var core_json := ChessPositionCodec.to_json(core_position, false) if core_position != null else "<pending>"
	if model_json != core_json or model.consecutive_forced_passes != core.consecutive_forced_passes or not model.is_settled() or core.pending_choice != null:
		failures.append("%s differs\n  model=%s\n  core=%s" % [context, model_json, core_json]); return false
	return true


func _matchup_position(white_type: StringName, black_type: StringName) -> ChessPosition:
	var white := _ready_king(ChessPieceCatalog.create_piece(white_type, "white", Vector2i(7, 7)) as KingPiece)
	var black := _ready_king(ChessPieceCatalog.create_piece(black_type, "black", Vector2i(0, 0)) as KingPiece)
	return _position([
		white, black,
		Rook.new("white", Vector2i(5, 1)), Bishop.new("white", Vector2i(6, 5)), Knight.new("white", Vector2i(4, 6)), Pawn.new("white", Vector2i(5, 4)),
		Rook.new("black", Vector2i(2, 6)), Queen.new("black", Vector2i(3, 3)), Knight.new("black", Vector2i(3, 1)), Pawn.new("black", Vector2i(2, 3)),
	])


func _ready_king(piece: KingPiece) -> KingPiece:
	piece.set_cooldown(0); piece.initial_cooldown_turn_pending = false; return piece


func _position(pieces: Array) -> ChessPosition:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position()
	# Position RNG must not depend on the host process or test execution order.
	result.random_states = {&"lunacy": 0x12345678, &"archer_volley": 0x23456789}
	model.queue_free(); return result


func _new_model(position: ChessPosition) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; model.forced_pass_delay_seconds = 0.0; add_child(model)
	model.load_position(position.copy())
	model.promotion_selection_requested.connect(func(_pawn, options):
		_model_choices.append({"kind": "promotion", "options": _normalized_options(options)})
		model.call_deferred("submit_promotion_selection", _choose_option(options))
	)
	model.movement_type_selection_requested.connect(func(_king, _target, options):
		_model_choices.append({"kind": "movement_type_grant", "options": _normalized_options(options)})
		model.call_deferred("submit_movement_type_grant", _choose_option(options))
	)
	model.reaction_selection_requested.connect(func(_piece, kind, options):
		_model_choices.append({"kind": String(kind), "options": _normalized_options(options)})
		model.call_deferred("submit_reaction_selection", _choose_option(options))
	)
	return model


func _submit_model_action(model: ChessBoardModel, action: ChessPrimaryAction) -> bool:
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY: return await model.submit_active_ability(action.piece, action.target)
	if action.kind == ChessPrimaryAction.Kind.ARCHER_CHARGE: return await model.submit_archer_charge(action.piece as ArcherKing)
	if action.path.size() > 1: return await model.submit_move_path(action.piece, action.path)
	return await model.submit_move(action.piece, action.target)


func _model_map(actions: Array[ChessPrimaryAction]) -> Dictionary:
	var output := {}
	for action in actions: output[_action_key(action.kind, action.piece.piece_id, action.piece.coordinate, action.target, action.path)] = action
	return output


func _core_map(actions: Array[ChessCoreAction]) -> Dictionary:
	var output := {}
	for action in actions: output[_action_key(action.kind, action.piece_id, action.from, action.target, action.path)] = action
	return output


func _action_key(kind: int, piece_id: String, from: Vector2i, target: Vector2i, path: Array) -> String:
	var path_parts: Array[String] = []
	for square in path: path_parts.append("%d,%d" % [square.x, square.y])
	return "%d|%s|%d,%d|%d,%d|%s" % [kind, piece_id, from.x, from.y, target.x, target.y, ";".join(path_parts)]


func _same_keys(model_map: Dictionary, core_map: Dictionary, context: String) -> bool:
	checks += 1
	var left := model_map.keys(); left.sort(); var right := core_map.keys(); right.sort()
	if left == right: return true
	failures.append("%s differ\n  model-only=%s\n  core-only=%s" % [context, _difference(left, right), _difference(right, left)]); return false


func _count_events(events: Array[ChessCoreEvent]) -> void:
	for event in events: _increment(stats.events, String(event.kind))


func _increment(values: Dictionary, key: String) -> void: values[key] = int(values.get(key, 0)) + 1


func _record_timing(name: String, elapsed_usec: int) -> void:
	var entry: Dictionary = stats.timings.get(name, {"calls": 0, "total_usec": 0, "max_usec": 0})
	entry.calls = int(entry.calls) + 1
	entry.total_usec = int(entry.total_usec) + elapsed_usec
	entry.max_usec = maxi(int(entry.max_usec), elapsed_usec)
	entry["average_usec"] = snappedf(float(entry.total_usec) / float(entry.calls), 0.01)
	stats.timings[name] = entry


func _assert_coverage() -> void:
	for king_type in KING_TYPES:
		if king_type == &"classic_king": continue
		_expect(int(stats.abilities.get(String(king_type), 0)) > 0, "gate exercises %s active ability" % king_type)
	for choice_kind in ["promotion", "raise_dead", "movement_type_grant", "lingering_malice"]:
		_expect(int(stats.choices.get(choice_kind, 0)) > 0, "gate exercises %s choice" % choice_kind)
	for event_kind in ["arc_mortar_impact", "automatic_reaction_started", "socratic_action_selected", "autonomous_entity_moved", "tile_effect_added", "turn_passed"]:
		_expect(int(stats.events.get(event_kind, 0)) > 0 or (event_kind == "turn_passed" and int(stats.forced_passes) > 0), "gate exercises %s" % event_kind)


func _capture_failure(label: String, white_type: StringName, black_type: StringName, seed: int, ply: int, start: ChessPosition, history: Array, model: ChessBoardModel, core: ChessCoreState, model_map: Dictionary, core_map: Dictionary, reason: String) -> void:
	if not first_artifact.is_empty(): return
	first_artifact = {
		"schema": "crpg_cross_king_core_failure", "version": 1, "label": label,
		"white_king": String(white_type), "black_king": String(black_type), "seed": seed,
		"failing_ply": ply, "reason": reason, "start_position": ChessPositionCodec.to_dictionary(start),
		"history": history.duplicate(true), "legal": {"model": model_map.keys(), "core": core_map.keys()},
		"model_position": ChessPositionCodec.to_dictionary(model.capture_position()),
		"core_position": ChessPositionCodec.to_dictionary(ClassicChessCore.export_position(core)) if core != null and core.pending_choice == null else {},
		"core_transient": {
			"pending_choice": String(core.pending_choice.kind) if core != null and core.pending_choice != null else "",
			"reaction_types": core.reaction_queue.map(func(reaction): return String(reaction.action_type)) if core != null else [],
			"resolution_context": core.resolution_context.duplicate(true) if core != null else {},
		},
	}


func _write_artifact(artifact: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIRECTORY)
	var path := "%s/failure-%s-%s.json" % [ARTIFACT_DIRECTORY, artifact.seed, Time.get_unix_time_from_system()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(artifact, "  "))
	return path


func _replay_artifact(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not _expect(file != null, "replay artifact opens"): return
	var artifact = JSON.parse_string(file.get_as_text())
	if not _expect(artifact is Dictionary and artifact.get("schema", "") == "crpg_cross_king_core_failure", "replay artifact schema is valid"): return
	var decoded := ChessPositionCodec.from_dictionary(artifact.start_position)
	if not _expect(decoded.position != null, "replay start position decodes"): return
	await _run_sequence(StringName(artifact.white_king), StringName(artifact.black_king), int(artifact.seed), int(artifact.failing_ply) + 1, decoded.position)


func _json_descriptor(value: Dictionary) -> Dictionary:
	return {"kind": value.kind, "color": value.color, "piece_id": value.piece_id, "piece_type": value.piece_type, "from": value.from.duplicate(), "target": value.target.duplicate(), "path": value.path.duplicate(true)}


func _json_value(value): return [value.x, value.y] if value is Vector2i else String(value) if value is StringName else value
func _difference(left: Array, right: Array) -> Array:
	var output := []
	for value in left:
		if value not in right: output.append(value)
	return output
func _free_model(model: ChessBoardModel) -> void:
	if model != null: model.queue_free()
func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition: failures.append(message)
	return condition


func _options() -> Dictionary:
	var output := {"profile": "gate", "seed": DEFAULT_SEED, "seeds_per_matchup": 2, "plies": 48, "replay": "", "white": "", "black": ""}
	for argument in OS.get_cmdline_user_args():
		if argument == "--cross-profile=soak": output.profile = "soak"; output.seeds_per_matchup = 4; output.plies = 120
		elif argument.begins_with("--cross-seed="): output.seed = int(argument.trim_prefix("--cross-seed="))
		elif argument.begins_with("--cross-seeds-per-matchup="): output.seeds_per_matchup = maxi(1, int(argument.trim_prefix("--cross-seeds-per-matchup=")))
		elif argument.begins_with("--cross-plies="): output.plies = maxi(1, int(argument.trim_prefix("--cross-plies=")))
		elif argument.begins_with("--cross-replay="): output.replay = argument.trim_prefix("--cross-replay=")
		elif argument.begins_with("--cross-white="): output.white = argument.trim_prefix("--cross-white=")
		elif argument.begins_with("--cross-black="): output.black = argument.trim_prefix("--cross-black=")
	return output
