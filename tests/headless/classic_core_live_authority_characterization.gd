extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_quiet_damage_and_capture()
	await _test_castle_and_en_passant()
	await _test_promotion_and_battle()
	await _test_forced_passes()
	await _test_cpu_execution()
	await _test_cpu_soak()
	await _test_arakne_live_authority()
	await _test_necromancer_live_authority()
	await _test_minotaur_live_authority()
	await _test_quarterly_live_authority()
	await _test_archer_live_authority()
	_test_mandatory_authority()
	if failures.is_empty():
		print("CLASSIC CORE LIVE AUTHORITY: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("CLASSIC CORE LIVE AUTHORITY: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_quiet_damage_and_capture() -> void:
	var durable := Rook.new("black", Vector2i(4, 2)); durable.max_hp = 2; durable.current_hp = 2
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4)), durable])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "compatible position activates core authority")
	var signals := {"started": 0, "finished": 0, "turn": 0, "settled": 0, "committed": 0}
	model.action_started.connect(func(_color): signals.started += 1)
	model.action_finished.connect(func(): signals.finished += 1)
	model.turn_changed.connect(func(_color): signals.turn += 1)
	model.settled_action_completed.connect(func(): signals.settled += 1)
	model.primary_action_committed.connect(func(_descriptor): signals.committed += 1)
	var revision := model.position_revision
	_expect(await model.submit_move(model.board[4][4], Vector2i(4, 2)), "nonlethal core attack is accepted")
	_expect(model.board[4][4] != null and model.board[4][2].current_hp == 1 and model.current_turn == "black", "nonlethal core attack projects damage without moving")
	_expect(model.position_revision == revision + 1 and model.get_live_authority_diagnostics().projection_mismatches == 0, "core action advances one revision with matching projection")
	_expect(signals == {"started": 1, "finished": 1, "turn": 1, "settled": 1, "committed": 1}, "core action emits each public lifecycle signal exactly once")
	model.current_turn = "white"; model._classic_core_bridge.state.current_turn = "white"
	_expect(await model.submit_move(model.board[4][4], Vector2i(4, 2)), "lethal follow-up capture is accepted")
	_expect(model.board[4][2] != null and model.board[4][2].color == "white" and model.board[4][4] == null, "lethal core capture projects board ownership")
	model.queue_free(); await get_tree().process_frame

	model = _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4))])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_move(model.board[4][4], Vector2i(4, 1)), "quiet core move is accepted")
	_expect(model.board[4][1] != null and model.current_turn == "black", "quiet core move projects destination and turn")
	model.queue_free(); await get_tree().process_frame


func _test_castle_and_en_passant() -> void:
	var model := _model([ClassicKing.new("white", Vector2i(7, 4)), Rook.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_move(model.board[7][4], Vector2i(7, 6)), "core castling is accepted")
	_expect(model.board[7][6] is ClassicKing and model.board[7][5] is Rook, "core castling projects both pieces atomically")
	model.queue_free(); await get_tree().process_frame

	var white_pawn := Pawn.new("white", Vector2i(3, 4)); white_pawn.has_moved = true
	var black_pawn := Pawn.new("black", Vector2i(1, 5))
	model = _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), white_pawn, black_pawn], "black")
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	await model.submit_move(black_pawn, Vector2i(3, 5))
	_expect(await model.submit_move(white_pawn, Vector2i(2, 5)), "core en passant is accepted")
	_expect(model.board[2][5] == white_pawn and model.board[3][5] == null, "core en passant projects its distinct capture square")
	model.queue_free(); await get_tree().process_frame


