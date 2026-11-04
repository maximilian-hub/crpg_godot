extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_capture_square_marks()
	await _test_summon_and_autonomous_lifecycle()
	await _test_projectile_curse_marks_and_boosts()
	await _test_target_destruction_cleanup()
	await _test_forced_pass_pursuit()
	await _test_necromancer_reaction_order()
	await _test_live_authority()
	await _test_randomized_differential()
	await _test_mixed_differential()
	_test_validation()
	if failures.is_empty():
		print("WRAITH CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("WRAITH CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_capture_square_marks() -> void:
	var wraith := WraithKing.new("white", Vector2i(7, 7)); wraith.initial_cooldown_turn_pending = false
	var rook := Rook.new("white", Vector2i(4, 0))
	var victim := Pawn.new("black", Vector2i(4, 3))
	var model := _model([wraith, rook, victim, ClassicKing.new("black", Vector2i(0, 7))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng_before = state.random_states.get(WraithCoreRules.CURSE_MARK_RANDOM_STREAM)
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, victim.coordinate))
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and result.state.tile_effects.size() == 1, "any allied piece capture creates exactly one Cursed Mark")
	_expect(result.state.tile_effects[0].coordinate == victim.coordinate and result.state.tile_effects[0].source_piece_id == wraith.piece_id, "the Cursed Mark occupies the defeated piece's square and belongs to the allied Wraith King")
	_expect(result.state.random_states.get(WraithCoreRules.CURSE_MARK_RANDOM_STREAM) == rng_before, "deterministic capture-square placement does not advance legacy Wraith RNG")
	await model.submit_move(rook, victim.coordinate)
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "allied capture-mark placement exactly matches ChessBoardModel")
	model.free(); await get_tree().process_frame

	# The physical King may stand on marks, but only autonomous projectiles use them.
	wraith = WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	model = _model([wraith, ClassicKing.new("black", Vector2i(0, 7))])
	state = ClassicChessCore.import_position(model.capture_position()).state
	_add_core_mark(state, wraith.piece_id, "white", Vector2i(3, 3))
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, wraith.piece_id, Vector2i(3, 3)))
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and result.state.pending_choice == null, "the Wraith King receives no Lingering Malice choice on a Cursed Mark")
	_expect(result.state.tile_effects.size() == 1 and result.state.tile_effects[0].coordinate == Vector2i(3, 3), "the Wraith King does not consume a Cursed Mark")
	model.free(); await get_tree().process_frame

	# A capture refreshes an opposing mark instead of stacking another effect.
	wraith = WraithKing.new("white", Vector2i(7, 7)); wraith.initial_cooldown_turn_pending = false
	var enemy_wraith := WraithKing.new("black", Vector2i(0, 7)); enemy_wraith.initial_cooldown_turn_pending = false
	rook = Rook.new("white", Vector2i(4, 0)); victim = Pawn.new("black", Vector2i(4, 3))
	model = _model([wraith, rook, victim, enemy_wraith])
	state = ClassicChessCore.import_position(model.capture_position()).state
	_add_core_mark(state, enemy_wraith.piece_id, "black", victim.coordinate)
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, victim.coordinate))
	_expect(result.state.tile_effects.size() == 1 and result.state.tile_effects[0].source_piece_id == wraith.piece_id and result.state.tile_effects[0].owner_color == "white", "capture refreshes one existing mark to the capturing Wraith army")
	_expect(result.events.any(func(event: ChessCoreEvent): return event.kind == &"tile_effect_refreshed"), "mark refresh has an explicit deterministic lifecycle event")
	model.free(); await get_tree().process_frame

	# En passant marks the defeated pawn's square, not the capturing pawn's landing square.
	wraith = WraithKing.new("white", Vector2i(7, 7)); wraith.initial_cooldown_turn_pending = false
	var white_pawn := Pawn.new("white", Vector2i(3, 4)); var black_pawn := Pawn.new("black", Vector2i(3, 5))
	model = _model([wraith, white_pawn, black_pawn, ClassicKing.new("black", Vector2i(0, 7))])
	state = ClassicChessCore.import_position(model.capture_position()).state
	state.last_move = {"piece_id": black_pawn.piece_id, "piece_type": &"pawn", "piece_color": "black", "from": Vector2i(1, 5), "to": black_pawn.coordinate}
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, white_pawn.piece_id, Vector2i(2, 5)))
	_expect(result.state.tile_effects.size() == 1 and result.state.tile_effects[0].coordinate == Vector2i(3, 5), "en passant marks its distinct captured square")
	model.free(); await get_tree().process_frame

	var classic := ClassicKing.new("white", Vector2i(7, 7))
	rook = Rook.new("white", Vector2i(4, 0)); victim = Pawn.new("black", Vector2i(4, 3))
	model = _model([classic, rook, victim, ClassicKing.new("black", Vector2i(0, 7))])
	state = ClassicChessCore.import_position(model.capture_position()).state
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, victim.coordinate))
	_expect(result.state.tile_effects.is_empty(), "an army without a Wraith King creates no Cursed Mark")
	model.free(); await get_tree().process_frame


