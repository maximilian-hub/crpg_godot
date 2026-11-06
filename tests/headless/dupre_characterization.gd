extends Node

const DuprePolicy = preload("res://scripts/ai/dupre_move_policy.gd")
const TacticalMap = preload("res://scripts/ai/dupre_tactical_map.gd")
const ExchangeAnalyzer = preload("res://scripts/ai/dupre_exchange_analyzer.gd")
const PositionHistory = preload("res://scripts/ai/dupre_position_history.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_opening_development_policy()
	_test_useful_rook_activity_policy()
	_test_immediate_reversal_policy()
	await _test_discovered_king_attack_policy()
	await _test_uncovered_free_piece_policy()
	await _test_capture_unprotected_checking_queen()
	await _test_favorable_checked_queen_exchange()
	_test_durable_target_projection()
	_test_incremental_projection_matches_rebuild()
	_test_tactical_map_revision_invalidation()
	await _test_hanging_valuable_piece()
	await _test_poisoned_capture()
	await _test_forcing_screen_cache_reuse()
	await _test_quiescence_capture_extension()
	await _test_quiescence_stops_when_quiet()
	await _test_quiescence_timeout_is_incomplete()
	await _test_immediate_victory()
	await _test_arakne_ability_victory()
	await _test_arakne_skitter_path_identity()
	await _test_minotaur_charge_support()
	await _test_minotaur_charge_defense()
	await _test_minotaur_rage_collateral()
	await _test_rhetorician_compel_support()
	await _test_rhetorician_rng_snapshot_consistency()
	_test_necromancer_policy_support()
	_test_arakne_ability_threat_horizon()
	_test_ability_effect_contract()
	_test_ability_effect_interpretation()
	_test_timeout_fallback_risk_evidence()
	await _test_wraith_strategic_summon_candidates()
	await _test_survivable_king_counterattack()
	_test_position_history_signatures()
	await _test_settled_position_history_lifecycle()
	_test_necromancer_removable_summon_policy()
	_test_necromancer_does_not_trade_queen_for_pawn()
	await _test_active_bone_pawn_threatens_cannon_queen()
	await _test_material_obligation_candidates()
	await _test_king_attack_timeout_fallback()
	await _test_game3_imminent_spike_burst_obligation()
	await _test_game3_king_damage_outranks_summon()
	_test_necromancer_reaction_policy()
	await _test_necromancer_simulation_settles_reaction()
	await _test_quarterly_simulation_secondary_choice()
	_test_cannon_policy_and_hazard_support()
	_test_brain_specific_king_support()
	await _test_cooperative_policy_score_identity()
	if failures.is_empty():
		print("DUPRE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _test_opening_development_policy() -> void:
	var model := _new_empty_model()
	var white_king := ClassicKing.new("white", Vector2i(7, 7))
	var black_king := ClassicKing.new("black", Vector2i(0, 7))
	var knight := Knight.new("white", Vector2i(7, 1))
	var rook := Rook.new("white", Vector2i(7, 4))
	for piece in [white_king, black_king, knight, rook]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var knight_development: ChessPrimaryAction
	var rook_shuffle: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == knight and action.target.x != 7: knight_development = action
		if action.piece == rook and action.target.x == 7: rook_shuffle = action
	_expect(knight_development != null and rook_shuffle != null and policy.score(knight_development) > policy.score(rook_shuffle), "purpose policy ranks useful opening development over a back-rank rook shuffle")
	_cleanup(cpu, model)


func _test_useful_rook_activity_policy() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(7, 0))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), rook]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var active: ChessPrimaryAction
	var shuffle: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece != rook: continue
		if action.target.x != 7 and active == null: active = action
		if action.target.x == 7 and shuffle == null: shuffle = action
	_expect(active != null and shuffle != null and policy.score(active) > policy.score(shuffle), "purpose policy prefers taking an open file to sliding a rook along its back rank")
	_cleanup(cpu, model)


func _test_immediate_reversal_policy() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(5, 0))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), rook]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var prior := {"piece_id": rook.piece_id, "from": Vector2i(7, 0), "to": Vector2i(5, 0)}
	var policy := DuprePolicy.new(cpu, prior)
	var reversal: ChessPrimaryAction
	var continuation: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece != rook: continue
		if action.target == Vector2i(7, 0): reversal = action
		if action.target == Vector2i(4, 0): continuation = action
	_expect(reversal != null and continuation != null and policy.score(continuation) > policy.score(reversal), "purpose policy penalizes immediately undoing Dupre's previous quiet move")
	_cleanup(cpu, model)


func _test_discovered_king_attack_policy() -> void:
	var model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(7, 4))
	king.current_hp = 1
	var knight := Knight.new("white", Vector2i(5, 2))
	var pawn := Pawn.new("white", Vector2i(6, 0))
	var bishop := Bishop.new("black", Vector2i(4, 1))
	for piece in [king, knight, pawn, bishop, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var exposing_move: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == knight and action.target == Vector2i(4, 4):
			exposing_move = action
			break
	_expect(exposing_move != null and policy.creates_new_king_threat(exposing_move), "purpose policy detects a knight move that uncovers an immediate bishop attack on its King")
	_expect(exposing_move != null and policy.score(exposing_move) < -9000.0, "newly exposing the King receives a catastrophic policy penalty")
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate != knight.coordinate, "ordinary Dupre avoids the discovered lethal attack when a safe move exists")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_uncovered_free_piece_policy() -> void:
	var model := _new_empty_model()
	var knight := Knight.new("white", Vector2i(3, 2))
	var queen := Queen.new("white", Vector2i(4, 3))
	var pawn := Pawn.new("white", Vector2i(6, 0))
	var bishop := Bishop.new("black", Vector2i(2, 1))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), knight, queen, pawn, bishop, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var exposing_move: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == knight and action.target == Vector2i(4, 4):
			exposing_move = action
			break
	_expect(exposing_move != null and policy.newly_exposed_undefended_value(exposing_move) == 9.0, "purpose policy detects a move that uncovers an undefended Queen")
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate != knight.coordinate, "ordinary Dupre avoids uncovering a free major piece when safe alternatives exist")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_capture_unprotected_checking_queen() -> void:
	var model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(7, 4))
	king.current_hp = 1
	var knight := Knight.new("white", Vector2i(4, 3))
	var checking_queen := Queen.new("black", Vector2i(3, 1))
	for piece in [king, knight, checking_queen, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate == knight.coordinate and thought.target == checking_queen.coordinate, "Dupre captures an unprotected checking Queen instead of merely moving its King")
	_expect(thought != null and int(thought.search_profile.mandatory_candidate_count) > 0, "capture of a checking piece is included as a mandatory tactical candidate")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_favorable_checked_queen_exchange() -> void:
	var model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(7, 4))
	king.current_hp = 1
	var knight := Knight.new("white", Vector2i(4, 3))
	var checking_queen := Queen.new("black", Vector2i(3, 1))
	var defending_pawn := Pawn.new("black", Vector2i(2, 0))
	for piece in [king, knight, checking_queen, defending_pawn, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var capture: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == knight and action.target == checking_queen.coordinate: capture = action
	_expect(capture != null and policy.capture_material_swing(capture) == 6.0, "tactical map recognizes a defended Queen-for-Knight capture as a favorable exchange")
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate == knight.coordinate and thought.target == checking_queen.coordinate, "Dupre chooses the favorable exchange while answering check")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_durable_target_projection() -> void:
	var model := _new_empty_model()
	var knight := Knight.new("white", Vector2i(4, 3))
	var durable_queen := Queen.new("black", Vector2i(3, 1))
	durable_queen.max_hp = 2
	durable_queen.current_hp = 2
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), knight, durable_queen, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var attack: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == knight and action.target == durable_queen.coordinate: attack = action
	var before := ChessPositionCodec.to_json(model.capture_position(), false)
	var projected := policy.projected_map(attack)
	var exchange: Dictionary = policy.exchange_result(attack)
	_expect(attack != null and projected.occupancy.get(knight.coordinate) == knight and projected.occupancy.get(durable_queen.coordinate) == durable_queen, "nonlethal attacks on durable pieces do not incorrectly move the attacker in tactical projections")
	_expect(attack != null and policy.capture_material_swing(attack) == 0.0, "nonlethal damage is not mislabeled as a material capture")
	_expect(float(exchange.delta) > 0.0 and int(exchange.confidence) == ExchangeAnalyzer.Confidence.MEDIUM, "exchange analysis values nonlethal HP damage with explicitly reduced confidence")
	_expect(ChessPositionCodec.to_json(model.capture_position(), false) == before, "static exchange analysis does not mutate the live model")
	_cleanup(cpu, model)


