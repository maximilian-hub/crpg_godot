extends Node

const DuprePolicy = preload("res://scripts/ai/dupre_move_policy.gd")
const TacticalMap = preload("res://scripts/ai/dupre_tactical_map.gd")

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
	await _test_immediate_victory()
	await _test_arakne_ability_victory()
	await _test_arakne_skitter_path_identity()
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
	var projected := policy.projected_map(attack)
	_expect(attack != null and projected.occupancy.get(knight.coordinate) == knight and projected.occupancy.get(durable_queen.coordinate) == durable_queen, "nonlethal attacks on durable pieces do not incorrectly move the attacker in tactical projections")
	_expect(attack != null and policy.capture_material_swing(attack) == 0.0, "nonlethal damage is not mislabeled as a material capture")
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
	_expect(fallback != null and fallback.search_profile.selected_status == &"policy_fallback" and fallback.search_profile.unverified_selection and fallback.search_profile.evaluated_reply_count == 1 and fallback.search_profile.incomplete_root_candidates > 0, "Dupre excludes a partially verified candidate and explicitly reports an unverified policy fallback")
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
