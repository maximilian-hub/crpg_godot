extends Node

const GATE_SEQUENCES := 32
const GATE_PLIES := 80
const SOAK_SEQUENCES := 256
const SOAK_PLIES := 160
const DEFAULT_SEED := 57923841
const ARTIFACT_DIRECTORY := "user://test_artifacts/cannon_reaction_soak"

var failures: Array[String] = []
var checks := 0
var model_events: Array[Dictionary] = []
var first_artifact := {}
var stats := {
	"sequences": 0, "actions": 0, "positions_compared": 0,
	"mortar_launches": 0, "mortar_impacts": 0, "overlapping_impacts": 0,
	"rage_triggers": 0, "raise_dead_choices": 0, "forced_passes": 0,
	"source_dead_impacts": 0, "terminal_battles": 0,
}


func _ready() -> void:
	var options := _options()
	var started := Time.get_ticks_msec()
	if String(options.replay).is_empty():
		await _curated_cases()
		await _live_authority_case()
		await _random_walks(options)
	else:
		await _replay_artifact(String(options.replay))
	stats["elapsed_ms"] = Time.get_ticks_msec() - started
	stats["actions_per_second"] = snappedf(float(stats.actions) * 1000.0 / maxf(1.0, float(stats.elapsed_ms)), 0.01)
	print("CANNON REACTION SOAK SUMMARY: ", JSON.stringify(stats))
	if String(options.replay).is_empty(): _assert_coverage()
	if failures.is_empty():
		print("CANNON REACTION SOAK: PASS (", checks, " checks; profile=", options.profile, "; seed=", options.seed, ")")
		get_tree().quit(0)
		return
	if not first_artifact.is_empty(): printerr("Reproduce with: -- --mixed-replay=", _write_artifact(first_artifact))
	printerr("CANNON REACTION SOAK: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _curated_cases() -> void:
	# A dead Cannon's persisted shell enters on the Minotaur turn, damages the
	# Minotaur, destroys a major piece, resolves Rage first, then exposes Raise Dead.
	var position := _minotaur_necromancer_position(true)
	var result := await _run_steps("mortar-rage-raise", position, 1, 1101, true)
	_expect(result.ok, "curated Mortar -> Rage -> Raise Dead cascade matches")

	position = _overlapping_mortar_position()
	result = await _run_steps("overlapping-mortars", position, 1, 1102, true)
	_expect(result.ok, "overlapping mortars resolve deterministically")

	position = _forced_pass_mortar_position()
	result = await _run_steps("forced-pass-impact", position, 1, 1103, true)
	_expect(result.ok, "mortar consequences remain identical across a forced pass")

	position = _terminal_mortar_position()
	result = await _run_steps("terminal-impact", position, 1, 1104, true)
	_expect(result.ok, "lethal mortar battle completion matches")

	position = _legacy_mortar_position()
	var imported := ClassicChessCore.import_position(position)
	_expect(imported.ok, "legacy mortar fixture imports")
	if imported.ok:
		var legacy: ChessCoreAutonomousEntity = imported.state.autonomous_entities[0]
		_expect(int(legacy.custom_state.get("landing_turn", 0)) == 0, "legacy fixture begins without a landing turn")


func _random_walks(options: Dictionary) -> void:
	var master := RandomNumberGenerator.new(); master.seed = int(options.seed)
	for sequence in range(int(options.sequences)):
		var sequence_seed := int(master.randi())
		var family := sequence % 3
		var start := _cannon_necromancer_position() if family == 0 else (_cannon_minotaur_position() if family == 1 else _minotaur_necromancer_position(sequence % 2 == 0))
		var result := await _run_steps("random-%d" % sequence, start, int(options.plies), sequence_seed, false)
		stats.sequences += 1
		if not result.ok: break


func _live_authority_case() -> void:
	var model := _new_model(_forced_pass_mortar_position())
	var timeline: Array[String] = []
	model.arc_mortar_impact.connect(func(_entity, _area, _gate): timeline.append("impact"))
	model.reaction_selection_requested.connect(func(_piece, action_type, _targets): timeline.append("choice:%s" % action_type))
	model.autonomous_entity_removed.connect(func(_entity, reason, _gate): timeline.append("removed:%s" % reason))
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "mixed forced-pass position activates pure live authority")
	_expect(await model.resolve_unplayable_turns(), "pure live authority advances the forced pass")
	var pending := model.get_pending_reaction()
	_expect(not pending.is_empty(), "pure live authority exposes mortar-created Raise Dead")
	if not pending.is_empty():
		var selected = _deterministic_choice(pending.targets)
		_expect(await model.submit_reaction_selection(selected), "pure live authority settles mortar-created Raise Dead")
	_expect(model.is_settled(), "pure live authority settles after the delayed reaction")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "mixed live projection remains identical")
	_expect(timeline.find("impact") >= 0 and timeline.find("choice:raise_dead") > timeline.find("impact") and timeline.find("removed:impact") > timeline.find("impact"), "impact presentation precedes choice and removal")
	_free_model(model); await get_tree().process_frame