func _test_incremental_projection_matches_rebuild() -> void:
	var model := _new_empty_model()
	var knight := Knight.new("white", Vector2i(5, 2))
	var bishop := Bishop.new("black", Vector2i(4, 1))
	for piece in [ClassicKing.new("white", Vector2i(7, 4)), knight, bishop, Queen.new("white", Vector2i(6, 3)), ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var move: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == knight and action.target == Vector2i(4, 4): move = action
	var incremental := policy.projected_map(move)
	var rebuilt := policy.tactical_map.rebuild_projection(cpu._project_board_after(move))
	_expect(move != null and incremental.equivalent_to(rebuilt), "incremental tactical projection matches a complete rebuild across an opened bishop ray")
	_cleanup(cpu, model)


func _test_tactical_map_revision_invalidation() -> void:
	var model := _new_empty_model()
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.brain._ensure_tactical_map()
	var original_map = cpu.brain._tactical_map
	var original_revision: int = original_map.revision
	var pawn := Pawn.new("white", Vector2i(6, 0))
	model.add_piece(pawn, pawn.coordinate)
	# Test fixtures add pieces directly; live settled actions and position loads
	# advance this authoritative revision themselves.
	model.position_revision += 1
	cpu.brain._ensure_tactical_map()
	_expect(cpu.brain._tactical_map != original_map and cpu.brain._tactical_map.revision == model.position_revision and model.position_revision != original_revision, "tactical map is discarded and rebuilt when the authoritative position revision changes")
	_cleanup(cpu, model)


func _test_hanging_valuable_piece() -> void:
	var model := _new_empty_model()
	var queen := Queen.new("white", Vector2i(4, 4))
	var attacker := Rook.new("black", Vector2i(4, 0))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), queen, attacker]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate == queen.coordinate, "Dupre responds with the hanging Queen when it has reasonable escapes or a capture")
	_expect(thought != null and not thought.search_profile.unverified_selection, "hanging-piece response is tactically verified")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_poisoned_capture() -> void:
	var model := _new_empty_model()
	var queen := Queen.new("white", Vector2i(4, 4))
	var bait := Pawn.new("black", Vector2i(4, 3))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), queen, bait, Rook.new("black", Vector2i(4, 0))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(thought != null and not (thought.piece_coordinate == queen.coordinate and thought.target == bait.coordinate), "Dupre rejects a policy-attractive pawn capture that loses its Queen on the reply")
	_expect(thought != null and thought.search_profile.selected_status == &"verified" and not thought.search_profile.unverified_selection, "poisoned-capture decision reports completed tactical verification")
	var brain = cpu.brain
	brain.max_reply_leaves = 1
	var fallback = await cpu.think()
	_expect(fallback != null and fallback.search_profile.selected_status == &"breadth_fallback" and fallback.search_profile.unverified_selection and fallback.search_profile.evaluated_reply_count == 1 and fallback.search_profile.incomplete_root_candidates > 0, "Dupre excludes a partially verified candidate and explicitly reports an unverified breadth fallback")
	_expect(fallback != null and int(fallback.search_profile.prepared_root_candidates) == int(fallback.search_profile.policy_candidate_count), "Dupre prepares every selected root before spending its bounded reply budget")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_forcing_screen_cache_reuse() -> void:
	var model := _new_empty_model()
	var queen := Queen.new("white", Vector2i(4, 4))
	var bait := Pawn.new("black", Vector2i(4, 3))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), queen, bait, Rook.new("black", Vector2i(4, 0))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(thought != null and int(thought.search_profile.screened_reply_count) > 0, "Dupre screens forcing opponent replies before exhaustive completion")
	_expect(thought != null and int(thought.search_profile.reused_screened_reply_count) > 0, "exhaustive completion reuses replies already evaluated during forcing screening")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_quiescence_capture_extension() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 4))
	var queen := Queen.new("black", Vector2i(4, 3))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), rook, queen]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain._begin_profile(0)
	brain._begin_book_profile()
	brain.quiescence_enabled = false
	var static_score: float = await brain._evaluate_model(model)
	brain.quiescence_enabled = true
	var extended_score: float = await brain._evaluate_model(model)
	_expect(extended_score > static_score and int(brain.last_profile.get("quiescence_node_count", 0)) > 0, "one-ply quiescence values an available forcing capture beyond the static leaf")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_quiescence_stops_when_quiet() -> void:
	var model := _new_empty_model()
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 0)), Pawn.new("white", Vector2i(6, 0)), Pawn.new("black", Vector2i(1, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain._begin_profile(0)
	brain._begin_book_profile()
	await brain._evaluate_model(model)
	_expect(int(brain.last_profile.get("quiescence_node_count", 0)) == 0, "quiescence does not extend a tactically quiet position")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_quiescence_timeout_is_incomplete() -> void:
	var model := _new_empty_model()
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4)), Queen.new("black", Vector2i(4, 3))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain._begin_profile(0)
	brain._begin_book_profile()
	brain.max_reply_leaves = 0
	await brain._evaluate_model(model)
	_expect(not brain._last_evaluation_complete and int(brain.last_profile.quiescence_incomplete_count) == 1, "a budget cutoff during quiescence marks the evaluation incomplete instead of returning an exact leaf")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_immediate_victory() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 4))
	var enemy_king := ClassicKing.new("black", Vector2i(4, 0))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), enemy_king, rook]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate == rook.coordinate and thought.target == enemy_king.coordinate, "Dupre preserves an immediate ordinary-piece victory outside the policy candidate cap")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_arakne_ability_victory() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var enemy_king := ClassicKing.new("black", Vector2i(3, 3))
	arakne.attack_power = 0
	arakne.set_cooldown(0)
	for piece in [arakne, enemy_king]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	var active_action: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.target == enemy_king.coordinate:
			active_action = action
	var policy := DuprePolicy.new(cpu)
	_expect(active_action != null and policy.score(active_action) >= 10000.0, "Dupre's policy recognizes lethal Spike Burst as a mandatory win")
	_expect(thought != null and thought.target == enemy_king.coordinate, "Dupre chooses an immediate Arakne victory when both Spike Burst and capture win")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_arakne_skitter_path_identity() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	arakne.set_cooldown(1)
	for piece in [arakne, ClassicKing.new("black", Vector2i(0, 0))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var skitter_actions: Array[ChessPrimaryAction] = []
	for action in model.get_legal_primary_actions("white"):
		if action.kind == ChessPrimaryAction.Kind.MOVE and action.path.size() == 2:
			skitter_actions.append(action)
	var plan: ChessAiPlan = await cpu.brain.choose_plan(skitter_actions)
	var chosen_path: Array[Vector2i] = []
	if plan != null:
		chosen_path.assign(plan.action.path)
	var thought := ChessAiThought.new()
	if plan != null:
		thought.model_revision = model.position_revision
		thought.color = "white"
		thought.action_kind = plan.action.kind
		thought.piece_coordinate = arakne.coordinate
		thought.piece_type_id = arakne.get_position_type_id()
		thought.target = plan.action.target
		thought.path.assign(plan.action.path)
		cpu.last_thought = thought
	var landings: Array[Vector2i] = []
	model.piece_landed.connect(func(piece, _from, to, _gate):
		if piece == arakne: landings.append(to))
	var executed := await cpu.execute_thought()
	_expect(plan != null and chosen_path.size() == 2, "Dupre retains a complete path-aware Skitter action")
	_expect(executed and landings == chosen_path, "Dupre executes the exact Skitter route it tactically verified")
	_cleanup(cpu, model)


func _test_minotaur_charge_support() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var enemy_king := ClassicKing.new("black", Vector2i(4, 4))
	enemy_king.max_hp = 4
	enemy_king.current_hp = 2
	minotaur.set_cooldown(0)
	for piece in [minotaur, enemy_king]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(DupreAiBrain.unsupported_king_ids(model).is_empty(), "Dupre capability registry accepts a Minotaur matchup")
	_expect(thought != null and thought.action_kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and thought.target == enemy_king.coordinate, "Dupre selects an immediately lethal Minotaur Charge")
	_expect(thought != null and thought.search_profile.selected_candidate_reason == &"immediate_win", "lethal Charge is retained outside the ordinary candidate cap")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_minotaur_charge_defense() -> void:
	var model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(4, 4))
	var blocker := Rook.new("white", Vector2i(6, 2))
	var enemy_minotaur := MinotaurKing.new("black", Vector2i(4, 0))
	enemy_minotaur.set_cooldown(0)
	for piece in [king, blocker, enemy_minotaur]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var current_threats := cpu._king_threat_count(king, king.coordinate, cpu._current_board_state())
	var thought = await cpu.think()
	var chosen: ChessPrimaryAction
	if thought != null:
		for action in model.get_legal_primary_actions("white"):
			if action.piece.coordinate == thought.piece_coordinate and action.target == thought.target and action.path == thought.path:
				chosen = action
				break
	_expect(current_threats > 0, "Dupre's king-safety projection recognizes an enemy Minotaur Charge lane")
	_expect(chosen != null and cpu._projected_king_threat_count(chosen) == 0, "Dupre answers a ready Charge with an authoritative safe defense")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_minotaur_rage_collateral() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var exposed_queen := Queen.new("white", Vector2i(3, 4))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	minotaur.set_cooldown(1)
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), rook, exposed_queen, minotaur]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var thought = await cpu.think()
	_expect(thought != null and not (thought.piece_coordinate == rook.coordinate and thought.target == minotaur.coordinate), "authoritative verification rejects a nonlethal Minotaur attack whose Rage loses the Queen")
	_expect(thought != null and thought.search_profile.selected_status == &"verified", "Rage collateral decision is based on completed tactical verification")
	_expect(thought != null and thought.candidates.any(func(candidate: Dictionary): return bool(candidate.get("ability_requires_verification", false))), "Rage candidate diagnostics explain that its outcome required authoritative simulation")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_rhetorician_compel_support() -> void:
	var model := _new_empty_model()
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4))
	var compelled := Pawn.new("black", Vector2i(2, 2))
	var victim := Queen.new("black", Vector2i(3, 3))
	rhetorician.set_cooldown(0)
	for piece in [rhetorician, compelled, victim, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var actions := model.get_legal_primary_actions("white")
	var policy := DuprePolicy.new(cpu)
	var compel: ChessPrimaryAction
	for action in actions:
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.target == compelled.coordinate:
			compel = action
			break
	var thought = await cpu.think()
	_expect(compel != null and policy.score(compel) >= 8.0, "Rhetorician policy values the piece actually removed by a compelled capture")
	var chose_compel: bool = thought != null and thought.action_kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and thought.target == compelled.coordinate
	var chose_direct_capture: bool = thought != null and thought.action_kind == ChessPrimaryAction.Kind.MOVE and thought.target == victim.coordinate
	_expect(chose_compel or chose_direct_capture, "Dupre chooses a materially decisive compel or the equivalent immediate capture")
	_expect(thought != null and int(thought.search_profile.mandatory_candidate_count) > 0, "forcing Rhetorician abilities are protected from the ordinary candidate limit")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_rhetorician_rng_snapshot_consistency() -> void:
	var source := _new_empty_model()
	var rhetorician := RhetoricianKing.new("white", Vector2i(7, 7))
	for piece in [rhetorician, Rook.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(1, 0)), ClassicKing.new("black", Vector2i(0, 7))]: source.add_piece(piece, piece.coordinate)
	var captured := source.capture_position()
	captured.lunacy_by_color["white"] = 5
	captured.socratic_turns_by_color["white"] = 2
	captured.current_turn = "black"
	var seeded_rng := RandomNumberGenerator.new(); seeded_rng.seed = 731
	captured.random_states[&"lunacy"] = seeded_rng.state
	_expect(source.load_position(captured), "Rhetorician RNG fixture loads through the authoritative position boundary")
	captured = source.capture_position()
	var encoded := ChessPositionCodec.to_json(captured, false)
	var decoded: Dictionary = ChessPositionCodec.from_json(encoded)
	var first := _new_empty_model()
	var second := _new_empty_model()
	var loaded_first := first.load_position(decoded.position)
	var loaded_second := second.load_position(decoded.position.copy())
	var before_live := source.capture_position().random_states.duplicate(true)
	if loaded_first and loaded_second:
		var first_action: ChessPrimaryAction = first.get_legal_primary_actions("black")[0]
		var second_action: ChessPrimaryAction = second.get_legal_primary_actions("black")[0]
		await first.submit_move(first_action.piece, first_action.target)
		await second.submit_move(second_action.piece, second_action.target)
	var first_position := first.capture_position()
	var second_position := second.capture_position()
	_expect(loaded_first and loaded_second and first_position.random_states == second_position.random_states and ChessPositionCodec.to_json(first_position, false) == ChessPositionCodec.to_json(second_position, false), "identical Rhetorician snapshots reproduce the same Socratic outcome")
	_expect(source.capture_position().random_states == before_live, "speculative Socratic resolution does not advance live-model RNG")
	first.free(); second.free(); source.free()
	await get_tree().process_frame