func _test_promotion_and_battle() -> void:
	var pawn := Pawn.new("white", Vector2i(1, 0))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), pawn])
	model.promotion_selection_requested.connect(func(_piece, _options): model.call_deferred("submit_promotion_selection", &"rook"))
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_move(pawn, Vector2i(0, 0)), "core promotion action completes through existing choice signal")
	_expect(model.board[0][0] is Rook and model.current_turn == "black" and model.is_settled(), "selected underpromotion projects and completes the turn")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "promotion projection matches authoritative core state")
	model.queue_free(); await get_tree().process_frame

	var attacker := Rook.new("white", Vector2i(1, 0))
	model = _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 0)), attacker])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_move(attacker, Vector2i(0, 0)), "core King capture is accepted")
	_expect(model.battle_over and model.battle_result == "white" and model.is_settled(), "core King capture projects terminal result")
	model.queue_free(); await get_tree().process_frame


func _test_mandatory_authority() -> void:
	var model := _model([ArcherKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Archer position activates mandatory core authority")
	var diagnostics := model.get_live_authority_diagnostics()
	_expect(diagnostics.active == "classic_core" and String(diagnostics.fallback_reason).is_empty(), "Archer activation has no legacy fallback")
	_expect(not model.set_live_authority(999), "no alternate live authority can be restored")
	model.queue_free()


func _test_archer_live_authority() -> void:
	var archer := ArcherKingQuiver.new("white", Vector2i(4, 4)); archer.current_cooldown = 0; archer.initial_cooldown_turn_pending = false
	var target := Pawn.new("black", Vector2i(1, 4)); target.max_hp = 2; target.current_hp = 2
	var model := _model([archer, ClassicKing.new("black", Vector2i(0, 7)), target])
	_expect(await model.submit_move(archer, target.coordinate), "live core accepts a Quiver Sharpshooter attack")
	_expect(target.current_hp == 1 and archer.coordinate == Vector2i(4, 4) and model.has_tile_effect(&"archer_arrow", target.coordinate, archer.piece_id), "live Quiver shot projects damage and its arrow without moving")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "Archer live projection matches authoritative state")
	model.queue_free(); await get_tree().process_frame


func _test_forced_passes() -> void:
	var white := ClassicKing.new("white", Vector2i(7, 7)); white.stunned = true; white.stun_timer = 20
	var black := ClassicKing.new("black", Vector2i(0, 7)); black.stunned = true; black.stun_timer = 20
	var model := _model([white, black])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.resolve_unplayable_turns(), "core authority resolves an unplayable loaded position")
	_expect(model.battle_over and model.battle_result == "draw" and model.is_settled(), "six core forced passes project a settled draw")
	model.queue_free(); await get_tree().process_frame