func _run_steps(label: String, start: ChessPosition, plies: int, seed: int, require_action := false) -> Dictionary:
	var model := _new_model(start)
	var imported := ClassicChessCore.import_position(start)
	if not _expect(imported.ok, "%s imports" % label):
		_free_model(model); return {"ok": false}
	var core: ChessCoreState = imported.state
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var history: Array[Dictionary] = []
	var completed := 0
	for ply in range(plies):
		if core.battle_over: break
		var model_map := _model_map(model.get_legal_primary_actions(model.current_turn))
		var core_map := _core_map(ClassicChessCore.legal_actions(core, core.current_turn))
		if not _same_keys(model_map, core_map, "%s ply %d legal actions" % [label, ply]):
			_capture_failure(seed, label, ply, start, history, model, core, model_map, core_map, "legal_action_mismatch")
			_free_model(model); return {"ok": false}
		if model_map.is_empty():
			model_events.clear()
			var pass_result := ClassicChessCore.resolve_forced_passes(core)
			var pass_trace: Array[ChessCoreEvent] = pass_result.events.duplicate()
			await model.resolve_unplayable_turns()
			_count_core_events(pass_trace)
			while pass_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
				if not _pending_choice_parity(model, pass_result, "%s forced pass %d" % [label, ply]):
					_free_model(model); return {"ok": false}
				var pass_choice = _deterministic_choice(pass_result.choice.options)
				var settled := ClassicChessCore.resolve_choice(pass_result.state, pass_choice)
				pass_trace.append_array(settled.events); _count_core_events(settled.events)
				await model.submit_reaction_selection(pass_choice)
				pass_result = settled
			if pass_result.status != ChessCoreStepResult.Status.COMPLETED:
				_fail("%s forced pass did not settle" % label); _free_model(model); return {"ok": false}
			core = pass_result.state
			history.append({"kind": "forced_pass"})
			stats.actions += 1; completed += 1
			if not _state_parity(model, core, "%s forced pass %d" % [label, ply]) or not _event_parity(model_events, _core_trace(pass_trace), "%s forced pass %d" % [label, ply]):
				_capture_failure(seed, label, ply, start, history, model, core, model_map, core_map, "forced_pass_mismatch")
				_free_model(model); return {"ok": false}
			continue
		var key := _choose_key(model_map, rng)
		var model_action: ChessPrimaryAction = model_map[key]
		var core_action: ChessCoreAction = core_map[key]
		var descriptor := ChessActionCodec.describe(model_action)
		model_events.clear()
		var core_result := ClassicChessCore.resolve_action(core, core_action)
		var core_trace: Array[ChessCoreEvent] = core_result.events.duplicate()
		var accepted := await _submit_model_action(model, model_action)
		if not _expect(accepted, "%s ply %d model accepts selected action" % [label, ply]):
			_capture_failure(seed, label, ply, start, history, model, core, model_map, core_map, "model_rejected")
			_free_model(model); return {"ok": false}
		_count_core_events(core_trace)
		while core_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			if not _pending_choice_parity(model, core_result, "%s ply %d" % [label, ply]):
				_capture_failure(seed, label, ply, start, history, model, core_result.state, model_map, core_map, "pending_choice_mismatch")
				_free_model(model); return {"ok": false}
			var selected = _deterministic_choice(core_result.choice.options)
			history.append({"kind": "choice", "value": _json_value(selected)})
			var choice_result := ClassicChessCore.resolve_choice(core_result.state, selected)
			core_trace.append_array(choice_result.events)
			_count_core_events(choice_result.events)
			if core_result.choice.kind == &"raise_dead": await model.submit_reaction_selection(selected)
			elif core_result.choice.kind == &"promotion": model.submit_promotion_selection(selected)
			else:
				_fail("%s exposed unsupported soak choice %s" % [label, core_result.choice.kind])
				_free_model(model); return {"ok": false}
			core_result = choice_result
		if not _expect(core_result.status == ChessCoreStepResult.Status.COMPLETED, "%s ply %d core completes" % [label, ply]):
			_free_model(model); return {"ok": false}
		core = core_result.state
		history.append({"kind": "action", "action": _json_descriptor(descriptor)})
		stats.actions += 1; completed += 1
		if not _state_parity(model, core, "%s ply %d" % [label, ply]):
			_capture_failure(seed, label, ply, start, history, model, core, model_map, core_map, "state_mismatch")
			_free_model(model); return {"ok": false}
		var normalized_core := _core_trace(core_trace)
		if not _event_parity(model_events, normalized_core, "%s ply %d" % [label, ply]):
			_capture_failure(seed, label, ply, start, history, model, core, model_map, core_map, "event_mismatch")
			_free_model(model); return {"ok": false}
	stats.positions_compared += completed
	if require_action: _expect(completed > 0, "%s executes its curated trigger" % label)
	_free_model(model)
	return {"ok": true, "completed": completed}