func _test_necromancer_policy_support() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("white", Vector2i(7, 7))
	necromancer.set_cooldown(0)
	for piece in [necromancer, Pawn.new("white", Vector2i(6, 0)), ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var layer = ChessKingAiRegistry.layer_for(&"necromancer_king")
	var doomed_score := float(layer.placement_score(model, necromancer, Vector2i(0, 1), "white"))
	var safe_score := float(layer.placement_score(model, necromancer, Vector2i(5, 3), "white"))
	var summon: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
			summon = action
			break
	var policy := DuprePolicy.new(cpu)
	_expect(DupreAiBrain.unsupported_king_ids(model).is_empty(), "Dupre accepts Necromancer as an enhanced supported King")
	_expect(safe_score > doomed_score, "Necromancer policy rejects a Bone Pawn placement that dies on the enemy back rank")
	_expect(summon != null, "ready Necromancer exposes a summon action to Dupre")
	if summon != null:
		var summon_score := policy.score(summon)
		var projected_threats := policy.direct_king_threat_count_after(summon)
		var before_position := ChessPositionCodec.to_json(model.capture_position(), false)
		var effects: Array[DupreAbilityEffect] = layer.describe_ability_action(model, summon, TacticalMap.from_model(model).occupancy)
		_expect(is_finite(summon_score) and projected_threats >= 0, "Necromancer summon projections keep placeholder occupancy out of live-piece identity comparisons")
		_expect(effects.any(func(effect): return effect.kind == DupreAbilityEffect.Kind.SUMMON), "Necromancer summon is exposed through the shared ability-effect contract")
		_expect(ChessPositionCodec.to_json(model.capture_position(), false) == before_position, "ability-effect description never mutates the authoritative live position")
	_cleanup(cpu, model)


func _test_arakne_ability_threat_horizon() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(3, 4))
	var knight := Knight.new("black", Vector2i(2, 5))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 4))
	for piece in [arakne, knight, necromancer]: model.add_piece(piece, piece.coordinate)
	arakne.current_cooldown = 1
	arakne.cooldown_reset_pending = false
	arakne.initial_cooldown_turn_pending = false
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var policy := DuprePolicy.new(cpu)
	var current: Dictionary = policy.ability_threat(knight, 0)
	var next_turn: Dictionary = policy.ability_threat(knight, 1)
	_expect(current.is_empty() and bool(next_turn.get("lethal", false)) and int(next_turn.get("ready_in_turn_entries", -1)) == 1, "Arakne threat projection distinguishes unavailable-now Spike Burst from next-turn readiness")
	arakne.cooldown_reset_pending = true
	arakne.current_cooldown = 0
	var scheduled := DuprePolicy.new(cpu).ability_threat(knight, 1)
	_expect(scheduled.is_empty(), "a newly spent Spike Burst is not incorrectly considered ready on Arakne's next turn entry")
	model.active_ability_cooldowns_disabled = true
	var disabled_cooldowns := DuprePolicy.new(cpu).ability_threat(knight, 0)
	_expect(bool(disabled_cooldowns.get("lethal", false)), "disabled cooldowns make Spike Burst immediately visible to tactical policy")
	_cleanup(cpu, model)