func _test_necromancer_live_authority() -> void:
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7)); necromancer.set_cooldown(0); necromancer.initial_cooldown_turn_pending = false
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(4, 3))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), rook, necromancer, bishop])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Necromancer position activates pure authority")
	_expect(await model.submit_move(rook, bishop.coordinate) and model.has_pending_reaction(), "live core capture pauses on the existing Raise Dead API")
	_expect(model.capture_position() == null, "pending core reactions cannot masquerade as settled position snapshots")
	var target: Vector2i = model.get_pending_reaction().targets[0]
	_expect(await model.submit_reaction_selection(target), "live core accepts a human-owned Raise Dead coordinate")
	_expect(model.board[target.x][target.y] is BonePawn and model.current_turn == "black" and model.is_settled(), "Raise Dead projects its summon and resumes the action")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "Raise Dead projection matches authoritative state")
	model.queue_free(); await get_tree().process_frame

	# Projection parity must be established before public completion listeners
	# can begin another lifecycle operation or mutate presentation-only state.
	necromancer = NecromancerKing.new("black", Vector2i(0, 7)); necromancer.set_cooldown(0); necromancer.initial_cooldown_turn_pending = false
	rook = Rook.new("white", Vector2i(4, 0)); bishop = Bishop.new("black", Vector2i(4, 3))
	model = _model([ClassicKing.new("white", Vector2i(7, 7)), rook, necromancer, bishop])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	var completion_listener := {"ran": false}
	model.action_finished.connect(func():
		completion_listener.ran = true
		model.global_turn_number += 100
	, CONNECT_ONE_SHOT)
	_expect(await model.submit_move(rook, bishop.coordinate) and model.has_pending_reaction(), "Raise Dead ordering fixture reaches its reaction choice")
	target = model.get_pending_reaction().targets[0]
	_expect(await model.submit_reaction_selection(target), "Raise Dead ordering fixture settles")
	var ordering_diagnostics := model.get_live_authority_diagnostics()
	_expect(completion_listener.ran and ordering_diagnostics.projection_mismatches == 0, "Raise Dead parity is checked before completion listeners can alter the settled facade (listener=%s, mismatches=%s, context=%s)" % [completion_listener.ran, ordering_diagnostics.projection_mismatches, ordering_diagnostics.last_projection_mismatch_context])
	model.queue_free(); await get_tree().process_frame


	necromancer = NecromancerKing.new("black", Vector2i(0, 7)); necromancer.set_cooldown(0); necromancer.initial_cooldown_turn_pending = false
	rook = Rook.new("white", Vector2i(4, 0)); bishop = Bishop.new("black", Vector2i(4, 3))
	model = _model([ClassicKing.new("white", Vector2i(7, 7)), rook, necromancer, bishop])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu)
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE); cpu.set_random_seed(551); cpu.configure(true, "black")
	model.reaction_selection_resolved.connect(func(_piece, _action_type, _target): cpu.is_enabled = false, CONNECT_ONE_SHOT)
	await model.submit_move(rook, bishop.coordinate)
	for _frame in range(8): await get_tree().process_frame
	_expect(not model.has_pending_reaction() and model.is_settled(), "matching CPU resolves a live-core Raise Dead choice through the existing API")
	cpu.queue_free(); model.queue_free(); await get_tree().process_frame

	var white_necro := NecromancerKing.new("white", Vector2i(7, 4)); white_necro.set_cooldown(0); white_necro.initial_cooldown_turn_pending = false
	model = _model([white_necro, ClassicKing.new("black", Vector2i(0, 4)), Pawn.new("white", Vector2i(5, 0))])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_active_ability(white_necro, Vector2i(6, 3)), "live core accepts Summon Bone Pawn")
	_expect(model.board[6][3] is BonePawn and white_necro.cooldown_reset_pending and model.current_turn == "black", "active summon projects its piece, cooldown, and turn")
	model.queue_free(); await get_tree().process_frame


func _test_minotaur_live_authority() -> void:
	var minotaur := MinotaurKing.new("white", Vector2i(4, 3)); minotaur.set_cooldown(0); minotaur.initial_cooldown_turn_pending = false
	var model := _model([minotaur, ClassicKing.new("black", Vector2i(0, 7))])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Minotaur position activates pure authority")
	_expect(await model.submit_active_ability(minotaur, Vector2i(4, 0)), "live core accepts wall Charge")
	_expect(model.board[4][0] == minotaur and minotaur.stunned and minotaur.stun_timer == 2 and minotaur.cooldown_reset_pending, "wall Charge projects movement, stun, and cooldown")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "wall Charge projection matches authoritative state")
	model.queue_free(); await get_tree().process_frame
	var rook := Rook.new("white", Vector2i(4, 0))
	var victim := Bishop.new("white", Vector2i(3, 3))
	var defender := MinotaurKing.new("black", Vector2i(4, 4))
	model = _model([ClassicKing.new("white", Vector2i(7, 7)), rook, victim, defender])
	var reactions := {"queued": 0, "finished": 0}
	model.reaction_queued.connect(func(_piece, action_type, _event, _sequence):
		if action_type == "retaliating_rage": reactions.queued += 1)
	model.reaction_finished.connect(func(_piece, action_type, _event, _sequence, _resolved):
		if action_type == "retaliating_rage": reactions.finished += 1)
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_move(rook, defender.coordinate), "live core settles an automatic Rage")
	_expect(defender.current_hp == 3 and model.find_piece_by_id(victim.piece_id) == null and reactions == {"queued": 1, "finished": 1}, "Rage projects damage, destruction, and reaction lifecycle")
	_expect(model.is_settled() and model.get_live_authority_diagnostics().projection_mismatches == 0, "automatic Rage leaves a settled matching projection")
	model.queue_free(); await get_tree().process_frame

	rook = Rook.new("white", Vector2i(4, 0))
	victim = Bishop.new("white", Vector2i(3, 3))
	defender = MinotaurKing.new("black", Vector2i(4, 4))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7))
	model = _model([ClassicKing.new("white", Vector2i(7, 7)), rook, victim, defender, necromancer])
	var mixed_finished := {"rage": 0, "raise": 0}
	model.reaction_finished.connect(func(_piece, action_type, _event, _sequence, _resolved):
		if action_type == "retaliating_rage": mixed_finished.rage += 1
		elif action_type == "raise_dead": mixed_finished.raise += 1)
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_move(rook, defender.coordinate) and model.has_pending_reaction(), "live Rage resolves before exposing its resulting Raise Dead choice")
	var target: Vector2i = model.get_pending_reaction().targets[0]
	_expect(await model.submit_reaction_selection(target), "mixed live reaction chain accepts Raise Dead after Rage")
	_expect(model.board[target.x][target.y] is BonePawn and model.is_settled() and model.get_live_authority_diagnostics().projection_mismatches == 0, "mixed Rage and Raise Dead projection settles identically")
	_expect(mixed_finished == {"rage": 1, "raise": 1}, "mixed live reaction lifecycle reports each automatic and selected reaction exactly once")
	model.queue_free(); await get_tree().process_frame


