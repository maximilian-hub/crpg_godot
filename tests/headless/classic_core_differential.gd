extends Node

const GATE_SEQUENCES := 24
const GATE_PLIES := 40
const SOAK_SEQUENCES := 256
const SOAK_PLIES := 100
const DEFAULT_SEED := 1128813136
const ARTIFACT_DIRECTORY := "user://test_artifacts/classic_core_differential"
const PROMOTIONS: Array[StringName] = [&"queen", &"rook", &"bishop", &"knight"]

var failures: Array[String] = []
var checks := 0
var stats := {
	"sequences": 0, "actions": 0, "positions_compared": 0,
	"attacks": 0, "captures": 0, "promotions": 0, "castles": 0, "en_passant": 0,
	"forced_passes": 0, "terminal_games": 0,
}
var model_events: Array[Dictionary] = []
var last_core_events: Array[Dictionary] = []
var promotion_choice: StringName = &"queen"
var first_artifact := {}


func _ready() -> void:
	var options := _options()
	var started := Time.get_ticks_msec()
	await _curated_cases()
	await _record_replay_case()
	if String(options.replay).is_empty():
		await _random_walks(options)
	else:
		await _replay_artifact(String(options.replay))
	if not first_artifact.is_empty(): await _minimize_artifact()
	_test_artifact_round_trip()
	var elapsed := Time.get_ticks_msec() - started
	stats["elapsed_ms"] = elapsed
	stats["actions_per_second"] = snappedf(float(stats.actions) * 1000.0 / maxf(1.0, elapsed), 0.01)
	print("CLASSIC CORE DIFFERENTIAL SUMMARY: ", JSON.stringify(stats))
	if failures.is_empty():
		print("CLASSIC CORE DIFFERENTIAL: PASS (", checks, " checks; profile=", options.profile, ")")
		get_tree().quit(0)
		return
	if not first_artifact.is_empty():
		var path := _write_artifact(first_artifact)
		printerr("Reproduce with: -- --diff-replay=", path)
	printerr("CLASSIC CORE DIFFERENTIAL: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _curated_cases() -> void:
	await _run_sequence("classic-start", _classic_start(), [
		{"from": Vector2i(6, 4), "to": Vector2i(4, 4)},
		{"from": Vector2i(1, 4), "to": Vector2i(3, 4)},
		{"from": Vector2i(7, 6), "to": Vector2i(5, 5)},
		{"from": Vector2i(0, 1), "to": Vector2i(2, 2)},
	])
	await _run_sequence("white-castle", _position([
		ClassicKing.new("white", Vector2i(7, 4)), Rook.new("white", Vector2i(7, 7)),
		ClassicKing.new("black", Vector2i(0, 4)),
	]), [{"from": Vector2i(7, 4), "to": Vector2i(7, 6)}])
	await _run_sequence("black-castle", _position([
		ClassicKing.new("white", Vector2i(7, 4)), ClassicKing.new("black", Vector2i(0, 4)),
		Rook.new("black", Vector2i(0, 0)),
	], "black"), [{"from": Vector2i(0, 4), "to": Vector2i(0, 2)}])

	var durable := Rook.new("black", Vector2i(4, 2))
	durable.max_hp = 3; durable.current_hp = 3
	await _run_sequence("nonlethal", _position([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
		Rook.new("white", Vector2i(4, 4)), durable,
	]), [{"from": Vector2i(4, 4), "to": Vector2i(4, 2)}])
	await _run_sequence("capture", _position([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
		Rook.new("white", Vector2i(4, 4)), Knight.new("black", Vector2i(4, 2)),
	]), [{"from": Vector2i(4, 4), "to": Vector2i(4, 2)}])
	await _run_sequence("king-defeat", _position([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
		Rook.new("white", Vector2i(1, 7)),
	]), [{"from": Vector2i(1, 7), "to": Vector2i(0, 7)}])

	var white_pawn := Pawn.new("white", Vector2i(3, 4)); white_pawn.has_moved = true
	await _run_sequence("en-passant", _position([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
		white_pawn, Pawn.new("black", Vector2i(1, 5)),
	], "black"), [
		{"from": Vector2i(1, 5), "to": Vector2i(3, 5)},
		{"from": Vector2i(3, 4), "to": Vector2i(2, 5)},
	])
	var expiry_pawn := Pawn.new("white", Vector2i(3, 4)); expiry_pawn.has_moved = true
	await _run_sequence("en-passant-expiry", _position([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
		expiry_pawn, Pawn.new("black", Vector2i(1, 5)),
	], "black"), [
		{"from": Vector2i(1, 5), "to": Vector2i(3, 5)},
		{"from": Vector2i(7, 7), "to": Vector2i(7, 6)},
		{"from": Vector2i(0, 7), "to": Vector2i(0, 6)},
		{"from": Vector2i(3, 4), "to": Vector2i(2, 4)},
	])
	var recovering := ClassicKing.new("white", Vector2i(7, 7)); recovering.stunned = true; recovering.stun_timer = 1
	await _run_sequence("stun-recovery", _position([
		recovering, ClassicKing.new("black", Vector2i(0, 7)),
	], "black"), [
		{"from": Vector2i(0, 7), "to": Vector2i(0, 6)},
		{"from": Vector2i(7, 7), "to": Vector2i(7, 6)},
	])
	for index in range(PROMOTIONS.size()):
		await _run_sequence("promotion-%s" % PROMOTIONS[index], _position([
			ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
			Pawn.new("white", Vector2i(1, index)),
		]), [{"from": Vector2i(1, index), "to": Vector2i(0, index), "promotion": PROMOTIONS[index]}])
	await _rejection_case()
	await _forced_pass_case()


func _record_replay_case() -> void:
	var record := ChessGameRecord.new()
	var start := _classic_start()
	record.frames.append({"kind": &"baseline", "label": "Classic baseline", "position": start, "action": {}, "ai": {}, "context": {}})
	var model := _new_model(start)
	for request in [
		{"from": Vector2i(6, 3), "to": Vector2i(4, 3)},
		{"from": Vector2i(1, 3), "to": Vector2i(3, 3)},
		{"from": Vector2i(7, 2), "to": Vector2i(4, 5)},
	]:
		var action = _find_model_action(model, request.from, request.to)
		_expect(action != null, "record fixture action is legal")
		if action == null: break
		var descriptor := ChessActionCodec.describe(action)
		await model.submit_move(action.piece, action.target)
		record.frames.append({"kind": &"gameplay", "label": ChessActionCodec.label(descriptor), "position": model.capture_position(), "action": descriptor, "ai": {}, "context": {}})
	_free_model(model)
	var decoded := ChessGameRecordCodec.from_json(ChessGameRecordCodec.to_json(record, false))
	_expect(decoded.record != null, "curated replay round-trips through ChessGameRecordCodec")
	if decoded.record == null: return
	for index in range(1, decoded.record.frames.size()):
		var result := await _execute_descriptor("record-frame-%d" % index, decoded.record.frames[index - 1].position, decoded.record.frames[index].action, &"queen")
		if result.ok:
			_expect(_canonical(result.model_position) == _canonical(decoded.record.frames[index].position), "record frame %d reproduces its snapshot" % index)
	var fixture := ChessGameRecordCodec.load_file("res://tests/fixtures/classic_core/rook_quiet.crpggame")
	_expect(fixture.record != null, "checked-in Classic replay fixture loads")
	if fixture.record != null:
		for index in range(1, fixture.record.frames.size()):
			var result := await _execute_descriptor("fixture-frame-%d" % index, fixture.record.frames[index - 1].position, fixture.record.frames[index].action, &"queen")
			if result.ok:
				_expect(_canonical(result.model_position) == _canonical(fixture.record.frames[index].position), "checked-in replay frame %d reproduces its snapshot" % index)


func _random_walks(options: Dictionary) -> void:
	var master := RandomNumberGenerator.new(); master.seed = int(options.seed)
	var starts := [_classic_start(), _midgame_start()]
	for sequence_index in range(int(options.sequences)):
		var sequence_seed := int(master.randi())
		var rng := RandomNumberGenerator.new(); rng.seed = sequence_seed
		var start: ChessPosition = starts[sequence_index % starts.size()].copy()
		var model := _new_model(start)
		var imported := ClassicChessCore.import_position(start)
		if not _expect(imported.ok, "random sequence %d imports" % sequence_index):
			_free_model(model); continue
		var core: ChessCoreState = imported.state
		var history: Array[Dictionary] = []
		stats.sequences += 1
		for ply in range(int(options.plies)):
			var model_map := _model_map(model.get_legal_primary_actions(model.current_turn))
			var core_map := _core_map(ClassicChessCore.legal_actions(core, core.current_turn))
			if not _same_keys(model_map, core_map, "random-%d ply %d legal actions" % [sequence_index, ply]):
				_capture_failure(sequence_seed, sequence_index, ply, start, history, model, core, model_map, core_map, "legal_action_mismatch")
				break
			if model_map.is_empty(): break
			var keys := model_map.keys(); keys.sort()
			var key: String = keys[rng.randi_range(0, keys.size() - 1)]
			var choice := PROMOTIONS[(sequence_index + ply) % PROMOTIONS.size()]
			var model_action: ChessPrimaryAction = model_map[key]
			model_events.clear(); promotion_choice = choice
			var core_result := ClassicChessCore.resolve_action(core, core_map[key])
			var core_trace: Array[ChessCoreEvent] = core_result.events.duplicate()
			if core_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
				var selected := ClassicChessCore.resolve_choice(core_result.state, choice)
				core_trace.append_array(selected.events); core_result = selected
				stats.promotions += 1
			var descriptor := ChessActionCodec.describe(model_action)
			_count_action(model, model_action)
			var accepted := await model.submit_move(model_action.piece, model_action.target)
			history.append({"action": _json_descriptor(descriptor), "promotion": String(choice)})
			stats.actions += 1
			if not accepted or core_result.status != ChessCoreStepResult.Status.COMPLETED:
				_fail("random-%d ply %d completion differs" % [sequence_index, ply])
				_capture_failure(sequence_seed, sequence_index, ply, start, history, model, core, model_map, core_map, "completion_mismatch")
				break
			core = core_result.state
			if not _state_parity(model, core, "random-%d ply %d" % [sequence_index, ply]):
				_capture_failure(sequence_seed, sequence_index, ply, start, history, model, core, model_map, core_map, "state_mismatch")
				break
			last_core_events = _core_trace(core_trace)
			if not _event_parity(model_events, last_core_events, "random-%d ply %d" % [sequence_index, ply]):
				_capture_failure(sequence_seed, sequence_index, ply, start, history, model, core, model_map, core_map, "event_mismatch")
				break
			if model.battle_over:
				stats.terminal_games += 1
				break
		_free_model(model)
		if not failures.is_empty(): break


func _run_sequence(label: String, start: ChessPosition, requests: Array) -> void:
	var model := _new_model(start)
	var imported := ClassicChessCore.import_position(start)
	if not _expect(imported.ok, "%s imports" % label):
		_free_model(model); return
	var core: ChessCoreState = imported.state
	for index in range(requests.size()):
		var model_map := _model_map(model.get_legal_primary_actions(model.current_turn))
		var core_map := _core_map(ClassicChessCore.legal_actions(core, core.current_turn))
		if not _same_keys(model_map, core_map, "%s step %d legal actions" % [label, index]): break
		var action = _find_model_action(model, requests[index].from, requests[index].to)
		if not _expect(action != null, "%s step %d requested action is legal" % [label, index]): break
		var key := _model_key(action)
		promotion_choice = requests[index].get("promotion", &"queen")
		model_events.clear()
		var result := ClassicChessCore.resolve_action(core, core_map[key])
		var core_trace: Array[ChessCoreEvent] = result.events.duplicate()
		if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			_expect(result.choice.options == PROMOTIONS, "%s promotion options match" % label)
			var selected := ClassicChessCore.resolve_choice(result.state, promotion_choice)
			core_trace.append_array(selected.events); result = selected
			stats.promotions += 1
		_count_action(model, action)
		var accepted := await model.submit_move(action.piece, action.target)
		if not _expect(accepted and result.status == ChessCoreStepResult.Status.COMPLETED, "%s step %d completes" % [label, index]): break
		core = result.state; stats.actions += 1
		_state_parity(model, core, "%s step %d" % [label, index])
		_event_parity(model_events, _core_trace(core_trace), "%s step %d" % [label, index])
	_free_model(model)


func _execute_descriptor(label: String, start: ChessPosition, descriptor: Dictionary, choice: StringName) -> Dictionary:
	var model := _new_model(start)
	var imported := ClassicChessCore.import_position(start)
	if not imported.ok:
		_fail("%s import failed: %s" % [label, imported.error]); _free_model(model); return {"ok": false}
	var model_map := _model_map(model.get_legal_primary_actions(model.current_turn))
	var core_map := _core_map(ClassicChessCore.legal_actions(imported.state, imported.state.current_turn))
	if not _same_keys(model_map, core_map, "%s legal actions" % label):
		_free_model(model); return {"ok": false}
	var key := _descriptor_key(descriptor)
	if not model_map.has(key) or not core_map.has(key):
		_fail("%s descriptor is not legal: %s" % [label, key]); _free_model(model); return {"ok": false}
	promotion_choice = choice
	var core_result := ClassicChessCore.resolve_action(imported.state, core_map[key])
	if core_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		core_result = ClassicChessCore.resolve_choice(core_result.state, choice)
	var action: ChessPrimaryAction = model_map[key]
	var accepted := await model.submit_move(action.piece, action.target)
	var ok := accepted and core_result.status == ChessCoreStepResult.Status.COMPLETED and _state_parity(model, core_result.state, label)
	var output := {"ok": ok, "model_position": model.capture_position(), "core_position": ClassicChessCore.export_position(core_result.state)}
	_free_model(model)
	return output


func _rejection_case() -> void:
	var start := _classic_start()
	var model := _new_model(start)
	var imported := ClassicChessCore.import_position(start)
	var stale := ChessCoreAction.new()
	stale.piece_id = model.board[6][0].piece_id; stale.color = "white"
	stale.from = Vector2i(6, 0); stale.target = Vector2i(3, 0); stale.path = [stale.target]
	var before_model := _canonical(model.capture_position())
	var before_core := _canonical(ClassicChessCore.export_position(imported.state))
	var result := ClassicChessCore.resolve_action(imported.state, stale)
	var accepted := await model.submit_move(model.board[6][0], stale.target)
	_expect(not accepted and result.status == ChessCoreStepResult.Status.REJECTED, "illegal actions reject in both engines")
	_expect(before_model == _canonical(model.capture_position()) and before_core == _canonical(ClassicChessCore.export_position(imported.state)), "rejections are atomic")
	_free_model(model)


func _forced_pass_case() -> void:
	var white := ClassicKing.new("white", Vector2i(7, 7)); white.stunned = true; white.stun_timer = 20
	var black := ClassicKing.new("black", Vector2i(0, 7)); black.stunned = true; black.stun_timer = 20
	var start := _position([white, black])
	var model := _new_model(start)
	var imported := ClassicChessCore.import_position(start)
	var core: ChessCoreState = imported.state
	model_events.clear()
	var core_events: Array[ChessCoreEvent] = []
	ClassicChessCore._resolve_forced_passes(core, core_events)
	await model.resolve_unplayable_turns()
	stats.forced_passes += 6
	_state_parity(model, core, "forced-pass draw")
	_event_parity(model_events, _core_trace(core_events), "forced-pass draw")
	_free_model(model)


func _state_parity(model: ChessBoardModel, core: ChessCoreState, context: String) -> bool:
	stats.positions_compared += 1
	var ok := true
	var model_json := _canonical(model.capture_position())
	var core_json := _canonical(ClassicChessCore.export_position(core))
	if model_json != core_json:
		_fail("%s resulting position differs\n  model=%s\n  core=%s" % [context, model_json, core_json]); ok = false
	if model.consecutive_forced_passes != core.consecutive_forced_passes:
		_fail("%s forced-pass counter differs" % context); ok = false
	if not model.is_settled() or core.pending_choice != null:
		_fail("%s did not settle identically" % context); ok = false
	return ok


func _event_parity(left: Array[Dictionary], right: Array[Dictionary], context: String) -> bool:
	checks += 1
	if left == right: return true
	failures.append("%s event trace differs\n  model=%s\n  core=%s" % [context, left, right])
	return false


func _new_model(position: ChessPosition) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	model.forced_pass_delay_seconds = 0.0
	add_child(model)
	_expect(model.load_position(position.copy()), "differential model loads position")
	_connect_trace(model)
	return model


func _new_model_unchecked(position: ChessPosition) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	model.forced_pass_delay_seconds = 0.0
	add_child(model)
	if not model.load_position(position.copy()): return model
	_connect_trace(model)
	return model


func _free_model(model: ChessBoardModel) -> void:
	if model == null: return
	# Promotion resolution resumes from a signal emission. Deferred disposal
	# avoids freeing an object that Godot still has locked in that call stack.
	model.queue_free()


func _connect_trace(model: ChessBoardModel) -> void:
	model.action_started.connect(func(color): model_events.append({"kind": "action_started", "color": color}))
	model.piece_move_committed.connect(func(piece, from, to, _p): model_events.append({"kind": "piece_moved", "piece_id": piece.piece_id, "from": _coord(from), "to": _coord(to)}))
	model.piece_landed.connect(func(piece, from, to, _g): model_events.append({"kind": "piece_landed", "piece_id": piece.piece_id, "from": _coord(from), "to": _coord(to)}))
	model.piece_castling_committed.connect(func(king, rook, kf, kt, rf, rt, _p): model_events.append({"kind": "pieces_castled", "king_id": king.piece_id, "rook_id": rook.piece_id, "king_from": _coord(kf), "king_to": _coord(kt), "rook_from": _coord(rf), "rook_to": _coord(rt)}))
	model.piece_capture_committed.connect(func(attacker, defender, from, to, captured_at, _p): model_events.append({"kind": "piece_captured", "attacker_id": attacker.piece_id, "defender_id": defender.piece_id, "from": _coord(from), "to": _coord(to), "captured_at": _coord(captured_at)}))
	model.piece_destroyed.connect(func(piece): model_events.append({"kind": "piece_destroyed", "piece_id": piece.piece_id, "coordinate": _coord(piece.coordinate)}))
	model.piece_damaged.connect(func(piece, amount, hp, max_hp): model_events.append({"kind": "piece_damaged", "piece_id": piece.piece_id, "amount": amount, "current_hp": hp, "max_hp": max_hp}))
	model.promotion_selection_requested.connect(func(pawn, options):
		model_events.append({"kind": "choice_requested", "choice_kind": "promotion", "piece_id": pawn.piece_id, "options": Array(options).map(func(value): return String(value))})
		model.call_deferred("submit_promotion_selection", promotion_choice)
	)
	model.piece_promotion_committed.connect(func(old_piece, new_piece, _g): model_events.append({"kind": "piece_promoted", "old_piece_id": old_piece.piece_id, "new_piece_id": new_piece.piece_id, "piece_type": String(new_piece.get_position_type_id()), "coordinate": _coord(new_piece.coordinate)}))
	model.turn_changed.connect(func(color): model_events.append({"kind": "turn_changed", "color": color, "global_turn_number": model.global_turn_number}))
	model.turn_passed.connect(func(color, count): model_events.append({"kind": "turn_passed", "color": color, "count": count}))
	model.battle_finished.connect(func(result): model_events.append({"kind": "battle_finished", "result": result}))
	model.action_finished.connect(func(): model_events.append({"kind": "action_finished"}))


func _core_trace(events: Array[ChessCoreEvent]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event in events:
		var item := {"kind": String(event.kind)}
		for raw_key in event.data:
			var key := "choice_kind" if event.kind == &"choice_requested" and String(raw_key) == "kind" else String(raw_key)
			var value = event.data[raw_key]
			if value is Vector2i: value = _coord(value)
			elif value is StringName: value = String(value)
			elif value is Array: value = Array(value).map(func(element): return String(element) if element is StringName else element)
			item[key] = value
		if event.kind == &"action_finished": item.erase("color")
		output.append(item)
	return output


func _model_map(actions: Array[ChessPrimaryAction]) -> Dictionary:
	var output := {}
	for action in actions:
		if action.kind != ChessPrimaryAction.Kind.MOVE: continue
		var key := _model_key(action)
		if output.has(key): _fail("duplicate model action: %s" % key)
		output[key] = action
	return output


func _core_map(actions: Array[ChessCoreAction]) -> Dictionary:
	var output := {}
	for action in actions:
		var key := _action_key(action.kind, action.piece_id, action.from, action.target, action.path)
		if output.has(key): _fail("duplicate core action: %s" % key)
		output[key] = action
	return output


func _model_map_silent(actions: Array[ChessPrimaryAction]) -> Dictionary:
	var output := {}
	for action in actions:
		if action.kind == ChessPrimaryAction.Kind.MOVE: output[_model_key(action)] = action
	return output


func _core_map_silent(actions: Array[ChessCoreAction]) -> Dictionary:
	var output := {}
	for action in actions: output[_action_key(action.kind, action.piece_id, action.from, action.target, action.path)] = action
	return output


func _sorted_keys(value: Dictionary) -> Array:
	var output := value.keys(); output.sort(); return output


func _count_action(model: ChessBoardModel, action: ChessPrimaryAction) -> void:
	var origin := action.piece.coordinate
	var defender = model.board[action.target.x][action.target.y]
	if defender != null:
		stats.attacks += 1
		if defender.current_hp <= action.piece.attack_power: stats.captures += 1
	elif action.piece.type == "pawn" and origin.y != action.target.y:
		stats.attacks += 1; stats.captures += 1; stats.en_passant += 1
	if action.piece is ClassicKing and absi(action.target.y - origin.y) == 2: stats.castles += 1


func _model_key(action: ChessPrimaryAction) -> String:
	return _action_key(action.kind, action.piece.piece_id, action.piece.coordinate, action.target, action.path)


func _descriptor_key(descriptor: Dictionary) -> String:
	return _action_key(int(descriptor.get("kind", 0)), String(descriptor.get("piece_id", "")), _decode_coord(descriptor.get("from", [])), _decode_coord(descriptor.get("target", [])), _decode_path(descriptor.get("path", [])))


func _action_key(kind: int, piece_id: String, from: Vector2i, target: Vector2i, path: Array) -> String:
	var path_parts: Array[String] = []
	for square in path: path_parts.append("%d,%d" % [square.x, square.y])
	return "%d|%s|%d,%d|%d,%d|%s" % [kind, piece_id, from.x, from.y, target.x, target.y, ";".join(path_parts)]


func _same_keys(model_map: Dictionary, core_map: Dictionary, context: String) -> bool:
	checks += 1
	var left := model_map.keys(); left.sort()
	var right := core_map.keys(); right.sort()
	if left == right: return true
	failures.append("%s differ\n  model-only=%s\n  core-only=%s" % [context, _difference(left, right), _difference(right, left)])
	return false


func _capture_failure(seed: int, sequence: int, ply: int, start: ChessPosition, history: Array[Dictionary], model: ChessBoardModel, core: ChessCoreState, model_map: Dictionary, core_map: Dictionary, reason: String) -> void:
	if not first_artifact.is_empty(): return
	var model_keys := model_map.keys(); model_keys.sort()
	var core_keys := core_map.keys(); core_keys.sort()
	first_artifact = {
		"schema": "crpg_classic_core_differential_failure", "version": 1,
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"build_id": String(ProjectSettings.get_setting("application/config/version", "dev")),
		"seed": seed, "sequence": sequence, "failing_ply": ply, "reason": reason,
		"start_position": ChessPositionCodec.to_dictionary(start), "history": history.duplicate(true),
		"legal": {"model": model_keys, "core": core_keys, "model_only": _difference(model_keys, core_keys), "core_only": _difference(core_keys, model_keys)},
		"model_position": ChessPositionCodec.to_dictionary(model.capture_position()),
		"core_position": ChessPositionCodec.to_dictionary(ClassicChessCore.export_position(core)) if core != null and core.pending_choice == null else {},
		"model_events": model_events.duplicate(true),
		"core_events": last_core_events.duplicate(true),
		"minimization": {"status": "pending", "attempts": 0},
	}


func _minimize_artifact() -> void:
	var decoded := ChessPositionCodec.from_dictionary(first_artifact.start_position)
	if decoded.position == null:
		first_artifact.minimization = {"status": "invalid_start", "attempts": 0}
		return
	var start: ChessPosition = decoded.position
	var history: Array = first_artifact.history.duplicate(true)
	var original_actions := history.size()
	var original_pieces := start.pieces.size()
	var attempts := 0
	# The harness already stops at the first mismatch. Delta-debug removable
	# contiguous history chunks while requiring the remaining sequence to stay legal.
	var chunk := maxi(1, history.size() / 2)
	while chunk >= 1 and attempts < 64 and not history.is_empty():
		var reduced := false
		var offset := 0
		while offset < history.size() and attempts < 64:
			var candidate := history.duplicate(true)
			candidate = candidate.slice(0, offset) + candidate.slice(mini(offset + chunk, candidate.size()), candidate.size())
			attempts += 1
			if await _silently_reproduces(start, candidate):
				history = candidate; reduced = true; break
			offset += chunk
		if not reduced: chunk /= 2
	# Greedily remove unreferenced non-Kings from the initial position.
	var referenced := {}
	for entry in history: referenced[String(entry.action.get("piece_id", ""))] = true
	for piece in start.pieces.duplicate():
		if attempts >= 128: break
		if ChessPieceCatalog.normalize_type_id(piece.type_id) == &"classic_king" or referenced.has(piece.piece_id): continue
		var candidate_start := start.copy()
		for candidate_piece in candidate_start.pieces.duplicate():
			if candidate_piece.piece_id == piece.piece_id: candidate_start.pieces.erase(candidate_piece)
		attempts += 1
		if await _silently_reproduces(candidate_start, history): start = candidate_start
	first_artifact["minimized_start_position"] = ChessPositionCodec.to_dictionary(start)
	first_artifact["minimized_history"] = history
	first_artifact.minimization = {
		"status": "completed", "attempts": attempts,
		"original_actions": original_actions, "minimized_actions": history.size(),
		"original_pieces": original_pieces, "minimized_pieces": start.pieces.size(),
	}


func _silently_reproduces(start: ChessPosition, history: Array) -> bool:
	var model := _new_model_unchecked(start)
	var imported := ClassicChessCore.import_position(start)
	if not imported.ok:
		_free_model(model); return false
	var core: ChessCoreState = imported.state
	for entry in history:
		var model_map := _model_map_silent(model.get_legal_primary_actions(model.current_turn))
		var core_map := _core_map_silent(ClassicChessCore.legal_actions(core, core.current_turn))
		if _sorted_keys(model_map) != _sorted_keys(core_map):
			_free_model(model); return true
		var key := _descriptor_key(entry.action)
		if not model_map.has(key) or not core_map.has(key):
			_free_model(model); return false
		promotion_choice = StringName(entry.get("promotion", "queen"))
		model_events.clear()
		var result := ClassicChessCore.resolve_action(core, core_map[key])
		var core_trace: Array[ChessCoreEvent] = result.events.duplicate()
		if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			var selected := ClassicChessCore.resolve_choice(result.state, promotion_choice)
			core_trace.append_array(selected.events); result = selected
		var action: ChessPrimaryAction = model_map[key]
		var accepted := await model.submit_move(action.piece, action.target)
		if not accepted or result.status != ChessCoreStepResult.Status.COMPLETED:
			_free_model(model); return true
		core = result.state
		if _canonical(model.capture_position()) != _canonical(ClassicChessCore.export_position(core)) or model.consecutive_forced_passes != core.consecutive_forced_passes:
			_free_model(model); return true
		if model_events != _core_trace(core_trace):
			_free_model(model); return true
	var final_model_map := _model_map_silent(model.get_legal_primary_actions(model.current_turn))
	var final_core_map := _core_map_silent(ClassicChessCore.legal_actions(core, core.current_turn))
	if _sorted_keys(final_model_map) != _sorted_keys(final_core_map):
		_free_model(model); return true
	_free_model(model)
	return false


func _write_artifact(artifact: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIRECTORY))
	var path := "%s/failure-%s-%s.json" % [ARTIFACT_DIRECTORY, artifact.get("seed", 0), Time.get_unix_time_from_system()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(artifact, "  "))
	return path


func _replay_artifact(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not _expect(file != null, "artifact opens"): return
	var parsed = JSON.parse_string(file.get_as_text())
	if not _expect(parsed is Dictionary and parsed.get("schema", "") == "crpg_classic_core_differential_failure", "artifact schema is valid"): return
	var decoded := ChessPositionCodec.from_dictionary(parsed.start_position)
	if not _expect(decoded.position != null, "artifact start position decodes"): return
	_expect(await _silently_reproduces(decoded.position, parsed.history), "artifact still reproduces its recorded mismatch")
	var current: ChessPosition = decoded.position
	for index in range(parsed.history.size()):
		var entry: Dictionary = parsed.history[index]
		var result := await _execute_descriptor("artifact-step-%d" % index, current, entry.action, StringName(entry.get("promotion", "queen")))
		if not result.ok: return
		current = result.model_position


func _test_artifact_round_trip() -> void:
	var sample := {"schema": "crpg_classic_core_differential_failure", "version": 1, "seed": 7, "history": [], "start_position": ChessPositionCodec.to_dictionary(_classic_start())}
	var decoded = JSON.parse_string(JSON.stringify(sample))
	_expect(decoded is Dictionary and decoded.seed == 7 and decoded.start_position.schema == "crpg_chess_position", "failure artifact is JSON-compatible")


func _classic_start() -> ChessPosition:
	var pieces: Array = []
	for color in ["black", "white"]:
		var back := 0 if color == "black" else 7
		var pawn_row := 1 if color == "black" else 6
		pieces.append_array([Rook.new(color, Vector2i(back, 0)), Knight.new(color, Vector2i(back, 1)), Bishop.new(color, Vector2i(back, 2)), Queen.new(color, Vector2i(back, 3)), ClassicKing.new(color, Vector2i(back, 4)), Bishop.new(color, Vector2i(back, 5)), Knight.new(color, Vector2i(back, 6)), Rook.new(color, Vector2i(back, 7))])
		for column in range(8): pieces.append(Pawn.new(color, Vector2i(pawn_row, column)))
	return _position(pieces)


func _midgame_start() -> ChessPosition:
	var wr := Rook.new("white", Vector2i(5, 0)); wr.has_moved = true
	var br := Rook.new("black", Vector2i(2, 7)); br.has_moved = true
	return _position([
		ClassicKing.new("white", Vector2i(7, 4)), ClassicKing.new("black", Vector2i(0, 4)), wr, br,
		Queen.new("white", Vector2i(5, 3)), Queen.new("black", Vector2i(2, 3)),
		Bishop.new("white", Vector2i(6, 2)), Bishop.new("black", Vector2i(1, 5)),
		Knight.new("white", Vector2i(5, 5)), Knight.new("black", Vector2i(2, 2)),
		Pawn.new("white", Vector2i(4, 1)), Pawn.new("white", Vector2i(4, 6)),
		Pawn.new("black", Vector2i(3, 1)), Pawn.new("black", Vector2i(3, 6)),
	])


func _position(pieces: Array, turn := "white") -> ChessPosition:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = turn
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position()
	_free_model(model)
	return result


func _find_model_action(model: ChessBoardModel, from: Vector2i, to: Vector2i):
	for action in model.get_legal_primary_actions(model.current_turn):
		if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece.coordinate == from and action.target == to: return action
	return null


func _canonical(position: ChessPosition) -> String: return ChessPositionCodec.to_json(position, false) if position != null else "<null>"
func _coord(value: Vector2i) -> Array[int]: return [value.x, value.y]
func _decode_coord(value: Array) -> Vector2i: return Vector2i(int(value[0]), int(value[1])) if value.size() == 2 else Vector2i(-1, -1)
func _decode_path(value: Array) -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	for item in value: output.append(_decode_coord(item))
	return output


func _json_descriptor(value: Dictionary) -> Dictionary:
	return {"kind": value.kind, "color": value.color, "piece_id": value.piece_id, "piece_type": value.piece_type, "from": value.from.duplicate(), "target": value.target.duplicate(), "path": value.path.duplicate(true)}


func _difference(left: Array, right: Array) -> Array:
	var output := []
	for value in left:
		if value not in right: output.append(value)
	return output


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition: failures.append(message)
	return condition


func _fail(message: String) -> void: failures.append(message)


func _options() -> Dictionary:
	var output := {"profile": "gate", "seed": DEFAULT_SEED, "sequences": GATE_SEQUENCES, "plies": GATE_PLIES, "replay": ""}
	for argument in OS.get_cmdline_user_args():
		if argument == "--diff-profile=soak": output.profile = "soak"; output.sequences = SOAK_SEQUENCES; output.plies = SOAK_PLIES
		elif argument.begins_with("--diff-seed="): output.seed = int(argument.trim_prefix("--diff-seed="))
		elif argument.begins_with("--diff-sequences="): output.sequences = maxi(1, int(argument.trim_prefix("--diff-sequences=")))
		elif argument.begins_with("--diff-plies="): output.plies = maxi(1, int(argument.trim_prefix("--diff-plies=")))
		elif argument.begins_with("--diff-replay="): output.replay = argument.trim_prefix("--diff-replay=")
	return output