func _test_ability_effect_contract() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var charge_target := Queen.new("black", Vector2i(4, 4))
	minotaur.set_cooldown(0)
	for piece in [minotaur, charge_target, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var minotaur_layer = ChessKingAiRegistry.layer_for(&"minotaur_king")
	var occupancy := DupreTacticalMap.from_model(model).occupancy
	var charge_effects: Array[DupreAbilityEffect] = minotaur_layer.collect_ability_threats(model, minotaur, occupancy, 0)
	_expect(charge_effects.size() == 1 and charge_effects[0].ability_id == &"charge" and charge_effects[0].damage == 2 and charge_effects[0].target_piece_id == charge_target.piece_id, "ability-effect contract describes an authoritative Minotaur Charge lane")
	model.free()

	model = _new_empty_model()
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4))
	var compelled := Pawn.new("black", Vector2i(2, 2))
	var victim := Rook.new("black", Vector2i(3, 3))
	rhetorician.set_cooldown(0)
	for piece in [rhetorician, compelled, victim, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var compel_effects: Array[DupreAbilityEffect] = ChessKingAiRegistry.layer_for(&"rhetorician_king").collect_ability_threats(model, rhetorician, DupreTacticalMap.from_model(model).occupancy, 0)
	_expect(compel_effects.size() == 1 and compel_effects[0].kind == DupreAbilityEffect.Kind.FORCED_MOVEMENT and compel_effects[0].destination == victim.coordinate and compel_effects[0].metadata.get("captured_piece_id", "") == victim.piece_id, "ability-effect contract records Compel's forced destination and captured occupant")
	model.free()

	model = _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(3, 4))
	var knight := Knight.new("black", Vector2i(2, 5))
	for piece in [arakne, knight, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	arakne.set_cooldown(0)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var policy := DuprePolicy.new(cpu)
	policy.ability_threat(knight, 0)
	policy.ability_threat(knight, 0)
	var metrics := policy.projection_metrics()
	_expect(int(metrics.ability_effect_collections) == 1 and int(metrics.ability_effect_cache_hits) == 1, "ability effects are collected once and reused within a Dupre decision")
	_cleanup(cpu, model)

	for archer_id in [&"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge"]:
		_expect(ChessKingAiRegistry.supports_dupre(archer_id) and ChessKingAiRegistry.dupre_support_level(archer_id) == ChessKingAiLayer.SupportLevel.GENERIC, "experimental Archer variant receives rules-compatible generic Dupre support: %s" % archer_id)


func _test_ability_effect_interpretation() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var queen := Queen.new("white", Vector2i(3, 4))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), rook, queen, minotaur]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var rage_attack: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == rook and action.target == minotaur.coordinate:
			rage_attack = action
			break
	var rage_assessment: Dictionary = policy.action_effect_assessment(rage_attack) if rage_attack != null else {}
	_expect(bool(rage_assessment.get("requires_verification", false)) and bool(rage_assessment.get("high_impact", false)) and float(rage_assessment.get("certain_value", -1.0)) == 0.0, "Minotaur Rage requests authoritative verification without receiving speculative tactical credit")
	var quiet_action: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action != rage_attack:
			quiet_action = action
			break
	var fallback_records: Array[Dictionary] = [
		{"action": rage_attack, "policy": 100.0, "candidate_reason": &"ability_verification", "screen_status": DupreAiBrain.ScreenStatus.INCOMPLETE, "ability_assessment": rage_assessment},
		{"action": quiet_action, "policy": 0.0, "candidate_reason": &"policy", "screen_status": DupreAiBrain.ScreenStatus.INCOMPLETE, "ability_assessment": {}},
	]
	var fallback = cpu.brain._best_screened_fallback(fallback_records)
	_expect(fallback.get("action") == quiet_action, "timeout fallback prefers a settled ordinary move over an optimistic simulation-required effect")
	_cleanup(cpu, model)

	model = _new_empty_model()
	var necromancer := NecromancerKing.new("white", Vector2i(7, 7))
	necromancer.set_cooldown(0)
	for piece in [necromancer, Pawn.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(0, 7)), ClassicKing.new("black", Vector2i(0, 0))]: model.add_piece(piece, piece.coordinate)
	cpu = _add_dupre(model)
	policy = DuprePolicy.new(cpu)
	var blocking_summon: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.target == Vector2i(6, 7):
			blocking_summon = action
			break
	var block_assessment: Dictionary = policy.action_effect_assessment(blocking_summon) if blocking_summon != null else {}
	_expect(bool(block_assessment.get("high_impact", false)) and bool(block_assessment.get("forcing", false)) and float(block_assessment.get("certain_value", 0.0)) >= 25.0, "a Bone Pawn that actually blocks a King attacker becomes a certain defensive ability effect")
	_cleanup(cpu, model)

	model = _new_empty_model()
	var white_king := ClassicKing.new("white", Vector2i(2, 0))
	var blocker := Pawn.new("white", Vector2i(2, 2))
	var rhetorician := RhetoricianKing.new("black", Vector2i(4, 4))
	rhetorician.set_cooldown(0)
	for piece in [white_king, blocker, rhetorician, Rook.new("black", Vector2i(2, 7))]: model.add_piece(piece, piece.coordinate)
	cpu = _add_dupre(model)
	policy = DuprePolicy.new(cpu)
	var obligations := policy.ability_obligations(0)
	_expect(obligations.any(func(obligation: Dictionary): return obligation.piece == white_king and bool(obligation.effect.metadata.get("king_exposure", false))), "Compel recognizes moving a blocker away as a certain King-exposure emergency")
	_cleanup(cpu, model)