func _test_projectile_curse_marks_and_boosts() -> void:
	var wraith := WraithKing.new("white", Vector2i(7, 7)); wraith.initial_cooldown_turn_pending = false
	var target: ModelPiece = Rook.new("black", Vector2i(1, 1)); target.max_hp = 2; target.current_hp = 2
	var enemy_wraith := WraithKing.new("black", Vector2i(0, 7)); enemy_wraith.initial_cooldown_turn_pending = false
	var model := _model([wraith, target, enemy_wraith])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	_add_core_mark(state, enemy_wraith.piece_id, "black", Vector2i(3, 3))
	_add_core_mark(state, enemy_wraith.piece_id, "black", Vector2i(2, 2))
	_add_core_wraith(state, wraith.piece_id, target.piece_id, Vector2i(4, 4), "white")
	var events: Array[ChessCoreEvent] = []
	ClassicChessCore._run_wraith_phase(state, "white", events, true)
	_expect(events.filter(func(event): return event.kind == &"autonomous_entity_moved").size() == 3, "a projectile chains through shared opposing Cursed Marks in one activation")
	_expect(events.filter(func(event): return event.kind == &"tile_effect_removed").size() == 2 and state.tile_effects.is_empty(), "projectile boosts consume each traversed mark")
	_expect(state.piece_by_id(target.piece_id).current_hp == 1 and state.autonomous_entities.is_empty(), "nonlethal target impact damages and removes the projectile")
	_expect(not events.any(func(event): return event.kind == &"tile_effect_added"), "nonlethal projectile damage creates no Cursed Mark")
	model.free(); await get_tree().process_frame

	wraith = WraithKing.new("white", Vector2i(7, 7)); wraith.initial_cooldown_turn_pending = false
	target = Pawn.new("black", Vector2i(1, 1))
	model = _model([wraith, target, ClassicKing.new("black", Vector2i(0, 7))])
	state = ClassicChessCore.import_position(model.capture_position()).state
	_add_core_wraith(state, wraith.piece_id, target.piece_id, Vector2i(2, 2), "white")
	events = []
	ClassicChessCore._run_wraith_phase(state, "white", events, true)
	var additions := events.filter(func(event): return event.kind == &"tile_effect_added")
	_expect(state.piece_by_id(target.piece_id) == null and additions.size() == 1, "lethal projectile capture creates exactly one target-square Cursed Mark")
	_expect(additions[0].data.get("spawn_reason") == &"wraith_projectile_capture" and state.tile_effects[0].source_piece_id == wraith.piece_id and state.tile_effects[0].coordinate == target.coordinate, "projectile-created mark retains its summoning King attribution at the impact square")
	model.free(); await get_tree().process_frame

	wraith = WraithKing.new("white", Vector2i(7, 7)); wraith.initial_cooldown_turn_pending = false
	target = Rook.new("black", Vector2i(1, 1)); target.max_hp = 2; target.current_hp = 2
	model = _model([wraith, target, ClassicKing.new("black", Vector2i(0, 7))])
	state = ClassicChessCore.import_position(model.capture_position()).state
	_add_core_mark(state, wraith.piece_id, "white", target.coordinate)
	_add_core_wraith(state, wraith.piece_id, target.piece_id, Vector2i(2, 2), "white")
	events = []
	ClassicChessCore._run_wraith_phase(state, "white", events, true)
	_expect(state.tile_effects.size() == 1 and state.tile_effects[0].coordinate == target.coordinate, "target impact takes priority and leaves its Cursed Mark untouched")
	model.free(); await get_tree().process_frame