func _test_quarterly_live_authority() -> void:
	var quarterly := QuarterlyInitiativeKing.new("white", Vector2i(7, 7)); quarterly.set_cooldown(0); quarterly.initial_cooldown_turn_pending = false
	var rook := Rook.new("white", Vector2i(5, 5))
	var model := _model([quarterly, rook, ClassicKing.new("black", Vector2i(0, 0))])
	var signals := {"choice": 0, "grant": 0, "damage": 0}
	model.movement_type_selection_requested.connect(func(_king, _target, _options):
		signals.choice += 1
		model.call_deferred("submit_movement_type_grant", &"bishop")
	)
	rook.movement_type_granted.connect(func(_type): signals.grant += 1)
	model.piece_damaged.connect(func(piece, _amount, _current, _maximum):
		if piece == quarterly: signals.damage += 1
	)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Quarterly position activates pure authority")
	_expect(await model.submit_active_ability(quarterly, rook.coordinate), "live core settles Stakeholder Pandering through the existing choice API")
	_expect(quarterly.current_hp == 3 and &"bishop" in rook.granted_movement_types and quarterly.cooldown_reset_pending, "paid grant projects HP, movement, and cooldown state")
	_expect(signals == {"choice": 1, "grant": 1, "damage": 1}, "Quarterly live authority emits each choice, grant, and damage signal once")
	_expect(Vector2i(0, 0) in model.get_legal_moves(rook), "granted Bishop movement is immediately authoritative")
	_expect(model.is_settled() and model.get_live_authority_diagnostics().projection_mismatches == 0, "Quarterly live projection settles identically")
	model.queue_free(); await get_tree().process_frame


func _test_cpu_execution() -> void:
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4)), Pawn.new("black", Vector2i(2, 1))])
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(ChessCpuPlayer.BrainKind.RYCK); cpu.set_random_seed(17)
	_expect(await cpu.step(), "existing CPU command path executes through live core authority")
	_expect(model.current_turn == "black" and int(model.get_live_authority_diagnostics().core_resolutions) > 0, "CPU action settles through the core bridge")
	cpu.queue_free(); model.queue_free(); await get_tree().process_frame