func _test_timeout_fallback_risk_evidence() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(6, 0))
	for piece in [ClassicKing.new("white", Vector2i(7, 4)), rook, Pawn.new("white", Vector2i(6, 2)), ClassicKing.new("black", Vector2i(0, 4))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var actions := model.get_legal_primary_actions("white")
	var dangerous: ChessPrimaryAction = actions[0]
	var safe: ChessPrimaryAction = actions[1]
	var records: Array[Dictionary] = [
		{"action": dangerous, "policy": 100.0, "adjusted_policy": 100.0, "candidate_reason": &"policy", "screen_status": DupreAiBrain.ScreenStatus.INCOMPLETE, "ability_assessment": {}, "known_loss": 40.0, "known_terminal_loss": false, "forcing_coverage_complete": true, "forcing_replies_evaluated": 1, "candidate_index": 0},
		{"action": safe, "policy": 0.0, "adjusted_policy": 0.0, "candidate_reason": &"policy", "screen_status": DupreAiBrain.ScreenStatus.INCOMPLETE, "ability_assessment": {}, "known_loss": 0.0, "known_terminal_loss": false, "forcing_coverage_complete": true, "forcing_replies_evaluated": 1, "candidate_index": 1},
	]
	_expect(cpu.brain._best_screened_fallback(records).action == safe, "timeout fallback rejects a known severe reply instead of trusting the higher optimistic policy score")
	records[0].known_loss = 0.0
	records[0].candidate_reason = &"king_attack"
	records[0].forcing_coverage_complete = false
	_expect(cpu.brain._best_screened_fallback(records).action == safe, "completed forcing coverage outranks a partially screened attack when their risk evidence differs")
	records[1].forcing_coverage_complete = false
	_expect(cpu.brain._best_screened_fallback(records).action == dangerous, "an unrefuted direct King attack retains mandatory priority among equally uncertain candidates")
	_cleanup(cpu, model)


func _test_wraith_strategic_summon_candidates() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var wraith := WraithKing.new("black", Vector2i(0, 4))
	var enemy_king := ClassicKing.new("white", Vector2i(7, 4))
	for piece in [wraith, enemy_king, Queen.new("white", Vector2i(7, 3)), Rook.new("white", Vector2i(7, 0)), Bishop.new("white", Vector2i(7, 2)), Knight.new("white", Vector2i(7, 1))]:
		model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain._begin_profile(model.get_legal_primary_actions("black").size())
	brain._begin_book_profile()
	brain._ensure_tactical_map()
	_expect(brain._has_mandatory_override(model.get_legal_primary_actions("black")) and brain.last_profile.opening_ability_override_reason == &"wraith_king_pressure", "early Wraith King pressure explicitly overrides ordinary opening-book play")
	var policy := DuprePolicy.new(cpu, {}, brain._tactical_map)
	var ranked: Array[Dictionary] = []
	var index := 0
	for action in model.get_legal_primary_actions("black"):
		ranked.append({
			"action": action,
			"policy": policy.score(action),
			"index": index,
			"ability_assessment": policy.action_effect_assessment(action) if policy.action_may_have_effects(action) else {},
		})
		index += 1
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.policy) > float(b.policy))
	var candidates := await brain._select_candidates(ranked, policy)
	var king_summon: Dictionary = {}
	for candidate in candidates:
		if candidate.action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and candidate.action.target == enemy_king.coordinate:
			king_summon = candidate
			break
	_expect(not king_summon.is_empty() and king_summon.candidate_reason == &"strategic_ability", "Wraith retains early enemy-King pressure as an explicit strategic candidate")
	var retained_wraith_summons := candidates.filter(func(candidate: Dictionary): return StringName(candidate.get("ability_assessment", {}).get("candidate_group", &"")) == &"wraith_summon").size()
	_expect(retained_wraith_summons <= 3, "Wraith caps delayed summon roots while preserving a diverse bounded set")
	var quiet: Dictionary = candidates.filter(func(candidate: Dictionary): return candidate.action.kind == ChessPrimaryAction.Kind.MOVE)[0]
	var fallback_records: Array[Dictionary] = [
		{"action": king_summon.action, "policy": king_summon.policy, "adjusted_policy": king_summon.policy, "candidate_reason": &"strategic_ability", "candidate_index": 0, "screen_status": DupreAiBrain.ScreenStatus.READY, "phase": &"prepared", "ability_assessment": king_summon.ability_assessment, "known_loss": 0.0, "known_terminal_loss": false, "forcing_coverage_complete": true, "forcing_replies_evaluated": 0, "forcing_replies_total": 0},
		{"action": quiet.action, "policy": quiet.policy, "adjusted_policy": quiet.policy, "candidate_reason": &"policy", "candidate_index": 1, "screen_status": DupreAiBrain.ScreenStatus.READY, "phase": &"prepared", "ability_assessment": {}, "known_loss": 0.0, "known_terminal_loss": false, "forcing_coverage_complete": true, "forcing_replies_evaluated": 0, "forcing_replies_total": 0},
	]
	_expect(brain._best_screened_fallback(fallback_records).action == king_summon.action, "a prepared clear Wraith pressure action may beat a quiet move without being mislabeled exact")
	fallback_records[0].forcing_coverage_complete = false
	_expect(brain._best_screened_fallback(fallback_records).action == quiet.action, "incomplete Wraith verification remains ineligible beside a settled move")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_survivable_king_counterattack() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var wraith := WraithKing.new("black", Vector2i(3, 2))
	wraith.current_hp = 4
	var queen := Queen.new("white", Vector2i(4, 3))
	for piece in [wraith, queen, ClassicKing.new("white", Vector2i(7, 0)), Rook.new("white", Vector2i(4, 7)), Bishop.new("white", Vector2i(7, 6)), Pawn.new("black", Vector2i(1, 0))]:
		model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.max_reply_leaves = 0
	var capture: ChessPrimaryAction
	for action in model.get_legal_primary_actions("black"):
		if action.piece == wraith and action.target == queen.coordinate:
			capture = action
			break
	var policy := DuprePolicy.new(cpu)
	_expect(capture != null and policy.is_survivable_king_counterattack(capture), "a multi-HP King recognizes that it can take a checking Queen and survive one immediate hit")
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate == wraith.coordinate and thought.target == queen.coordinate, "timeout fallback prioritizes the survivable King counter-capture over irrelevant defense")
	_expect(thought != null and thought.search_profile.selected_candidate_reason == &"king_counterattack" and int(thought.search_profile.king_safety_candidates_retained) <= 6, "the King counter-capture has explicit priority while generic safety candidates remain bounded")
	wraith.current_hp = 1
	policy = DuprePolicy.new(cpu)
	_expect(not policy.is_survivable_king_counterattack(capture), "the same counter-capture receives no survivability waiver at one HP")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_position_history_signatures() -> void:
	var model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(7, 4))
	for piece in [king, ClassicKing.new("black", Vector2i(0, 4)), Rook.new("white", Vector2i(6, 0))]: model.add_piece(piece, piece.coordinate)
	var first := model.capture_position()
	var cosmetically_later := first.copy()
	cosmetically_later.global_turn_number += 9
	cosmetically_later.random_states[&"test"] = 999
	var history := PositionHistory.new(2)
	history.observe_position(first)
	_expect(history.count_position(cosmetically_later) == 1, "repetition signatures ignore absolute turn and RNG bookkeeping")
	var changed := first.copy()
	changed.pieces[0].current_cooldown += 1
	_expect(history.count_position(changed) == 0, "repetition signatures retain legality-relevant cooldown state")
	history.observe_position(cosmetically_later)
	history.observe_position(changed)
	_expect(history.count_position(first) == 1 and int(history.snapshot().size) == 2, "bounded repetition history evicts only the oldest observation")
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain._begin_profile(1)
	brain._begin_book_profile()
	brain.position_history.observe_position(first)
	var quiet: ChessPrimaryAction = model.get_legal_primary_actions("white").filter(func(action: ChessPrimaryAction): return action.kind == ChessPrimaryAction.Kind.MOVE and model.board[action.target.x][action.target.y] == null)[0]
	var quiet_record := {"action": quiet, "policy": 5.0, "adjusted_policy": 5.0, "candidate_reason": &"policy"}
	brain._apply_repetition_evidence(quiet_record, first)
	var forcing_record := {"action": quiet, "policy": 5.0, "adjusted_policy": 5.0, "candidate_reason": &"king_attack"}
	brain._apply_repetition_evidence(forcing_record, first)
	_expect(float(quiet_record.repetition_penalty) > 0.0 and float(forcing_record.repetition_penalty) == 0.0, "repetition discourages quiet cycles without suppressing mandatory tactical actions")
	_cleanup(cpu, model)