func _test_summon_and_autonomous_lifecycle() -> void:
	var wraith := WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(1, 1)); target.max_hp = 2; target.current_hp = 2
	var model := _model([wraith, Rook.new("white", Vector2i(7, 0)), target, ClassicKing.new("black", Vector2i(0, 7))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, wraith.piece_id, target.coordinate))
	await model.submit_active_ability(wraith, target.coordinate)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and result.state.autonomous_entities.size() == 1, "Summon Wraith creates one settled autonomous entity")
	var entity: ChessCoreAutonomousEntity = result.state.autonomous_entities[0]
	_expect(entity.target_piece_id == target.piece_id and int(entity.custom_state.next_move_turn) == 4, "summoned Wraith tracks its target and first movement round")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Summon Wraith exactly matches ChessBoardModel")

	# Force the scheduled round and execute the same harmless owner action.
	result.state.global_turn_number = 4; result.state.current_turn = "white"
	var wraith_id := wraith.piece_id
	_expect(model.load_position(ClassicChessCore.export_position(result.state)), "scheduled Wraith fixture reloads through the authoritative position boundary")
	wraith = model.find_piece_by_id(wraith_id) as WraithKing
	var core_move := _find(result.state, ChessCoreAction.Kind.MOVE, wraith.piece_id, Vector2i(4, 5))
	var moved := ClassicChessCore.resolve_action(result.state, core_move)
	await model.submit_move(wraith, Vector2i(4, 5))
	_expect(moved.state.autonomous_entities[0].coordinate == Vector2i(3, 3), "due Wraith advances one kingwise square after its owner's action")
	_expect(int(moved.state.autonomous_entities[0].custom_state.next_move_turn) == 7, "Wraith movement schedules the next three-round interval")
	_expect(_json(moved.state) == ChessPositionCodec.to_json(model.capture_position(), false), "scheduled Wraith movement exactly matches ChessBoardModel")
	model.free(); await get_tree().process_frame

	wraith = WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	model = _model([wraith, ClassicKing.new("black", Vector2i(0, 7))])
	var orphan := ChessAutonomousEntityState.new(); orphan.entity_id = model._allocate_state_id("entity"); orphan.type_id = &"wraith"; orphan.coordinate = Vector2i(3, 3); orphan.owner_color = "white"; orphan.source_piece_id = wraith.piece_id; orphan.target_piece_id = "piece_missing"; orphan.custom_state = {"next_move_turn": 1}
	var orphan_position := model.capture_position().copy()
	orphan_position.autonomous_entities.append(orphan)
	_expect(not ChessPositionValidator.validate(orphan_position).structural_errors.is_empty(), "an orphaned Wraith is rejected as non-authoritative state")
	var imported := ClassicChessCore.import_position(orphan_position)
	_expect(not imported.ok, "the pure core rejects an orphaned Wraith")
	model.free(); await get_tree().process_frame