func _pending_choice_parity(model: ChessBoardModel, result: ChessCoreStepResult, context: String) -> bool:
	checks += 1
	if result.choice == null: failures.append("%s core exposed an empty choice" % context); return false
	if result.choice.kind == &"raise_dead":
		var pending := model.get_pending_reaction()
		var model_targets := _sorted_coords(pending.get("targets", [])) if not pending.is_empty() else []
		var core_targets := _sorted_coords(result.choice.options)
		if pending.is_empty() or model_targets != core_targets:
			failures.append("%s Raise Dead options differ: model=%s core=%s" % [context, model_targets, core_targets]); return false
		return true
	failures.append("%s unexpected pending choice kind %s" % [context, result.choice.kind])
	return false


func _state_parity(model: ChessBoardModel, core: ChessCoreState, context: String) -> bool:
	checks += 1
	var model_json := ChessPositionCodec.to_json(model.capture_position(), false)
	var core_json := ChessPositionCodec.to_json(ClassicChessCore.export_position(core), false)
	if model_json != core_json:
		failures.append("%s position differs\n  model=%s\n  core=%s" % [context, model_json, core_json]); return false
	if not model.is_settled() or core.pending_choice != null:
		failures.append("%s did not settle identically" % context); return false
	return true


func _event_parity(left: Array[Dictionary], right: Array[Dictionary], context: String) -> bool:
	checks += 1
	if left == right: return true
	failures.append("%s semantic event trace differs\n  model=%s\n  core=%s" % [context, left, right])
	return false