func _test_settled_position_history_lifecycle() -> void:
	var model := _new_empty_model()
	for piece in [ClassicKing.new("white", Vector2i(7, 4)), Rook.new("white", Vector2i(6, 0)), ClassicKing.new("black", Vector2i(0, 4))]:
		model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.candidate_limit = 2
	brain.max_reply_leaves = 1
	brain.think_budget_msec = 100
	var thought = await cpu.think()
	var executed := thought != null and await cpu.execute_thought()
	_expect(executed and int(brain.position_history.snapshot().size) == 1, "Dupre records one settled authoritative position only after its completed action")
	brain.reset_session(&"test")
	_expect(int(brain.position_history.snapshot().size) == 0, "Dupre clears repetition history with the rest of its match session")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_necromancer_removable_summon_policy() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var arakne := ArakneKing.new("white", Vector2i(3, 4))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 4))
	arakne.set_cooldown(0)
	necromancer.set_cooldown(0)
	for piece in [arakne, necromancer, Bishop.new("black", Vector2i(0, 5)), Knight.new("black", Vector2i(2, 2))]: model.add_piece(piece, piece.coordinate)
	var layer = ChessKingAiRegistry.layer_for(&"necromancer_king")
	var score := float(layer.placement_score(model, necromancer, Vector2i(2, 3), "black"))
	var summon: ChessPrimaryAction
	for action in model.get_legal_primary_actions("black"):
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.target == Vector2i(2, 3):
			summon = action
			break
	_expect(summon != null and score < 2.0, "Necromancer policy discounts the game3 d6 summon that ready Spike Burst can erase")
	_expect(summon != null and not layer.action_is_forcing(model, summon, "black"), "an immediately removable Bone Pawn is not forcing merely because it attacks the enemy King")
	model.active_ability_cooldowns_disabled = false
	arakne.current_cooldown = 1
	arakne.cooldown_reset_pending = false
	arakne.initial_cooldown_turn_pending = false
	var recharging_score := float(layer.placement_score(model, necromancer, Vector2i(2, 3), "black"))
	_expect(recharging_score > score, "Necromancer summon policy retains value while Spike Burst is unavailable")
	model.free()