func _test_target_destruction_cleanup() -> void:
	var wraith := WraithKing.new("black", Vector2i(0, 0)); wraith.initial_cooldown_turn_pending = false
	var target := Pawn.new("white", Vector2i(3, 3))
	var hunter := Rook.new("black", Vector2i(3, 7))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), wraith, target, hunter])
	var wraith_id := wraith.piece_id
	var target_id := target.piece_id
	var hunter_id := hunter.piece_id
	var entity := ChessAutonomousEntityState.new()
	entity.entity_id = model._allocate_state_id("entity"); entity.type_id = &"wraith"; entity.coordinate = Vector2i(1, 1)
	entity.owner_color = "black"; entity.source_piece_id = wraith.piece_id; entity.target_piece_id = target.piece_id; entity.custom_state = {"next_move_turn": 20}
	var targeted_position := model.capture_position().copy()
	targeted_position.current_turn = "black"
	targeted_position.autonomous_entities.append(entity)
	_expect(model.load_position(targeted_position), "targeted Wraith fixture loads through the authoritative position boundary")
	wraith = model.find_piece_by_id(wraith_id) as WraithKing
	target = model.find_piece_by_id(target_id) as Pawn
	hunter = model.find_piece_by_id(hunter_id) as Rook
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "valid targeted Wraith fixture imports")
	var result := ClassicChessCore.resolve_action(imported.state, _find(imported.state, ChessCoreAction.Kind.MOVE, hunter.piece_id, target.coordinate))
	await model.submit_move(hunter, target.coordinate)
	_expect(result.state.autonomous_entities.is_empty(), "destroying a Wraith target removes its chaser immediately")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "target-destruction Wraith cleanup exactly matches ChessBoardModel")
	model.free(); await get_tree().process_frame


func _test_necromancer_reaction_order() -> void:
	var wraith := WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	var victim := Queen.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7)); necromancer.initial_cooldown_turn_pending = false
	var model := _model([wraith, victim, necromancer])
	_add_model_mark(model, wraith, victim.coordinate)
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, wraith.piece_id, victim.coordinate))
	await model.submit_move(wraith, victim.coordinate)
	_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and result.choice.kind == &"raise_dead", "enemy Raise Dead remains available after a Wraith-army capture creates a mark")
	_expect(model.get_pending_reaction().action_type == "raise_dead", "model exposes the same capture reaction")
	var raise_target: Vector2i = result.choice.options[0]
	result = ClassicChessCore.resolve_choice(result.state, raise_target)
	await model.submit_reaction_selection(raise_target)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and not model.has_pending_reaction(), "Raise Dead settles without an obsolete Lingering Malice follow-up")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Raise Dead and capture-mark placement settle identically")
	model.free(); await get_tree().process_frame


func _test_forced_pass_pursuit() -> void:
	var wraith := WraithKing.new("white", Vector2i(4, 4)); wraith.stunned = true; wraith.stun_timer = 20; wraith.initial_cooldown_turn_pending = false
	var target := ClassicKing.new("black", Vector2i(0, 7))
	var model := _model([wraith, target])
	var entity := ChessAutonomousEntityState.new(); entity.entity_id = model._allocate_state_id("entity"); entity.type_id = &"wraith"; entity.coordinate = Vector2i(1, 6); entity.owner_color = "white"; entity.source_piece_id = wraith.piece_id; entity.target_piece_id = target.piece_id; entity.custom_state = {"next_move_turn": 1}
	var pursuit_position := model.capture_position().copy()
	pursuit_position.autonomous_entities.append(entity)
	_expect(model.load_position(pursuit_position), "forced-pass Wraith fixture loads through the authoritative position boundary")
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_forced_passes(state)
	await model.resolve_unplayable_turns()
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED, "forced-pass Wraith pursuit settles synchronously")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "forced-pass pursuit and terminal damage exactly match ChessBoardModel")
	model.free(); await get_tree().process_frame