func _connect_trace(model: ChessBoardModel) -> void:
	model.autonomous_entity_added.connect(func(entity, _gate): model_events.append({"kind": "autonomous_entity_added", "entity_id": entity.entity_id}))
	model.arc_mortar_impact.connect(func(entity, _area, _gate): model_events.append({"kind": "arc_mortar_impact", "entity_id": entity.entity_id}))
	model.autonomous_entity_removed.connect(func(entity, reason, _gate): model_events.append({"kind": "autonomous_entity_removed", "entity_id": entity.entity_id, "reason": String(reason)}))
	model.piece_damaged.connect(func(piece, amount, hp, _max_hp): model_events.append({"kind": "piece_damaged", "piece_id": piece.piece_id, "amount": amount, "current_hp": hp}))
	model.piece_destroyed.connect(func(piece): model_events.append({"kind": "piece_destroyed", "piece_id": piece.piece_id}))
	model.reaction_queued.connect(func(piece, action_type, _event_data, sequence): model_events.append({"kind": "reaction_queued", "piece_id": piece.piece_id, "action_type": String(action_type), "sequence": sequence}))
	model.reaction_selection_requested.connect(func(piece, action_type, targets): model_events.append({"kind": "reaction_selection_requested", "piece_id": piece.piece_id, "action_type": String(action_type), "targets": _sorted_coords(targets)}))
	model.reaction_selection_committed.connect(func(piece, action_type, target): model_events.append({"kind": "reaction_selection_committed", "piece_id": piece.piece_id, "action_type": String(action_type), "target": _coord(target)}))
	model.reaction_selection_resolved.connect(func(piece, action_type, target): model_events.append({"kind": "reaction_selection_resolved", "piece_id": piece.piece_id, "action_type": String(action_type), "target": _coord(target)}))
	model.reaction_finished.connect(func(piece, action_type, _event_data, sequence, resolved): model_events.append({"kind": "reaction_finished", "piece_id": piece.piece_id if piece != null else "", "action_type": String(action_type), "sequence": sequence, "resolved": resolved}))
	model.turn_changed.connect(func(color): model_events.append({"kind": "turn_changed", "color": color, "global_turn_number": model.global_turn_number}))
	model.turn_passed.connect(func(color, count): model_events.append({"kind": "turn_passed", "color": color, "count": count}))
	model.battle_finished.connect(func(result): model_events.append({"kind": "battle_finished", "result": result}))