func _test_necromancer_reaction_policy() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("white", Vector2i(7, 7))
	for piece in [necromancer, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var targets := [Vector2i(0, 1), Vector2i(5, 3), Vector2i(5, 4)]
	var first = cpu.brain.choose_reaction_target(model, necromancer, "raise_dead", Vector2i(5, 3), targets)
	var second = cpu.brain.choose_reaction_target(model, necromancer, "raise_dead", Vector2i(5, 3), targets)
	_expect(first == second, "Dupre reaction placement is deterministic for an identical position")
	_expect(first != Vector2i(0, 1), "Dupre Raise Dead avoids a Bone Pawn placement that dies immediately")
	_cleanup(cpu, model)


func _test_necromancer_does_not_trade_queen_for_pawn() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("white", Vector2i(7, 7))
	var queen := Queen.new("white", Vector2i(4, 4))
	var attacking_pawn := Pawn.new("black", Vector2i(3, 3))
	necromancer.set_cooldown(0)
	for piece in [necromancer, queen, attacking_pawn, ClassicKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var policy := DuprePolicy.new(cpu)
	var capture: ChessPrimaryAction
	var defensive_summon: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.piece == queen and action.target == attacking_pawn.coordinate:
			capture = action
		elif action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.target == Vector2i(5, 3):
			defensive_summon = action
	var layer = ChessKingAiRegistry.layer_for(&"necromancer_king")
	var current_risk: Dictionary = policy.material_risk(queen)
	var summon_risk: Dictionary = policy.material_risk_after(defensive_summon, queen) if defensive_summon != null else {}
	var capture_exchange: Dictionary = policy.exchange_result(capture) if capture != null else {}
	_expect(capture != null and defensive_summon != null, "queen-capture and superficially defensive summon are both legal in the Necromancer exchange fixture")
	_expect(defensive_summon != null and not layer.action_is_forcing(model, defensive_summon, "white"), "merely defending a still-capturable Queen does not make a Necromancer summon forcing")
	_expect(capture != null and defensive_summon != null and policy.score(capture) > policy.score(defensive_summon), "Dupre prefers taking the vulnerable pawn over sacrificing its Queen for a Bone Pawn recapture")
	_expect(float(current_risk.loss) >= 8.0 and float(summon_risk.get("loss", 0.0)) >= 8.0, "exchange analysis recognizes that adding a defender does not erase a profitable pawn-for-Queen exchange")
	_expect(not capture_exchange.is_empty() and capture_exchange.sequence.size() <= 6, "bounded exchange analysis reports a finite capture sequence")
	_cleanup(cpu, model)


func _test_active_bone_pawn_threatens_cannon_queen() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var cannon := CannonKing.new("black", Vector2i(0, 4))
	var queen := Queen.new("black", Vector2i(4, 7))
	var necromancer := NecromancerKing.new("white", Vector2i(7, 4))
	var active_summon := BonePawn.new("white", Vector2i(5, 6))
	var tempting_pawn := Pawn.new("white", Vector2i(4, 5))
	for piece in [cannon, queen, necromancer, active_summon, tempting_pawn]:
		model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.think_budget_msec = 500
	var policy := DuprePolicy.new(cpu)
	var poisoned_capture: ChessPrimaryAction
	var safe_queen_move: ChessPrimaryAction
	for action in model.get_legal_primary_actions("black"):
		if action.piece != queen:
			continue
		var risk := policy.material_risk_after(action, queen)
		if action.target == tempting_pawn.coordinate:
			poisoned_capture = action
		elif float(risk.get("loss", 0.0)) < 8.0 and safe_queen_move == null:
			safe_queen_move = action
	var current_risk := policy.material_risk(queen)
	var poisoned_risk := policy.material_risk_after(poisoned_capture, queen) if poisoned_capture != null else {}
	_expect(float(current_risk.get("loss", 0.0)) >= 8.0, "a ready active-summoned Bone Pawn registers as an immediate threat to the Cannon Queen")
	_expect(poisoned_capture != null and float(poisoned_risk.get("loss", 0.0)) >= 8.0 and safe_queen_move != null, "the cannon_wasted_queen capture remains poisoned while safe Queen moves exist")
	var thought = await cpu.think()
	var selected_action: ChessPrimaryAction
	if thought != null:
		for action in model.get_legal_primary_actions("black"):
			if action.kind == thought.action_kind and action.piece.coordinate == thought.piece_coordinate and action.target == thought.target and action.path == thought.path:
				selected_action = action
				break
	var selected_risk := policy.material_risk_after(selected_action, queen) if selected_action != null else {}
	_expect(selected_action != null and selected_action.piece == queen and float(selected_risk.get("loss", 0.0)) < 8.0, "Dupre answers the active Bone Pawn threat by saving the Cannon Queen")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_material_obligation_candidates() -> void:
	var model := _new_empty_model()
	var queen := Queen.new("white", Vector2i(4, 4))
	var pawn := Pawn.new("black", Vector2i(3, 3))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), queen, pawn, ClassicKing.new("black", Vector2i(0, 6))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain.think_budget_msec = 1500
	brain._begin_profile(model.get_legal_primary_actions("white").size())
	brain._begin_book_profile()
	brain._ensure_tactical_map()
	var policy := DuprePolicy.new(cpu, {}, brain._tactical_map)
	var ranked: Array[Dictionary] = []
	var index := 0
	for action in model.get_legal_primary_actions("white"):
		ranked.append({"action": action, "policy": policy.score(action), "index": index})
		index += 1
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.policy) > float(b.policy))
	var candidates: Array[Dictionary] = await brain._select_candidates(ranked, policy)
	var capture_reason: StringName = &""
	for candidate in candidates:
		if candidate.action.piece == queen and candidate.action.target == pawn.coordinate:
			capture_reason = candidate.candidate_reason
			break
	_expect(brain.last_profile.danger_class == &"critical" and int(brain.last_profile.material_obligation_count) == 1, "a profitable pawn attack on the Queen classifies the root as a critical material obligation")
	_expect(capture_reason == &"material_obligation", "capturing the pawn is retained ahead of ordinary policy candidates as an obligation response")
	var thought = await cpu.think()
	_expect(thought != null and thought.piece_coordinate == queen.coordinate and thought.target == pawn.coordinate, "Dupre answers the critical Queen threat by taking the vulnerable pawn")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_king_attack_timeout_fallback() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var arakne := ArakneKing.new("white", Vector2i(3, 5))
	var bishop := Bishop.new("black", Vector2i(0, 2))
	var knight := Knight.new("black", Vector2i(2, 5))
	for piece in [arakne, NecromancerKing.new("black", Vector2i(0, 4)), bishop, knight]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.max_reply_leaves = 0
	var thought = await cpu.think()
	var saw_king_attack := false
	var saw_material_response := false
	for diagnostic in thought.candidates if thought != null else []:
		if diagnostic.reason == "king_attack": saw_king_attack = true
		if diagnostic.reason == "material_obligation": saw_material_response = true
	_expect(thought != null and thought.piece_coordinate == bishop.coordinate and thought.target == arakne.coordinate, "a direct nonlethal King hit outranks a knight rescue when Dupre must use an unverified fallback")
	_expect(saw_king_attack and saw_material_response and int(thought.search_profile.prepared_root_candidates) == 0, "timeout diagnostics retain both unprepared King-attack and material-response candidates")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_game3_imminent_spike_burst_obligation() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var arakne := ArakneKing.new("white", Vector2i(3, 4))
	var knight := Knight.new("black", Vector2i(2, 5))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 4))
	arakne.current_cooldown = 1
	arakne.cooldown_reset_pending = false
	arakne.initial_cooldown_turn_pending = false
	for piece in [arakne, knight, necromancer]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.max_reply_leaves = 0
	brain._begin_profile(model.get_legal_primary_actions("black").size())
	brain._begin_book_profile()
	brain._ensure_tactical_map()
	var policy := DuprePolicy.new(cpu, {}, brain._tactical_map)
	var ranked: Array[Dictionary] = []
	var index := 0
	for action in model.get_legal_primary_actions("black"):
		ranked.append({"action": action, "policy": policy.score(action), "index": index})
		index += 1
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.policy) > float(b.policy))
	var candidates := await brain._select_candidates(ranked, policy)
	var saw_escape := false
	for candidate in candidates:
		if candidate.get("candidate_reason", &"") == &"material_obligation" and policy.ability_threat_after(candidate.action, knight, 1).is_empty():
			saw_escape = true
			break
	_expect(brain._has_mandatory_override(model.get_legal_primary_actions("black")), "an f6 Knight facing next-turn Spike Burst overrides opening-book play")
	_expect(int(brain.last_profile.ability_obligation_count) == 1 and int(brain.last_profile.ability_threat_next_turn_count) == 1 and saw_escape, "the imminent Spike Burst becomes a material obligation with retained saving responses")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_game3_king_damage_outranks_summon() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var arakne := ArakneKing.new("white", Vector2i(3, 4))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 4))
	var knight := Knight.new("black", Vector2i(2, 2))
	var bone := BonePawn.new("black", Vector2i(2, 5))
	arakne.current_cooldown = 1
	arakne.cooldown_reset_pending = false
	arakne.initial_cooldown_turn_pending = false
	necromancer.set_cooldown(0)
	for piece in [arakne, necromancer, knight, bone, Bishop.new("black", Vector2i(0, 5))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.max_reply_leaves = 0
	var thought = await cpu.think()
	_expect(thought != null and thought.target == arakne.coordinate and thought.action_kind == ChessPrimaryAction.Kind.MOVE, "game3 timeout fallback takes immediate Arakne HP instead of summoning another future threat")
	_expect(thought != null and thought.search_profile.selected_candidate_reason == &"king_attack" and thought.search_profile.unverified_selection, "game3 fallback reports immediate King damage as the reason for its unverified selection")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_necromancer_simulation_settles_reaction() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var victim := Bishop.new("black", Vector2i(4, 4))
	for piece in [ClassicKing.new("white", Vector2i(7, 7)), rook, victim, NecromancerKing.new("black", Vector2i(0, 7))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain._begin_profile(1)
	brain._begin_book_profile()
	var simulation = await brain._make_model(model.capture_position())
	var descriptor := {"kind": ChessPrimaryAction.Kind.MOVE, "piece_id": rook.piece_id, "target": victim.coordinate, "path": [victim.coordinate]}
	var execution := await brain._execute_dupre_descriptor(simulation, descriptor)
	_expect(execution.status == DupreAiBrain.ExecutionStatus.COMPLETED and simulation.is_settled(), "Dupre simulation drains Raise Dead before evaluating the branch")
	_expect(int(execution.policy_reactions) == 1 and int(brain.last_profile.opponent_policy_reactions_resolved) == 1, "opponent Raise Dead is recorded as a policy-resolved reaction")
	brain._free_model(simulation)
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_quarterly_simulation_secondary_choice() -> void:
	var model := _new_empty_model()
	model.global_turn_number = 4
	var quarterly := QuarterlyInitiativeKing.new("white", Vector2i(7, 7))
	var rook := Rook.new("white", Vector2i(5, 5))
	quarterly.set_cooldown(0)
	for piece in [quarterly, rook, ClassicKing.new("black", Vector2i(0, 0))]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var brain: DupreAiBrain = cpu.brain
	brain._begin_profile(1)
	brain._begin_book_profile()
	var action: ChessPrimaryAction
	for candidate in model.get_legal_primary_actions("white"):
		if candidate.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and candidate.target == rook.coordinate:
			action = candidate
			break
	var simulation := await brain._make_model(model.capture_position())
	var execution := await brain._execute_dupre_descriptor(simulation, brain._describe_action(action)) if simulation != null and action != null else {"status": DupreAiBrain.ExecutionStatus.INVALID}
	var simulated_rook: ModelPiece = simulation.find_piece_by_id(rook.piece_id) if simulation != null else null
	_expect(execution.status == DupreAiBrain.ExecutionStatus.COMPLETED and simulated_rook != null and &"bishop" in simulated_rook.granted_movement_types, "Dupre simulations settle Quarterly's secondary selection with the intended movement grant")
	_expect(cpu.brain.choose_movement_type_grant(model, quarterly, rook, [&"pawn", &"knight", &"bishop", &"rook"]) == &"bishop", "Dupre's live Quarterly selection matches its deterministic simulated selection")
	if simulation != null: brain._free_model(simulation)
	_cleanup(cpu, model)
	await get_tree().process_frame


func _test_cannon_policy_and_hazard_support() -> void:
	var model := _new_empty_model()
	var cannon := CannonKing.new("white", Vector2i(7, 7))
	cannon.set_cooldown(0)
	var enemy_king := ClassicKing.new("black", Vector2i(2, 2))
	var enemy_rook := Rook.new("black", Vector2i(2, 3))
	var friendly_queen := Queen.new("white", Vector2i(5, 5))
	for piece in [cannon, enemy_king, enemy_rook, friendly_queen]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var layer = ChessKingAiRegistry.layer_for(&"cannon_king")
	var valuable_shot: ChessPrimaryAction
	var friendly_shot: ChessPrimaryAction
	for action in model.get_legal_primary_actions("white"):
		if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY: continue
		if action.target == Vector2i(2, 2): valuable_shot = action
		if action.target == Vector2i(5, 5): friendly_shot = action
	_expect(valuable_shot != null and friendly_shot != null and layer.action_policy_bonus(model, valuable_shot, "white") > layer.action_policy_bonus(model, friendly_shot, "white"), "Cannon policy prefers delayed King-and-Rook pressure over friendly-fire exposure")
	var effects: Array[DupreAbilityEffect] = layer.describe_ability_action(model, valuable_shot, DupreTacticalMap.from_model(model).occupancy)
	_expect(effects.size() == 1 and effects[0].kind == DupreAbilityEffect.Kind.AREA_HAZARD and effects[0].certainty == DupreAbilityEffect.Certainty.CONDITIONAL, "Arc Mortar is described as a conditional scheduled area hazard, not guaranteed damage")
	var mortar := ChessAutonomousEntityState.new()
	mortar.entity_id = "test_mortar"
	mortar.type_id = &"arc_mortar"
	mortar.owner_color = "black"
	mortar.coordinate = Vector2i(5, 5)
	mortar.custom_state["landing_turn"] = model.global_turn_number + 1
	model.autonomous_entities.append(mortar)
	var policy := DuprePolicy.new(cpu)
	var obligations := policy.scheduled_hazard_obligations(1)
	_expect(obligations.any(func(obligation): return obligation.piece == friendly_queen), "an imminent mortar retains evacuation of an exposed major piece as a tactical obligation")
	_cleanup(cpu, model)


func _test_brain_specific_king_support() -> void:
	var model := _new_empty_model()
	for piece in [MinotaurKing.new("white", Vector2i(7, 7)), RhetoricianKing.new("black", Vector2i(0, 0))]: model.add_piece(piece, piece.coordinate)
	_expect(DupreAiBrain.unsupported_king_ids(model).is_empty(), "Dupre supports enhanced Minotaur and Rhetorician layers on either side")
	_expect(LeMayAiBrain.unsupported_king_ids(model).size() == 2, "enabling enhanced Dupre layers does not silently broaden LeMay support")
	model.free()
	model = _new_empty_model()
	for piece in [QuarterlyInitiativeKing.new("white", Vector2i(7, 7)), CannonKing.new("black", Vector2i(0, 0))]: model.add_piece(piece, piece.coordinate)
	_expect(DupreAiBrain.unsupported_king_ids(model).is_empty(), "Dupre supports Quarterly Initiative and Cannon Kings on either side")
	_expect(LeMayAiBrain.unsupported_king_ids(model).size() == 2, "Quarterly and Cannon support remains scoped to Dupre")
	model.free()


func _test_cooperative_policy_score_identity() -> void:
	var model := _new_empty_model()
	for piece in [
		ClassicKing.new("white", Vector2i(7, 4)), Queen.new("white", Vector2i(6, 3)), Rook.new("white", Vector2i(7, 0)), Pawn.new("white", Vector2i(5, 2)),
		ClassicKing.new("black", Vector2i(0, 4)), Queen.new("black", Vector2i(1, 3)), Rook.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(2, 5)),
	]: model.add_piece(piece, piece.coordinate)
	var cpu := _add_dupre(model)
	var actions := model.get_legal_primary_actions("white")
	var synchronous := DuprePolicy.new(cpu)
	var cooperative := DuprePolicy.new(cpu)
	for action in actions.slice(0, mini(8, actions.size())):
		var expected := synchronous.score(action)
		await cooperative.prepare_action_cooperatively(action, Callable(self, "_cooperate_for_policy_test"))
		_expect(is_equal_approx(expected, cooperative.score(action)), "cooperative policy preparation preserves the synchronous score for %s" % action.target)
	var metrics: Dictionary = cooperative.projection_metrics()
	_expect(int(metrics.get("endgame", {}).get("cache_hits", 0)) > 0, "cooperative scoring reuses prepared endgame assessments")
	_cleanup(cpu, model)
	await get_tree().process_frame


func _cooperate_for_policy_test() -> int:
	await get_tree().process_frame
	return 0


func _add_dupre(model: ChessBoardModel) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	cpu.set_random_seed(31)
	return cpu


func _new_empty_model() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null: model.unregister_piece(piece)
	model.board.clear()
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.last_move = {}
	model.current_turn = "white"
	model.battle_over = false
	model.defeated_king_colors.clear()
	return model


func _cleanup(cpu: ChessCpuPlayer, model: ChessBoardModel) -> void:
	cpu.queue_free()
	model.free()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