func _test_live_authority() -> void:
	var wraith := WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(1, 1))
	var model := _model([wraith, target, ClassicKing.new("black", Vector2i(0, 7))])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Wraith position activates experimental pure authority")
	_expect(await model.submit_active_ability(wraith, target.coordinate), "pure live authority accepts Summon Wraith")
	_expect(model.autonomous_entities.size() == 1 and model.get_live_authority_diagnostics().projection_mismatches == 0, "live summon projects one Wraith without divergence")
	model.free(); await get_tree().process_frame

	var victim := Pawn.new("black", Vector2i(3, 3))
	wraith = WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	model = _model([wraith, victim, ClassicKing.new("black", Vector2i(0, 7))])
	_add_model_mark(model, wraith, victim.coordinate)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "capture-mark fixture activates pure authority")
	_expect(await model.submit_move(wraith, victim.coordinate) and not model.has_pending_reaction(), "live Wraith King capture settles without bonus movement")
	_expect(wraith.coordinate == victim.coordinate and model.tile_effects.size() == 1 and model.tile_effects[0].coordinate == victim.coordinate and model.get_live_authority_diagnostics().projection_mismatches == 0, "live capture refreshes its square's mark without moving the physical King again")
	model.free(); await get_tree().process_frame

	wraith = WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	var queen := Queen.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7)); necromancer.initial_cooldown_turn_pending = false
	model = _model([wraith, queen, necromancer])
	_add_model_mark(model, wraith, queen.coordinate)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "mixed Wraith/Necromancer fixture activates pure authority")
	_expect(await model.submit_move(wraith, queen.coordinate) and model.get_pending_reaction().action_type == "raise_dead", "live mixed capture preserves Raise Dead priority")
	var raise_target: Vector2i = model.get_pending_reaction().targets[0]
	_expect(await model.submit_reaction_selection(raise_target) and not model.has_pending_reaction(), "live mixed bridge settles after Raise Dead without Lingering Malice")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "mixed Wraith/Necromancer live projection remains identical")
	model.free(); await get_tree().process_frame


func _test_validation() -> void:
	var wraith := WraithKing.new("white", Vector2i(4, 4)); wraith.initial_cooldown_turn_pending = false
	var model := _model([wraith, ClassicKing.new("black", Vector2i(0, 7))])
	var position := model.capture_position()
	var unsupported := ChessTileEffectState.new(); unsupported.effect_id = "effect_99"; unsupported.type_id = &"archer_arrow"; unsupported.coordinate = Vector2i(2, 2); unsupported.owner_color = "white"; unsupported.source_piece_id = wraith.piece_id
	position.tile_effects.append(unsupported)
	_expect(not ClassicChessCore.import_position(position).ok, "unmigrated tile effects retain safe model fallback")
	model.free()


func _test_randomized_differential() -> void:
	var white := WraithKing.new("white", Vector2i(7, 4)); white.initial_cooldown_turn_pending = false
	var black := WraithKing.new("black", Vector2i(0, 4)); black.initial_cooldown_turn_pending = false
	var model := _model([
		white, Queen.new("white", Vector2i(6, 3)), Rook.new("white", Vector2i(7, 0)), Pawn.new("white", Vector2i(5, 2)),
		black, Queen.new("black", Vector2i(1, 3)), Rook.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(2, 5)),
	])
	var settled_actions := await _run_differential(model, 441177, 24, "Wraith")
	_expect(settled_actions >= 12, "random Wraith differential completes a useful bounded sequence")
	model.free(); await get_tree().process_frame


func _test_mixed_differential() -> void:
	for spec in [[CannonKing.new("black", Vector2i(0, 4)), 77331, "Wraith/Cannon"], [MinotaurKing.new("black", Vector2i(0, 4)), 77332, "Wraith/Minotaur"]]:
		var white := WraithKing.new("white", Vector2i(7, 4)); white.initial_cooldown_turn_pending = false
		var black: KingPiece = spec[0]; black.set_cooldown(0); black.initial_cooldown_turn_pending = false
		var model := _model([
			white, Queen.new("white", Vector2i(6, 3)), Rook.new("white", Vector2i(7, 0)), Pawn.new("white", Vector2i(5, 2)),
			black, Queen.new("black", Vector2i(1, 3)), Rook.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(2, 5)),
		])
		var settled := await _run_differential(model, int(spec[1]), 16, String(spec[2]))
		_expect(settled >= 8 or model.battle_over, "%s differential completes a useful bounded sequence" % spec[2])
		model.free(); await get_tree().process_frame