func _core_trace(events: Array[ChessCoreEvent]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event in events:
		var item := {"kind": String(event.kind)}
		match event.kind:
			&"autonomous_entity_added": item["entity_id"] = String(event.data.get("entity_id", ""))
			&"arc_mortar_impact": item["entity_id"] = String(event.data.get("entity_id", ""))
			&"autonomous_entity_removed": item.merge({"entity_id": String(event.data.get("entity_id", "")), "reason": String(event.data.get("reason", ""))})
			&"piece_damaged": item.merge({"piece_id": String(event.data.get("piece_id", "")), "amount": int(event.data.get("amount", 0)), "current_hp": int(event.data.get("current_hp", 0))})
			&"piece_destroyed": item["piece_id"] = String(event.data.get("piece_id", ""))
			&"reaction_queued": item.merge({"piece_id": String(event.data.get("piece_id", "")), "action_type": String(event.data.get("action_type", "")), "sequence": int(event.data.get("sequence", 0))})
			&"reaction_selection_requested": item.merge({"piece_id": String(event.data.get("piece_id", "")), "action_type": String(event.data.get("action_type", "")), "targets": _sorted_coords(event.data.get("targets", []))})
			&"reaction_selection_committed", &"reaction_selection_resolved": item.merge({"piece_id": String(event.data.get("piece_id", "")), "action_type": String(event.data.get("action_type", "")), "target": _coord(event.data.get("target", Vector2i.ZERO))})
			&"reaction_finished": item.merge({"piece_id": String(event.data.get("piece_id", "")), "action_type": String(event.data.get("action_type", "")), "sequence": int(event.data.get("sequence", 0)), "resolved": bool(event.data.get("resolved", false))})
			&"turn_changed": item.merge({"color": String(event.data.get("color", "")), "global_turn_number": int(event.data.get("global_turn_number", 0))})
			&"turn_passed": item.merge({"color": String(event.data.get("color", "")), "count": int(event.data.get("count", 0))})
			&"battle_finished": item["result"] = String(event.data.get("result", ""))
			_: continue
		output.append(item)
	return output


func _count_core_events(events: Array[ChessCoreEvent]) -> void:
	var impacts_this_step := 0
	for event in events:
		match event.kind:
			&"autonomous_entity_added": stats.mortar_launches += 1
			&"arc_mortar_impact":
				stats.mortar_impacts += 1; impacts_this_step += 1
				if String(event.data.get("entity_id", "")) in ["entity_90", "entity_91"]: stats.source_dead_impacts += 1
			&"automatic_reaction_started": stats.rage_triggers += 1
			&"reaction_selection_requested": stats.raise_dead_choices += 1
			&"turn_passed": stats.forced_passes += 1
			&"battle_finished": stats.terminal_battles += 1
	if impacts_this_step > 1: stats.overlapping_impacts += 1


func _choose_key(actions: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys := actions.keys(); keys.sort()
	var weighted: Array[String] = []
	for key in keys:
		var action: ChessPrimaryAction = actions[key]
		var weight := 1
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY: weight = 12
		elif action.piece.model.board[action.target.x][action.target.y] != null: weight = 7
		for _index in range(weight): weighted.append(key)
	return weighted[rng.randi_range(0, weighted.size() - 1)]


func _submit_model_action(model: ChessBoardModel, action: ChessPrimaryAction) -> bool:
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY: return await model.submit_active_ability(action.piece, action.target)
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
	failures.append("%s differ\n  model-only=%s\n  core-only=%s" % [context, _difference(left, right), _difference(right, left)])
	return false


func _new_model(position: ChessPosition) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; model.forced_pass_delay_seconds = 0.0
	add_child(model); model.load_position(position.copy()); _connect_trace(model); return model


func _position(pieces: Array, turn := "white", global_turn := 1) -> ChessPosition:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = turn; model.global_turn_number = global_turn
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position(); model.queue_free(); return result


func _ready_king(piece: KingPiece) -> KingPiece:
	piece.set_cooldown(0); piece.initial_cooldown_turn_pending = false; return piece


func _cannon_necromancer_position() -> ChessPosition:
	return _position([
		_ready_king(CannonKing.new("white", Vector2i(7, 7))), _ready_king(NecromancerKing.new("black", Vector2i(0, 0))),
		Rook.new("white", Vector2i(5, 1)), Bishop.new("white", Vector2i(6, 5)), Rook.new("black", Vector2i(2, 6)), Queen.new("black", Vector2i(3, 3)),
	])


func _cannon_minotaur_position() -> ChessPosition:
	return _position([
		_ready_king(CannonKing.new("white", Vector2i(7, 7))), _ready_king(MinotaurKing.new("black", Vector2i(0, 0))),
		Rook.new("white", Vector2i(5, 1)), Queen.new("white", Vector2i(4, 5)), Rook.new("black", Vector2i(2, 6)), Bishop.new("black", Vector2i(3, 3)),
	])


func _minotaur_necromancer_position(with_due_mortar: bool) -> ChessPosition:
	var minotaur := _ready_king(MinotaurKing.new("white", Vector2i(4, 4)))
	var necromancer := _ready_king(NecromancerKing.new("black", Vector2i(0, 7)))
	var position := _position([minotaur, necromancer, Rook.new("black", Vector2i(4, 5)), Bishop.new("white", Vector2i(6, 2)), Queen.new("black", Vector2i(2, 5))], "black", 1)
	if with_due_mortar: _append_mortar(position, "entity_90", Vector2i(4, 4), "white", 2)
	return position


func _overlapping_mortar_position() -> ChessPosition:
	var position := _position([_ready_king(MinotaurKing.new("white", Vector2i(4, 4))), _ready_king(NecromancerKing.new("black", Vector2i(0, 7))), Rook.new("black", Vector2i(4, 5)), Queen.new("black", Vector2i(5, 5))], "black", 1)
	_append_mortar(position, "entity_90", Vector2i(4, 4), "white", 2)
	_append_mortar(position, "entity_91", Vector2i(4, 4), "white", 2)
	return position


func _forced_pass_mortar_position() -> ChessPosition:
	var black := _ready_king(NecromancerKing.new("black", Vector2i(0, 7))); black.stunned = true; black.stun_timer = 3
	var position := _position([_ready_king(MinotaurKing.new("white", Vector2i(4, 4))), black, Rook.new("white", Vector2i(4, 5))], "black", 1)
	_append_mortar(position, "entity_90", Vector2i(4, 4), "white", 2)
	return position


func _terminal_mortar_position() -> ChessPosition:
	var king := ClassicKing.new("white", Vector2i(4, 4)); king.current_hp = 1
	var black := ClassicKing.new("black", Vector2i(0, 7))
	var position := _position([king, black, Rook.new("black", Vector2i(0, 0))], "black", 1)
	_append_mortar(position, "entity_90", Vector2i(4, 4), "white", 2)
	return position


func _legacy_mortar_position() -> ChessPosition:
	var position := _position([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 0))])
	_append_mortar(position, "entity_90", Vector2i(4, 4), "white", 0)
	return position