func _test_cpu_soak() -> void:
	var model := _model(_classic_armies())
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	var white := ChessCpuPlayer.new(); white.model = model; add_child(white)
	var black := ChessCpuPlayer.new(); black.model = model; add_child(black)
	white.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white"); white.set_brain(ChessCpuPlayer.BrainKind.RYCK); white.set_random_seed(1001)
	black.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black"); black.set_brain(ChessCpuPlayer.BrainKind.RYCK); black.set_random_seed(2002)
	var plies := 0
	for _index in range(24):
		if model.battle_over: break
		var cpu := white if model.current_turn == "white" else black
		if not await cpu.step(): break
		plies += 1
		if ChessPositionCodec.to_json(model.capture_position(), false) != ChessPositionCodec.to_json(model._capture_projected_position(), false): break
	_expect(plies >= 12, "fixed-seed core-authority CPU soak completes a useful action sequence")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0 and ChessPositionCodec.to_json(model.capture_position(), false) == ChessPositionCodec.to_json(model._capture_projected_position(), false), "CPU soak retains authoritative/projection parity after every settled action")
	white.queue_free(); black.queue_free(); model.queue_free(); await get_tree().process_frame


func _test_arakne_live_authority() -> void:
	var arakne := ArakneKing.new("white", Vector2i(4, 4)); arakne.set_cooldown(0); arakne.initial_cooldown_turn_pending = false
	var model := _model([arakne, ClassicKing.new("black", Vector2i(0, 7))])
	var movement_targets: Array[Vector2i] = []
	var skitter_steps := {"count": 0}
	model.piece_move_committed.connect(func(_piece, _from, target, _presentation): movement_targets.append(target))
	model.skitter_step_started.connect(func(_piece, _from, _to): skitter_steps.count += 1)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Arakne position activates pure authority")
	_expect(Vector2i(3, 6) not in model.get_legal_moves(arakne) and Vector2i(4, 5) in model.get_legal_moves(arakne), "live pure authority preserves staged Skitter selection")
	_expect(await model.submit_move_path(arakne, [Vector2i(4, 5), Vector2i(3, 6)]), "live pure authority accepts an exact Skitter path")
	_expect(movement_targets == [Vector2i(4, 5), Vector2i(3, 6)] and skitter_steps.count == 1 and model.board[3][6] == arakne, "live Skitter presents both landings and its authored second-step marker")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "Skitter projection matches authoritative state")
	model.queue_free(); await get_tree().process_frame

	arakne = ArakneKing.new("white", Vector2i(4, 4)); arakne.set_cooldown(0); arakne.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(4, 5)); target.max_hp = 2; target.current_hp = 2
	model = _model([arakne, ClassicKing.new("black", Vector2i(0, 7)), target])
	var presentation := {"committed": 0, "damaged": 0, "scheduled": 0}
	model.targeted_ability_committed.connect(func(_context): presentation.committed += 1)
	model.piece_damaged.connect(func(piece, _amount, _current, _maximum):
		if piece == target: presentation.damaged += 1
	)
	arakne.cooldown_scheduled.connect(func(_king): presentation.scheduled += 1)
	model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	_expect(await model.submit_active_ability(arakne, target.coordinate), "live pure authority accepts Spike Burst")
	_expect(target.current_hp == 1 and arakne.cooldown_reset_pending and model.current_turn == "black", "live Spike Burst projects damage, scheduled cooldown, and turn completion")
	_expect(presentation == {"committed": 1, "damaged": 1, "scheduled": 1}, "Spike Burst preserves existing presentation and cooldown signals exactly once")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "Spike Burst projection matches authoritative state")
	model.queue_free(); await get_tree().process_frame


func _classic_armies() -> Array:
	var result: Array = []
	for color in ["black", "white"]:
		var row := 0 if color == "black" else 7
		var pawn_row := 1 if color == "black" else 6
		result.append_array([
			Rook.new(color, Vector2i(row, 0)), Knight.new(color, Vector2i(row, 1)), Bishop.new(color, Vector2i(row, 2)), Queen.new(color, Vector2i(row, 3)),
			ClassicKing.new(color, Vector2i(row, 4)), Bishop.new(color, Vector2i(row, 5)), Knight.new(color, Vector2i(row, 6)), Rook.new(color, Vector2i(row, 7)),
		])
		for column in range(8): result.append(Pawn.new(color, Vector2i(pawn_row, column)))
	return result


func _model(pieces: Array, turn := "white") -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = turn
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