func _run_differential(model: ChessBoardModel, seed: int, max_plies: int, label: String) -> int:
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var settled_actions := 0
	for _ply in range(max_plies):
		if state.battle_over: break
		var core_actions := ClassicChessCore.legal_actions(state, state.current_turn)
		var model_actions := model.get_legal_primary_actions(model.current_turn)
		_expect(_core_action_keys(core_actions) == _model_action_keys(model_actions), "%s differential legal actions match at ply %d" % [label, _ply])
		if core_actions.is_empty(): break
		var selected: ChessCoreAction = core_actions[rng.randi_range(0, core_actions.size() - 1)]
		var model_action := _matching_model_action(model_actions, selected)
		var result := ClassicChessCore.resolve_action(state, selected)
		if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY: await model.submit_active_ability(model_action.piece, model_action.target)
		elif model_action.path.size() > 1: await model.submit_move_path(model_action.piece, model_action.path)
		else: await model.submit_move(model_action.piece, model_action.target)
		while result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			var option = result.choice.options[0]
			result = ClassicChessCore.resolve_choice(result.state, option)
			if model.has_pending_reaction(): await model.submit_reaction_selection(option)
		state = result.state
		settled_actions += 1
		_expect(_json(state) == ChessPositionCodec.to_json(model.capture_position(), false), "%s differential state matches at ply %d" % [label, _ply])
	return settled_actions


func _core_action_keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_action_key(action.kind, action.piece_id, action.target, action.path))
	result.sort(); return result


func _model_action_keys(actions: Array[ChessPrimaryAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_action_key(action.kind, action.piece.piece_id, action.target, action.path))
	result.sort(); return result


func _matching_model_action(actions: Array[ChessPrimaryAction], selected: ChessCoreAction) -> ChessPrimaryAction:
	var key := _action_key(selected.kind, selected.piece_id, selected.target, selected.path)
	for action in actions:
		if _action_key(action.kind, action.piece.piece_id, action.target, action.path) == key: return action
	return null


func _action_key(kind: int, piece_id: String, target: Vector2i, path: Array) -> String:
	return "%s|%s|%s|%s" % [kind, piece_id, target, path]


func _model(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _add_core_mark(state: ChessCoreState, source_piece_id: String, owner_color: String, coordinate: Vector2i) -> void:
	var mark := ChessCoreTileEffect.new()
	mark.effect_id = state.allocate_state_id("effect")
	mark.type_id = &"cursed_mark"
	mark.coordinate = coordinate
	mark.owner_color = owner_color
	mark.source_piece_id = source_piece_id
	state.add_effect(mark)


func _add_model_mark(model: ChessBoardModel, source: WraithKing, coordinate: Vector2i) -> void:
	var mark := ChessTileEffectState.new()
	mark.effect_id = model._allocate_state_id("effect")
	mark.type_id = &"cursed_mark"
	mark.coordinate = coordinate
	mark.owner_color = source.color
	mark.source_piece_id = source.piece_id
	model.tile_effects.append(mark)


func _add_core_wraith(state: ChessCoreState, source_piece_id: String, target_piece_id: String, coordinate: Vector2i, owner_color: String) -> void:
	var entity := ChessCoreAutonomousEntity.new()
	entity.entity_id = state.allocate_state_id("entity")
	entity.type_id = &"wraith"
	entity.coordinate = coordinate
	entity.owner_color = owner_color
	entity.source_piece_id = source_piece_id
	entity.target_piece_id = target_piece_id
	entity.custom_state = {"next_move_turn": state.global_turn_number}
	state.add_entity(entity)


func _find(state: ChessCoreState, kind: int, piece_id: String, target: Vector2i) -> ChessCoreAction:
	for action in ClassicChessCore.legal_actions(state, state.current_turn):
		if action.kind == kind and action.piece_id == piece_id and action.target == target: return action
	return null


func _json(state: ChessCoreState) -> String:
	return ChessPositionCodec.to_json(ClassicChessCore.export_position(state), false)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