func _append_mortar(position: ChessPosition, id: String, anchor: Vector2i, owner: String, landing_turn: int) -> void:
	var entity := ChessAutonomousEntityState.new(); entity.entity_id = id; entity.type_id = &"arc_mortar"; entity.coordinate = anchor; entity.owner_color = owner
	if landing_turn > 0: entity.custom_state["landing_turn"] = landing_turn
	position.autonomous_entities.append(entity)


func _capture_failure(seed: int, label: String, ply: int, start: ChessPosition, history: Array, model: ChessBoardModel, core: ChessCoreState, model_map: Dictionary, core_map: Dictionary, reason: String) -> void:
	if not first_artifact.is_empty(): return
	first_artifact = {
		"schema": "crpg_cannon_reaction_soak_failure", "version": 1, "seed": seed, "label": label, "failing_ply": ply, "reason": reason,
		"start_position": ChessPositionCodec.to_dictionary(start), "history": history.duplicate(true),
		"legal": {"model": model_map.keys(), "core": core_map.keys()},
		"model_position": ChessPositionCodec.to_dictionary(model.capture_position()),
		"core_position": ChessPositionCodec.to_dictionary(ClassicChessCore.export_position(core)) if core != null and core.pending_choice == null else {},
		"model_events": model_events.duplicate(true),
	}


func _write_artifact(artifact: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIRECTORY))
	var path := "%s/failure-%s-%s.json" % [ARTIFACT_DIRECTORY, artifact.seed, Time.get_unix_time_from_system()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(artifact, "  "))
	return path


func _replay_artifact(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not _expect(file != null, "replay artifact opens"): return
	var artifact = JSON.parse_string(file.get_as_text())
	if not _expect(artifact is Dictionary and artifact.get("schema", "") == "crpg_cannon_reaction_soak_failure", "replay artifact schema is valid"): return
	var decoded := ChessPositionCodec.from_dictionary(artifact.start_position)
	if not _expect(decoded.position != null, "replay start position decodes"): return
	# Re-running with the recorded seed follows the same deterministic weighted choices.
	await _run_steps("replay", decoded.position, int(artifact.get("failing_ply", 0)) + 1, int(artifact.seed), false)


func _assert_coverage() -> void:
	for key in ["mortar_impacts", "rage_triggers", "raise_dead_choices", "overlapping_impacts", "source_dead_impacts"]:
		_expect(int(stats.get(key, 0)) > 0, "soak exercises %s" % key)


func _deterministic_choice(options: Array):
	var ordered := options.duplicate()
	ordered.sort_custom(func(a, b):
		if a is Vector2i and b is Vector2i: return a.x < b.x if a.x != b.x else a.y < b.y
		return String(a) < String(b)
	)
	return ordered[0]


func _sorted_coords(values: Array) -> Array:
	var output := []
	for value in values: output.append(_coord(value))
	output.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	return output


func _json_descriptor(value: Dictionary) -> Dictionary:
	return {"kind": value.kind, "piece_id": value.piece_id, "from": value.from.duplicate(), "target": value.target.duplicate(), "path": value.path.duplicate(true)}


func _json_value(value): return _coord(value) if value is Vector2i else String(value) if value is StringName else value
func _coord(value: Vector2i) -> Array[int]: return [value.x, value.y]
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
func _fail(message: String) -> void: failures.append(message)


func _options() -> Dictionary:
	var output := {"profile": "gate", "seed": DEFAULT_SEED, "sequences": GATE_SEQUENCES, "plies": GATE_PLIES, "replay": ""}
	for argument in OS.get_cmdline_user_args():
		if argument == "--mixed-profile=soak": output.profile = "soak"; output.sequences = SOAK_SEQUENCES; output.plies = SOAK_PLIES
		elif argument.begins_with("--mixed-seed="): output.seed = int(argument.trim_prefix("--mixed-seed="))
		elif argument.begins_with("--mixed-sequences="): output.sequences = maxi(1, int(argument.trim_prefix("--mixed-sequences=")))
		elif argument.begins_with("--mixed-plies="): output.plies = maxi(1, int(argument.trim_prefix("--mixed-plies=")))
		elif argument.begins_with("--mixed-replay="): output.replay = argument.trim_prefix("--mixed-replay=")
	return output
