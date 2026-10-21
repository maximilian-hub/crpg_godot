extends Node

const ArcherKing := preload("res://scripts/pieces/archer_king.gd")

var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	await _run()
	if failures.is_empty():
		print("HEADLESS MODEL CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	printerr("HEADLESS MODEL CHARACTERIZATION: FAIL")
	get_tree().quit(1)

func _run() -> void:
	_test_completion_gate_contract()
	_test_stun_timer_saturates_at_zero()
	await _test_initialization_and_move()
	await _test_active_ability_cooldown_counts_full_turns()
	_test_active_ability_cooldown_override()
	_test_line_of_sight_map()
	_test_catalog_direct_attack_parity()
	await _test_forced_pass_after_action()
	await _test_turn_entry_recovery_prevents_pass()
	await _test_nonlethal_combat()
	await _test_lethal_damage_event_order()
	await _test_arakne_staged_controller_selection()
	await _test_special_moves()
	await _test_minotaur_charge_landing()
	await _test_headless_rage()
	_test_reaction_queued_boundary()
	await _test_rage_raise_dead_includes_death_square()
	await _test_terminal_rank_raise_dead_expires_bone_pawn()
	await _test_headless_reaction_priority()
	await _test_model_owned_raise_dead_choice()
	await _test_raise_dead_excludes_occupied_death_square()
	await _test_complete_battle_from_commands()
	await _test_wraith_king_lingering_malice()
	await _test_wraith_summon_autonomous_lifecycle()
	_test_wraith_state_round_trip()
	await _test_wraith_cpu_active_integration()
	await _test_rhetorician_rules_and_lunacy()
	await _test_cannon_king_arc_mortar()
	await _test_quarterly_initiative_king()
	await _test_archer_king()

func _test_line_of_sight_map() -> void:
	var model := _new_empty_model()
	var origin := Vector2i(4, 1)
	var open_map := model.get_visibility_map(origin)
	_expect(open_map.size() == 64 and is_equal_approx(float(open_map[origin]), 1.0), "unlimited line of sight includes every square on an unobstructed board")
	_expect(model.get_visibility_map(origin, 1.01).is_empty(), "visibility queries honor an explicit cutoff without changing the default")

	var blocker := Pawn.new("white", Vector2i(4, 3))
	model.add_piece(blocker, blocker.coordinate)
	var blocked_map := model.get_visibility_map(origin)
	_expect(blocker.coordinate in blocked_map, "an occupied destination remains visible")
	_expect(Vector2i(4, 7) not in blocked_map, "a piece obscures squares directly behind it")
	_expect(Vector2i(0, 7) in blocked_map, "piece occlusion does not hide unrelated far-side squares")

	blocker.color = "black"
	_expect(Vector2i(4, 7) not in model.get_visibility_map(origin), "friendly and enemy pieces block line of sight identically")
	_expect(model.get_visibility_map(Vector2i(-1, 0)).is_empty(), "an invalid line-of-sight origin returns an empty map")

	var corner_model := _new_empty_model()
	var corner_origin := Vector2i(4, 4)
	var adjacent_blocker := Pawn.new("white", Vector2i(3, 4))
	corner_model.add_piece(adjacent_blocker, adjacent_blocker.coordinate)
	var corner_map := corner_model.get_visibility_map(corner_origin, 0.5)
	_expect(Vector2i(3, 3) in corner_map and Vector2i(3, 5) in corner_map, "a cardinally adjacent blocker permits corner peeking into both adjacent diagonals")
	_expect(Vector2i(0, 0) in corner_map and Vector2i(1, 7) in corner_map, "corner peeking continues along both complete diagonals beside an adjacent blocker")
	_expect(Vector2i(2, 4) not in corner_map, "the same adjacent blocker still obscures squares directly behind it")
	var corridor_blocker := Pawn.new("black", Vector2i(2, 2))
	corner_model.add_piece(corridor_blocker, corridor_blocker.coordinate)
	corner_map = corner_model.get_visibility_map(corner_origin, 0.5)
	_expect(corridor_blocker.coordinate in corner_map and Vector2i(1, 1) not in corner_map, "a farther piece on the diagonal remains visible and closes the corner-peek corridor behind itself")

	var mirrored_model := _new_empty_model()
	var reflected_model := _new_empty_model()
	mirrored_model.add_piece(Pawn.new("white", Vector2i(3, 3)), Vector2i(3, 3))
	reflected_model.add_piece(Pawn.new("black", Vector2i(3, 4)), Vector2i(3, 4))
	var from_left := mirrored_model.get_visibility_map(Vector2i(3, 0))
	var from_right := reflected_model.get_visibility_map(Vector2i(3, 7))
	var symmetric := true
	for coordinate in from_left:
		var mirror := Vector2i(coordinate.x, 7 - coordinate.y)
		if not from_right.has(mirror) or not is_equal_approx(float(from_left[coordinate]), float(from_right[mirror])):
			symmetric = false
			break
	_expect(symmetric and from_left.size() == from_right.size(), "line-of-sight scores are symmetric across mirrored board positions")
	model.free()
	corner_model.free()
	mirrored_model.free()
	reflected_model.free()

func _test_catalog_direct_attack_parity() -> void:
	for type_id in ChessPieceCatalog.get_type_ids(true):
		var model := _new_empty_model()
		var origin := Vector2i(4, 4)
		var piece := ChessPieceCatalog.create_piece(type_id, "white", origin)
		model.add_piece(piece, origin)
		var matches := true
		for row_index in range(8):
			for column_index in range(8):
				var target := Vector2i(row_index, column_index)
				if target == origin:
					continue
				var enemy := Pawn.new("black", target)
				model.add_piece(enemy, target)
				var legal_capture := target in model.get_legal_moves(piece)
				var position := ChessAttackPosition.from_board(model.board)
				var shared_attack := piece.can_directly_attack_square(origin, target, position)
				if legal_capture != shared_attack:
					matches = false
				model.board[target.x][target.y] = null
				model.unregister_piece(enemy)
				enemy.free()
		_expect(matches, "%s live captures match its shared projected direct-attack contract" % type_id)
		model.free()

func _test_archer_king() -> void:
	_expect(ChessPieceCatalog.create_piece(&"archer_king", "white", Vector2i.ZERO) is ArcherKing, "the piece catalog constructs Archer King positions and palette selections")
	var attack_model := _new_empty_model()
	var archer := ArcherKing.new("white", Vector2i(4, 4))
	var adjacent_enemy := Pawn.new("black", Vector2i(5, 5))
	var ranged_enemy := Pawn.new("black", Vector2i(1, 4))
	ranged_enemy.max_hp = 2
	ranged_enemy.current_hp = 2
	attack_model.add_piece(archer, archer.coordinate)
	attack_model.add_piece(adjacent_enemy, adjacent_enemy.coordinate)
	attack_model.add_piece(ranged_enemy, ranged_enemy.coordinate)
	_expect(archer.max_hp == 2 and archer.current_cooldown == 4, "Archer King starts with two HP and Volley on a four-turn cooldown")
	_expect(adjacent_enemy.coordinate not in attack_model.get_legal_moves(archer), "Sharpshooter has no traditional adjacent attack")
	_expect(ranged_enemy.coordinate in attack_model.get_legal_moves(archer), "Sharpshooter attacks targets two to four squares away")
	_expect(await attack_model.submit_move(archer, ranged_enemy.coordinate), "Sharpshooter accepts its ranged attack")
	_expect(archer.coordinate == Vector2i(4, 4) and attack_model.board[4][4] == archer and attack_model.board[1][4] == ranged_enemy and ranged_enemy.current_hp == 1, "Sharpshooter deals one damage without moving the Archer King")
	attack_model.free()

	var los_model := _new_empty_model()
	var los_archer := ArcherKing.new("white", Vector2i(4, 4))
	var adjacent_blocker := Pawn.new("white", Vector2i(3, 4))
	var obscured_enemy := Pawn.new("black", Vector2i(1, 4))
	var diagonal_enemy := Pawn.new("black", Vector2i(1, 1))
	los_model.add_piece(los_archer, los_archer.coordinate)
	los_model.add_piece(adjacent_blocker, adjacent_blocker.coordinate)
	los_model.add_piece(obscured_enemy, obscured_enemy.coordinate)
	los_model.add_piece(diagonal_enemy, diagonal_enemy.coordinate)
	var los_attacks := los_model.get_legal_moves(los_archer)
	_expect(obscured_enemy.coordinate not in los_attacks, "Sharpshooter cannot attack an enemy obscured inside its two-to-four-square range")
	_expect(diagonal_enemy.coordinate in los_attacks, "Sharpshooter can attack along an open corner-peek diagonal inside its range")
	var los_position := ChessAttackPosition.from_board(los_model.board)
	_expect(not los_archer.can_directly_attack_square(Vector2i(7, 7), Vector2i(2, 7), los_position), "Sharpshooter projected threats stop beyond four squares")
	los_model.free()

	var volley_model := _new_empty_model()
	var volley_archer := ArcherKing.new("white", Vector2i(7, 7))
	volley_model.add_piece(volley_archer, volley_archer.coordinate)
	for row in range(0, 3):
		for column in range(8):
			var durable_target := ClassicKing.new("black", Vector2i(row, column))
			durable_target.max_hp = 2
			durable_target.current_hp = 2
			volley_model.add_piece(durable_target, durable_target.coordinate)
	volley_archer.set_cooldown(0)
	volley_model.set_archer_volley_random_seed(4404)
	var selected: Array[Vector2i] = []
	var destroyed := {"count": 0}
	volley_model.archer_volley_committed.connect(func(_king, targets, _gate): selected.assign(targets))
	volley_model.piece_destroyed.connect(func(piece):
		if piece.color == "black": destroyed.count += 1)
	_expect(await volley_model.submit_active_ability(volley_archer, volley_archer.coordinate), "Volley of Arrows is cast by selecting the Archer King")
	_expect(selected.size() == 6 and selected.all(func(coord): return coord.x >= 0 and coord.x <= 2), "Volley selects six unique squares between the enemy front and rear rows")
	_expect(destroyed.count == 0 and selected.all(func(coord): return volley_model.board[coord.x][coord.y].current_hp == 1), "Volley deals exactly one damage to every occupied selected square, including Kings")
	_expect(volley_archer.cooldown_reset_pending, "Volley schedules its four-turn cooldown")
	volley_model.free()

func _test_quarterly_initiative_king() -> void:
	var efficiency_model := _new_empty_model()
	var executive := QuarterlyInitiativeKing.new("white", Vector2i(4, 4))
	var redundant_pawn := Pawn.new("white", Vector2i(3, 4))
	var opposing_king := ClassicKing.new("black", Vector2i(0, 7))
	efficiency_model.add_piece(executive, executive.coordinate)
	efficiency_model.add_piece(redundant_pawn, redundant_pawn.coordinate)
	efficiency_model.add_piece(opposing_king, opposing_king.coordinate)
	_expect(redundant_pawn.coordinate in efficiency_model.get_legal_moves(executive), "Efficiency lets the Quarterly Initiative King target a friendly piece")
	_expect(await efficiency_model.submit_move(executive, redundant_pawn.coordinate), "Efficiency accepts a friendly capture as a normal move")
	_expect(efficiency_model.board[3][4] == executive and not efficiency_model.is_piece_active(redundant_pawn), "Efficiency removes the friendly piece and moves the King into its square")
	efficiency_model.free()

	var grant_model := _new_empty_model()
	var quarterly := QuarterlyInitiativeKing.new("white", Vector2i(7, 7))
	var recipient := Knight.new("white", Vector2i(4, 4))
	var enemy_king := ClassicKing.new("black", Vector2i(0, 7))
	grant_model.add_piece(quarterly, quarterly.coordinate)
	grant_model.add_piece(recipient, recipient.coordinate)
	grant_model.add_piece(enemy_king, enemy_king.coordinate)
	quarterly.set_cooldown(0)
	grant_model.movement_type_selection_requested.connect(func(_king, _target, _options): grant_model.call_deferred("submit_movement_type_grant", &"rook"))
	_expect(await grant_model.submit_active_ability(quarterly, recipient.coordinate), "Stakeholder Pandering completes after a movement-type choice")
	_expect(&"rook" in recipient.granted_movement_types and Vector2i(4, 0) in grant_model.get_legal_moves(recipient), "the recipient permanently gains Rook moves alongside its original movement")
	_expect(quarterly.current_hp == 3, "Performance Cycle damages the King outside a fourth global turn")
	var saved := grant_model.capture_position()
	_expect(saved.global_turn_number == 1 and &"rook" in saved.pieces.filter(func(state): return state.piece_id == recipient.piece_id)[0].granted_movement_types, "global turn and granted movement persist in position state")
	await get_tree().process_frame
	grant_model.free()

	var terminal_capture_cases := [
		{"name": "ordinary", "origin": Vector2i(1, 0), "target": Vector2i(0, 1), "grant": &""},
		{"name": "Rook-elevated", "origin": Vector2i(3, 0), "target": Vector2i(0, 0), "grant": &"rook"},
	]
	for capture_case in terminal_capture_cases:
		var terminal_model := _new_empty_model()
		var winning_pawn := Pawn.new("white", capture_case.origin)
		if capture_case.grant != &"":
			winning_pawn.grant_movement_type(capture_case.grant)
		var friendly_king := ClassicKing.new("white", Vector2i(7, 7))
		var defeated_king := ClassicKing.new("black", capture_case.target)
		terminal_model.add_piece(winning_pawn, winning_pawn.coordinate)
		terminal_model.add_piece(friendly_king, friendly_king.coordinate)
		terminal_model.add_piece(defeated_king, defeated_king.coordinate)
		var promotions := {"count": 0}
		terminal_model.piece_promotion_committed.connect(func(_old_piece, _new_piece, _gate): promotions.count += 1)
		_expect(await terminal_model.submit_move(winning_pawn, capture_case.target), capture_case.name + " Pawn can deliver a terminal-rank killing blow")
		_expect(terminal_model.battle_over and terminal_model.board[capture_case.target.x][capture_case.target.y] == winning_pawn, capture_case.name + " Pawn remains on the defeated King's square when battle ends")
		_expect(promotions.count == 0 and winning_pawn.type == "pawn", capture_case.name + " Pawn does not promote after defeating the King")
		terminal_model.free()

	var fourth_turn_model := _new_empty_model()
	var exempt_quarterly := QuarterlyInitiativeKing.new("white", Vector2i(7, 7))
	var exempt_recipient := Bishop.new("white", Vector2i(5, 5))
	var fourth_enemy_king := ClassicKing.new("black", Vector2i(0, 7))
	fourth_turn_model.add_piece(exempt_quarterly, exempt_quarterly.coordinate)
	fourth_turn_model.add_piece(exempt_recipient, exempt_recipient.coordinate)
	fourth_turn_model.add_piece(fourth_enemy_king, fourth_enemy_king.coordinate)
	fourth_turn_model.global_turn_number = 4
	exempt_quarterly.set_cooldown(0)
	fourth_turn_model.movement_type_selection_requested.connect(func(_king, _target, _options): fourth_turn_model.call_deferred("submit_movement_type_grant", &"knight"))
	await fourth_turn_model.submit_active_ability(exempt_quarterly, exempt_recipient.coordinate)
	_expect(exempt_quarterly.current_hp == 4 and fourth_turn_model.global_turn_number == 4, "Performance Cycle is free for White on global turn four")
	_expect(fourth_turn_model.current_turn == "black", "White completing an action hands play to Black")
	fourth_turn_model.switch_turn()
	_expect(fourth_turn_model.global_turn_number == 5 and fourth_turn_model.current_turn == "white", "White and Black share one global turn before the next round begins")
	await get_tree().process_frame
	fourth_turn_model.free()

func _test_cannon_king_arc_mortar() -> void:
	var model := _new_empty_model()
	var cannon := CannonKing.new("white", Vector2i(7, 7))
	var black_king := ClassicKing.new("black", Vector2i(0, 7))
	var target := Rook.new("black", Vector2i(3, 3))
	target.max_hp = 2
	target.current_hp = 2
	model.add_piece(cannon, cannon.coordinate)
	model.add_piece(black_king, black_king.coordinate)
	model.add_piece(target, target.coordinate)
	cannon.set_cooldown(0)
	_expect(cannon.max_hp == 5, "Cannon King starts with five HP")
	_expect(await model.submit_active_ability(cannon, Vector2i(3, 3)), "Arc Mortar accepts an in-range 2x2 area")
	var mortar: ChessAutonomousEntityState = model.autonomous_entities.filter(func(entity): return entity.type_id == &"arc_mortar")[0]
	_expect(target.current_hp == 2 and int(mortar.custom_state.get("landing_turn", 0)) == 4, "Arc Mortar schedules impact three shared rounds after firing")
	_expect(model.begin_action("black"), "opponent can act while Arc Mortar is pending")
	await model.continue_action_resolution()
	_expect(target.current_hp == 2 and mortar in model.autonomous_entities and model.global_turn_number == 2, "Arc Mortar remains pending at the start of the shooter's first later turn")
	_expect(cannon.current_cooldown == 4, "Arc Mortar keeps its four-turn cooldown when an enemy occupied the selected area")
	_expect(model.begin_action("white"), "the shooter's first later turn can complete under the warning")
	await model.continue_action_resolution()
	_expect(model.begin_action("black"), "the second intervening opposing turn can complete")
	await model.continue_action_resolution()
	_expect(target.current_hp == 2 and mortar in model.autonomous_entities and model.global_turn_number == 3, "Arc Mortar remains pending at the start of the shooter's second later turn")
	_expect(model.begin_action("white"), "the shooter's second later turn can complete under the warning")
	await model.continue_action_resolution()
	_expect(model.begin_action("black"), "the third intervening opposing turn can complete")
	await model.continue_action_resolution()
	_expect(target.current_hp == 1 and mortar not in model.autonomous_entities and model.global_turn_number == 4, "Arc Mortar damages its area at the beginning of the shooter's third later turn")
	model.free()

	var empty_model := _new_empty_model()
	var careful_cannon := CannonKing.new("white", Vector2i(7, 7))
	var other_king := ClassicKing.new("black", Vector2i(0, 7))
	empty_model.add_piece(careful_cannon, careful_cannon.coordinate)
	empty_model.add_piece(other_king, other_king.coordinate)
	careful_cannon.set_cooldown(0)
	await empty_model.submit_active_ability(careful_cannon, Vector2i(3, 3))
	_expect(empty_model.begin_action("black"), "opponent action advances an empty Arc Mortar shot")
	await empty_model.continue_action_resolution()
	_expect(careful_cannon.current_cooldown == 3, "Calculated Trajectory reduces an empty area's cooldown by one turn")
	_expect(empty_model.autonomous_entities.any(func(entity): return entity.type_id == &"arc_mortar"), "an empty-area Arc Mortar still waits until the third later turn")
	empty_model.free()

	var reaction_model := _new_empty_model()
	var reaction_cannon := CannonKing.new("white", Vector2i(7, 7))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7))
	var mortar_victim := Bishop.new("black", Vector2i(3, 3))
	reaction_model.add_piece(reaction_cannon, reaction_cannon.coordinate)
	reaction_model.add_piece(necromancer, necromancer.coordinate)
	reaction_model.add_piece(mortar_victim, mortar_victim.coordinate)
	reaction_cannon.set_cooldown(0)
	await reaction_model.submit_active_ability(reaction_cannon, Vector2i(3, 3))
	reaction_model.global_turn_number = 3
	_expect(reaction_model.begin_action("black"), "Necromancer side can complete the turn before the scheduled third-turn impact")
	await reaction_model.continue_action_resolution()
	_expect(reaction_model.has_pending_reaction() and reaction_model.action_in_progress, "mortar destruction opens Raise Dead inside a selectable turn-entry reaction context")
	var pending_raise_dead := reaction_model.get_pending_reaction()
	var raise_target: Vector2i = pending_raise_dead.get("targets", [Vector2i(-1, -1)])[0]
	_expect(await reaction_model.submit_reaction_selection(raise_target), "Raise Dead can select a target after an Arc Mortar destruction")
	_expect(reaction_model.board[raise_target.x][raise_target.y] is BonePawn and reaction_model.current_turn == "white" and not reaction_model.action_in_progress, "mortar-triggered Raise Dead resolves without skipping or hanging the entered turn")
	reaction_model.free()

func _test_rhetorician_rules_and_lunacy() -> void:
	var threat_model := _new_empty_model()
	var threatened_king := RhetoricianKing.new("white", Vector2i(4, 4))
	var threatening_rook := Rook.new("black", Vector2i(1, 4))
	var adjacent_threat := Rook.new("black", Vector2i(4, 3))
	threat_model.add_piece(threatened_king, threatened_king.coordinate)
	threat_model.add_piece(threatening_rook, threatening_rook.coordinate)
	threat_model.add_piece(adjacent_threat, adjacent_threat.coordinate)
	threat_model.current_turn = "black"
	threat_model.switch_turn()
	_expect(int(threat_model.lunacy_by_color["white"]) == 1, "a threatened Rhetorician gains Lunacy on authoritative turn entry")
	threat_model.unregister_piece(threatening_rook)
	threat_model.board[1][4] = null
	threat_model.lunacy_by_color["white"] = 4
	threat_model.current_turn = "black"
	threat_model.switch_turn()
	_expect(int(threat_model.socratic_turns_by_color["white"]) == 2, "an adjacent attacker blocked by the passive still triggers Socratic Lunacy")
	threat_model.free()

	var model := _new_empty_model()
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4))
	var adjacent_enemy := Rook.new("black", Vector2i(4, 3))
	var distant_enemy := Rook.new("black", Vector2i(1, 4))
	model.add_piece(rhetorician, rhetorician.coordinate)
	model.add_piece(adjacent_enemy, adjacent_enemy.coordinate)
	model.add_piece(distant_enemy, distant_enemy.coordinate)
	_expect(rhetorician.max_hp == 4, "Rhetorician King starts with four HP")
	_expect(rhetorician.coordinate not in model.get_legal_moves(adjacent_enemy), "adjacent enemies cannot attack the Rhetorician King")
	_expect(rhetorician.coordinate in model.get_legal_moves(distant_enemy), "non-adjacent enemies may attack the Rhetorician King")
	rhetorician.set_cooldown(0)
	var pulled := Pawn.new("black", Vector2i(2, 2))
	var occupant := Bishop.new("black", Vector2i(3, 3))
	model.add_piece(pulled, pulled.coordinate)
	model.add_piece(occupant, occupant.coordinate)
	_expect(await model.submit_active_ability(rhetorician, pulled.coordinate), "Can Logic Move Them targets an enemy two rows and columns away")
	_expect(model.board[3][3] == pulled and not model.is_piece_active(occupant), "compelled movement captures the destination occupant with normal capture resolution")
	model.free()

	var lunacy_model := _new_empty_model()
	var lunatic := RhetoricianKing.new("white", Vector2i(7, 7))
	var white_rook := Rook.new("white", Vector2i(6, 0))
	var black_rook := Rook.new("black", Vector2i(1, 0))
	lunacy_model.add_piece(lunatic, lunatic.coordinate)
	lunacy_model.add_piece(white_rook, white_rook.coordinate)
	lunacy_model.add_piece(black_rook, black_rook.coordinate)
	lunacy_model.add_lunacy("white", 5)
	lunacy_model.set_lunacy_random_seed(7)
	lunacy_model.current_turn = "black"
	_expect(lunacy_model.begin_action("black"), "opposing setup action begins before Socratic Lunacy")
	await lunacy_model.continue_action_resolution()
	_expect(lunacy_model.current_turn == "black" and int(lunacy_model.socratic_turns_by_color["white"]) == 1, "first Socratic turn makes one random move and returns control to the opponent")
	_expect(lunacy_model.begin_action("black"), "opponent can act between forced Socratic turns")
	await lunacy_model.continue_action_resolution()
	_expect(int(lunacy_model.socratic_turns_by_color["white"]) == 0 and int(lunacy_model.lunacy_by_color["white"]) == 0, "second Socratic turn ends the phase and resets Lunacy")
	lunacy_model.free()

func _test_wraith_king_lingering_malice() -> void:
	var model := _new_empty_model()
	var wraith_king := WraithKing.new("white", Vector2i(4, 4))
	var victim := Pawn.new("black", Vector2i(3, 3))
	var black_king := ClassicKing.new("black", Vector2i(0, 7))
	model.add_piece(wraith_king, wraith_king.coordinate)
	model.add_piece(victim, victim.coordinate)
	model.add_piece(black_king, black_king.coordinate)
	_expect(wraith_king.max_hp == 4 and wraith_king.current_hp == 4, "Wraith King starts with four HP")
	_expect(await model.submit_move(wraith_king, victim.coordinate), "Wraith King can directly capture")
	_expect(model.has_tile_effect(&"cursed_mark", Vector2i(3, 3), wraith_king.piece_id), "direct capture leaves an owned Cursed Mark")
	_expect(model.has_pending_reaction() and wraith_king.coordinate in model.get_pending_reaction()["targets"], "Lingering Malice offers an optional bonus step and a decline target")
	_expect(await model.submit_reaction_selection(Vector2i(2, 2)), "Lingering Malice accepts an adjacent bonus destination")
	_expect(wraith_king.coordinate == Vector2i(2, 2) and not model.has_tile_effect(&"cursed_mark", Vector2i(3, 3), wraith_king.piece_id), "bonus step consumes its triggering mark")
	model.free()
	var marked_model := _new_empty_model()
	var marked_king := WraithKing.new("white", Vector2i(4, 4)); var marked_enemy_king := ClassicKing.new("black", Vector2i(0, 7))
	marked_model.add_piece(marked_king, marked_king.coordinate); marked_model.add_piece(marked_enemy_king, marked_enemy_king.coordinate)
	marked_model.add_tile_effect(&"cursed_mark", Vector2i(3, 4), "white", marked_king.piece_id)
	_expect(await marked_model.submit_move(marked_king, Vector2i(3, 4)) and marked_model.has_pending_reaction(), "landing on a persistent Cursed Mark triggers Lingering Malice without another capture")
	await marked_model.submit_reaction_selection(marked_king.coordinate)
	_expect(not marked_model.has_tile_effect(&"cursed_mark", Vector2i(3, 4), marked_king.piece_id), "declining the optional bonus still consumes the activated mark")
	marked_model.free()

func _test_wraith_summon_autonomous_lifecycle() -> void:
	var model := _new_empty_model()
	var wraith_king := WraithKing.new("white", Vector2i(4, 4))
	var overlap_piece := Pawn.new("white", Vector2i(3, 3))
	var target := Rook.new("black", Vector2i(1, 1))
	target.max_hp = 2; target.current_hp = 2
	var black_king := ClassicKing.new("black", Vector2i(0, 7))
	model.add_piece(wraith_king, wraith_king.coordinate); model.add_piece(overlap_piece, overlap_piece.coordinate)
	model.add_piece(target, target.coordinate); model.add_piece(black_king, black_king.coordinate)
	_expect(await model.submit_active_ability(wraith_king, target.coordinate), "Summon Wraith accepts any enemy physical piece")
	_expect(model.autonomous_entities.size() == 1 and model.autonomous_entities[0].coordinate == Vector2i(4, 4), "summoned Wraith remains at its source during the summoning round")
	_expect(int(model.autonomous_entities[0].custom_state.get("next_move_turn", 0)) == 4, "summoned Wraith schedules its first step three shared rounds later")
	_expect(wraith_king.is_active_ability_ready(), "one active Wraith leaves Summon Wraith available for a second projectile")
	_expect(model.begin_action("black"), "opponent action can begin while the Wraith exists")
	await model.continue_action_resolution()
	_expect(model.autonomous_entities.size() == 1 and model.autonomous_entities[0].coordinate == Vector2i(4, 4) and model.global_turn_number == 2, "Wraith remains stationary when the summoning round completes")
	_expect(model.begin_action("white"), "the owning army can act during a waiting round")
	await model.continue_action_resolution()
	_expect(model.autonomous_entities.size() == 1 and model.autonomous_entities[0].coordinate == Vector2i(4, 4), "Wraith does not advance before three rounds elapse")
	model.global_turn_number = 4
	model.current_turn = "white"
	_expect(model.begin_action("white"), "the owning army can act when the Wraith's scheduled round arrives")
	await model.continue_action_resolution()
	_expect(model.autonomous_entities.size() == 1 and model.autonomous_entities[0].coordinate == Vector2i(3, 3), "Wraith advances one square on its scheduled third round")
	_expect(int(model.autonomous_entities[0].custom_state.get("next_move_turn", 0)) == 7, "a Wraith step schedules the next step three rounds later")
	await model.run_autonomous_phase("white")
	_expect(model.autonomous_entities[0].coordinate == Vector2i(3, 3), "Wraith cannot advance twice during the same round")
	model.global_turn_number = 7
	await model.run_autonomous_phase("white")
	_expect(model.autonomous_entities.size() == 1 and model.autonomous_entities[0].coordinate == Vector2i(2, 2), "Wraith advances again after another three rounds")
	model.global_turn_number = 10
	await model.run_autonomous_phase("white")
	_expect(model.board[1][1] == target and target.current_hp == 1 and model.autonomous_entities.is_empty(), "Wraith deals one damage to a durable ordinary target and then disappears")
	_expect(wraith_king.is_active_ability_ready(), "Summon Wraith becomes available after its Wraith resolves")
	model.free()

	var replacement_model := _new_empty_model()
	var replacement_king := WraithKing.new("white", Vector2i(4, 4))
	var first_target := Rook.new("black", Vector2i(1, 1))
	var second_target := Bishop.new("black", Vector2i(1, 3))
	var third_target := Knight.new("black", Vector2i(1, 5))
	replacement_model.add_piece(replacement_king, replacement_king.coordinate)
	for replacement_target in [first_target, second_target, third_target]:
		replacement_model.add_piece(replacement_target, replacement_target.coordinate)
	await replacement_model.summon_wraith(replacement_king, first_target)
	_expect(first_target.coordinate not in replacement_king.get_active_ability_targets() and second_target.coordinate in replacement_king.get_active_ability_targets(), "a lone Wraith's target is unavailable to a second Wraith")
	await replacement_model.summon_wraith(replacement_king, second_target)
	var oldest_wraith := replacement_model.get_wraith_replacement_candidate(replacement_king.piece_id)
	var replacement_targets := replacement_king.get_active_ability_targets()
	_expect(oldest_wraith != null and oldest_wraith.target_piece_id == first_target.piece_id, "the first summoned Wraith becomes the two-slot queue's replacement candidate")
	_expect(first_target.coordinate in replacement_targets and second_target.coordinate not in replacement_targets, "targeting a replacement permits the cancellable Wraith's target but excludes the surviving Wraith's target")
	var surviving_wraith_id: String = replacement_model.get_wraith_entities_from_source(replacement_king.piece_id)[1].entity_id
	await replacement_model.summon_wraith(replacement_king, first_target)
	var replaced_entities := replacement_model.get_wraith_entities_from_source(replacement_king.piece_id)
	_expect(replaced_entities.size() == 2 and replaced_entities[0].entity_id == surviving_wraith_id, "a third summon removes the oldest Wraith and preserves the newer one")
	var chased_target_ids: Array[String] = []
	for active_wraith in replaced_entities:
		chased_target_ids.append(active_wraith.target_piece_id)
	_expect(chased_target_ids == [second_target.piece_id, first_target.piece_id], "replacement can retarget the cancelled Wraith's piece without creating duplicate chasers")
	var entity_count_before_duplicate := replaced_entities.size()
	await replacement_model.summon_wraith(replacement_king, first_target)
	_expect(replacement_model.get_wraith_entities_from_source(replacement_king.piece_id).size() == entity_count_before_duplicate, "model-level summoning rejects a target still chased by a non-cancellable Wraith")
	replacement_model.free()

	var pass_model := _new_empty_model()
	var stalled_king := WraithKing.new("white", Vector2i(4, 4))
	var pass_target := Rook.new("black", Vector2i(1, 1))
	var pass_enemy_king := ClassicKing.new("black", Vector2i(0, 7))
	pass_model.add_piece(stalled_king, stalled_king.coordinate)
	pass_model.add_piece(pass_target, pass_target.coordinate)
	pass_model.add_piece(pass_enemy_king, pass_enemy_king.coordinate)
	await pass_model.summon_wraith(stalled_king, pass_target)
	pass_model.global_turn_number = 4
	stalled_king.stunned = true
	stalled_king.stun_timer = 99
	pass_model.forced_pass_delay_seconds = 0.0
	await pass_model.resolve_unplayable_turns()
	_expect(pass_model.autonomous_entities[0].coordinate == Vector2i(3, 3), "a scheduled Wraith advances when its owner's turn is forced to pass")
	pass_model.free()

	var king_model := _new_empty_model()
	var king_hunter := WraithKing.new("white", Vector2i(4, 4))
	var king_target := MinotaurKing.new("black", Vector2i(3, 3))
	king_model.add_piece(king_hunter, king_hunter.coordinate)
	king_model.add_piece(king_target, king_target.coordinate)
	var king_hp_before := king_target.current_hp
	await king_model.summon_wraith(king_hunter, king_target)
	king_model.global_turn_number = 4
	await king_model.run_autonomous_phase("white")
	_expect(king_model.board[3][3] == king_target and king_target.current_hp == king_hp_before - WraithKing.SUMMON_WRAITH_DAMAGE, "Wraith deals one damage instead of outright destroying a King on arrival")
	_expect(king_model.autonomous_entities.is_empty() and king_hunter.is_active_ability_ready(), "Wraith disappears and re-enables Summon Wraith after damaging a King")
	king_model.free()

func _test_wraith_state_round_trip() -> void:
	var model := _new_empty_model()
	var wraith_king := WraithKing.new("white", Vector2i(4, 4)); var target := Rook.new("black", Vector2i(0, 0))
	model.add_piece(wraith_king, wraith_king.coordinate); model.add_piece(target, target.coordinate)
	model.add_tile_effect(&"cursed_mark", Vector2i(2, 2), "white", wraith_king.piece_id)
	var entity := ChessAutonomousEntityState.new(); entity.entity_id = model._allocate_state_id("entity"); entity.type_id = &"wraith"; entity.coordinate = Vector2i(3, 3); entity.owner_color = "white"; entity.source_piece_id = wraith_king.piece_id; entity.target_piece_id = target.piece_id; entity.custom_state = {"next_move_turn": 4}
	model.autonomous_entities.append(entity)
	var decoded := ChessPositionCodec.from_json(ChessPositionCodec.to_json(model.capture_position()))
	_expect(decoded.errors.is_empty(), "Wraith board state passes position JSON validation")
	var restored := ChessBoardModel.new(); restored.initialize_battle()
	_expect(restored.load_position(decoded.position), "Wraith board state reloads")
	_expect(restored.tile_effects.size() == 1 and restored.autonomous_entities.size() == 1 and restored.find_piece_by_id(restored.autonomous_entities[0].target_piece_id) != null, "reload preserves marks, autonomous entities, and target identity")
	_expect(int(restored.autonomous_entities[0].custom_state.get("next_move_turn", 0)) == 4, "reload preserves the Wraith's scheduled movement round")
	restored.free(); model.free()

func _test_wraith_cpu_active_integration() -> void:
	var model := _new_empty_model(); add_child(model)
	var king := WraithKing.new("white", Vector2i(4, 4)); var target := Rook.new("black", Vector2i(0, 0)); var enemy_king := ClassicKing.new("black", Vector2i(0, 7))
	model.add_piece(king, king.coordinate); model.add_piece(target, target.coordinate); model.add_piece(enemy_king, enemy_king.coordinate)
	for coord in model.get_adjacent_squares(king.coordinate):
		var blocker := Pawn.new("white", coord); blocker.stunned = true; blocker.stun_timer = 99; model.add_piece(blocker, coord)
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu); cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	var thought = await cpu.think()
	_expect(thought != null and thought.action_kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and thought.piece_type_id == &"wraith_king", "CPU can enumerate and select Summon Wraith as a primary action")
	cpu.queue_free(); model.queue_free(); await get_tree().process_frame

func _test_completion_gate_contract() -> void:
	var unclaimed := CompletionGate.new()
	unclaimed.close()
	_expect(unclaimed.is_completed(), "unclaimed completion gate resolves immediately")
	var claimed := CompletionGate.new()
	claimed.hold()
	claimed.close()
	_expect(not claimed.is_completed(), "claimed completion gate waits after emission closes")
	claimed.release()
	_expect(claimed.is_completed(), "claimed completion gate resolves after release")

func _test_reaction_queued_boundary() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	model.add_piece(minotaur, minotaur.coordinate)
	var observed: Array[String] = []
	model.reaction_queued.connect(func(_piece: ModelPiece, action_type: String, _event_data, _sequence: int): observed.append(action_type))
	model.queue_selection_opportunity(minotaur, "retaliating_rage", null)
	model.battle_over = true
	model.queue_selection_opportunity(minotaur, "retaliating_rage", null)
	_expect(observed == ["retaliating_rage"], "reaction_queued reports accepted opportunities but suppresses rejected post-battle reactions")
	model.free()

func _test_stun_timer_saturates_at_zero() -> void:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	var pawn: ModelPiece = model.board[6][0]
	pawn.decrement_stun_timer()
	pawn.decrement_stun_timer()
	_expect(pawn.stun_timer == 0 and not pawn.stunned, "unstunned pieces do not accumulate negative stun timers")
	pawn.stun(2)
	pawn.decrement_stun_timer()
	_expect(pawn.stunned and pawn.stun_timer == 1, "active stun timer counts down while positive")
	pawn.decrement_stun_timer()
	_expect(not pawn.stunned and pawn.stun_timer == 0, "stun recovery stops exactly at zero")
	pawn.decrement_stun_timer()
	_expect(pawn.stun_timer == 0, "recovered stun timer remains saturated at zero")
	model.free()

func _test_lethal_damage_event_order() -> void:
	var model := _new_empty_model()
	var pawn := Pawn.new("white", Vector2i(4, 4))
	model.add_piece(pawn, pawn.coordinate)
	var events: Array[String] = []
	var observation := {"lethal_hp": 1}
	model.piece_damaged.connect(func(piece: ModelPiece, _amount: int, current_hp: int, _max_hp: int):
		if piece == pawn:
			events.append("damaged")
			observation.lethal_hp = current_hp)
	model.piece_destroyed.connect(func(piece: ModelPiece):
		if piece == pawn:
			events.append("destroyed"))
	await pawn.take_damage(1)
	_expect(events == ["damaged", "destroyed"] and observation.lethal_hp <= 0, "lethal damage emits its damage event before destruction")
	_expect(model.board[4][4] == null, "lethal damage still removes the defeated piece")
	model.free()

func _test_initialization_and_move() -> void:
	var model := ChessBoardModel.new()
	_expect(model.initialize_battle(), "standalone Model initializes explicitly")
	_expect(not model.initialize_battle(), "standalone initialization is idempotent")
	_expect(_count_pieces(model) == 32, "standalone Model creates the default board")
	var pawn: ModelPiece = model.board[6][0]
	_expect(await model.submit_move(pawn, Vector2i(4, 0)), "standalone Model accepts a legal move")
	_expect(model.board[4][0] == pawn and model.current_turn == "black", "headless move resolves state and turn")
	var black_king := model.get_king("black") as KingPiece
	_expect(black_king.current_cooldown == black_king.base_cooldown, "Black's authored cooldown remains full on its first playable turn")
	model.switch_turn()
	model.switch_turn()
	_expect(black_king.current_cooldown == black_king.base_cooldown - 1, "Black's starting cooldown first decrements on its second playable turn")
	_expect(not model.action_in_progress, "unobserved movement gate completes immediately")
	_expect(not (await model.submit_move(pawn, Vector2i(3, 0))), "wrong-turn command is rejected")
	model.free()


func _test_active_ability_cooldown_counts_full_turns() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var target := ClassicKing.new("black", Vector2i(3, 3))
	target.max_hp = 10
	target.current_hp = 10
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(target, target.coordinate)
	_expect(arakne.current_cooldown == ArakneKing.ACTIVE_ABILITY_COOLDOWN and not arakne.is_active_ability_ready(), "an active King starts at its authored cooldown")
	arakne.set_cooldown(0)
	_expect(await model.submit_active_ability(arakne, target.coordinate), "ready active ability is accepted before cooldown starts")
	_expect(arakne.current_cooldown == 0 and arakne.cooldown_reset_pending and model.current_turn == "black", "ability use schedules recharge without immediately emitting cooldown")
	var restored_model := ChessBoardModel.new()
	restored_model.initialize_battle()
	_expect(restored_model.load_position(model.capture_position()), "a position with scheduled recharge reloads successfully")
	var restored_arakne := restored_model.get_king("white") as ArakneKing
	_expect(restored_arakne != null and restored_arakne.cooldown_reset_pending and not restored_arakne.is_active_ability_ready(), "position reload preserves scheduled recharge as unavailable")
	restored_model.free()
	model.switch_turn()
	_expect(arakne.current_cooldown == 1 and not arakne.cooldown_reset_pending and model.current_turn == "white", "the next King turn emits the configured cooldown without decrementing it")
	_expect(not (await model.submit_active_ability(arakne, target.coordinate)), "an emitted cooldown blocks the active ability for that complete turn")
	model.switch_turn()
	model.switch_turn()
	_expect(arakne.current_cooldown == 0 and model.current_turn == "white", "the following King turn decrements cooldown 1 to ready")
	arakne.base_cooldown = 2
	_expect(await model.submit_active_ability(arakne, target.coordinate), "active ability is usable again on the turn after its full cooldown turn")
	model.switch_turn()
	_expect(arakne.current_cooldown == 2, "a longer configured cooldown begins at its authored count")
	model.switch_turn()
	model.switch_turn()
	_expect(arakne.current_cooldown == 1, "cooldown 2 remains unavailable after its first complete cooldown turn")
	model.switch_turn()
	model.switch_turn()
	_expect(arakne.current_cooldown == 0, "cooldown 2 becomes ready after two complete cooldown turns")
	model.free()

func _test_active_ability_cooldown_override() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	model.add_piece(arakne, arakne.coordinate)
	_expect(not arakne.is_active_ability_ready(), "cooldown override leaves normal startup behavior unchanged while disabled")
	model.set_active_ability_cooldowns_disabled(true)
	_expect(arakne.current_cooldown == 0 and arakne.is_active_ability_ready(), "cooldown override immediately readies an existing active King")
	arakne.schedule_cooldown()
	_expect(arakne.current_cooldown == 0 and not arakne.cooldown_reset_pending and arakne.is_active_ability_ready(), "cooldown override prevents a spent ability from scheduling recharge")
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	model.add_piece(minotaur, minotaur.coordinate)
	_expect(minotaur.current_cooldown == 0 and minotaur.is_active_ability_ready(), "cooldown override readies active Kings added after it is enabled")
	model.set_active_ability_cooldowns_disabled(false)
	minotaur.schedule_cooldown()
	_expect(minotaur.cooldown_reset_pending and not minotaur.is_active_ability_ready(), "disabling the override restores normal cooldown scheduling")
	model.free()


func _test_forced_pass_after_action() -> void:
	var model := _new_empty_model()
	model.forced_pass_delay_seconds = 0.0
	var rook := Rook.new("white", Vector2i(7, 0))
	var minotaur := MinotaurKing.new("black", Vector2i(0, 0))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(minotaur, minotaur.coordinate)
	minotaur.stun(2)
	var passed_colors: Array[String] = []
	model.turn_passed.connect(func(color: String, _count: int): passed_colors.append(color))
	_expect(await model.submit_move(rook, Vector2i(6, 0)), "a legal action resolves before forced-pass evaluation")
	_expect(minotaur.stunned and minotaur.stun_timer == 1, "turn-entry stun countdown runs before checking the incoming color's actions")
	_expect(passed_colors == ["black"] and model.current_turn == "white", "a still-stunned sole King passes back to the playable opponent")
	model.free()


func _test_turn_entry_recovery_prevents_pass() -> void:
	var model := _new_empty_model()
	model.forced_pass_delay_seconds = 0.0
	var rook := Rook.new("white", Vector2i(7, 0))
	var minotaur := MinotaurKing.new("black", Vector2i(0, 0))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(minotaur, minotaur.coordinate)
	minotaur.stun(1)
	var pass_count := {"value": 0}
	model.turn_passed.connect(func(_color: String, _count: int): pass_count.value += 1)
	await model.submit_move(rook, Vector2i(6, 0))
	_expect(not minotaur.stunned and minotaur.stun_timer == 0, "a one-turn stun recovers on the incoming turn")
	_expect(model.current_turn == "black" and pass_count.value == 0, "recovery that restores a legal action preserves the incoming turn")
	model.free()

func _test_nonlethal_combat() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(minotaur, minotaur.coordinate)
	var observation := {"attack_events": 0}
	model.piece_attack_committed.connect(
		func(piece: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, _gate: CompletionGate):
			if piece == rook and defender == minotaur and from == Vector2i(4, 0) and to == Vector2i(4, 4):
				observation["attack_events"] += 1
	)

	_expect(await model.submit_move(rook, minotaur.coordinate), "headless nonlethal attack command is accepted")
	_expect(minotaur.current_hp == minotaur.max_hp - rook.attack_power, "nonlethal attack damages its defender")
	_expect(model.board[4][0] == rook and rook.coordinate == Vector2i(4, 0), "nonlethal attacker remains on its original square")
	_expect(model.board[4][4] == minotaur, "surviving defender remains on its square")
	_expect(observation["attack_events"] == 1, "nonlethal combat emits one attack presentation event")
	_expect(not model.action_in_progress and model.current_turn == "black", "unobserved attack presentation gate completes headlessly")
	model.free()

func _test_headless_rage() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var pawn := Pawn.new("white", Vector2i(3, 4))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(pawn, pawn.coordinate)
	_expect(model.begin_action("white"), "headless Rage action starts")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(model.board[3][4] == null, "headless Rage resolves adjacent damage")
	_expect(model.current_turn == "black", "headless Rage completes the action")
	model.free()

func _test_rage_raise_dead_includes_death_square() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(3, 4))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(rook, rook.coordinate)
	model.begin_action("white")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()

	_expect(model.board[3][4] == null, "Rage leaves its defeated piece's square empty")
	_expect(model.has_pending_reaction(), "Rage defeat queues a Raise Dead selection")
	var pending := model.get_pending_reaction()
	_expect(Vector2i(3, 4) in pending["targets"], "Raise Dead includes a death square emptied by Rage")
	await model.submit_reaction_selection(Vector2i(3, 4))
	_expect(model.board[3][4] is BonePawn, "Raise Dead can summon directly onto a Rage death square")
	model.free()

func _test_terminal_rank_raise_dead_expires_bone_pawn() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(6, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(7, 4))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(rook, rook.coordinate)
	var observation := {"bone_pawns_added": 0, "bone_pawns_destroyed": 0}
	model.piece_added.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_added"] += 1
	)
	model.piece_destroyed.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_destroyed"] += 1
	)

	model.begin_action("white")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(Vector2i(7, 4) in model.get_pending_reaction()["targets"], "opposite back rank remains a legal Raise Dead target")
	await model.submit_reaction_selection(Vector2i(7, 4))
	_expect(observation["bone_pawns_added"] == 1, "terminal-rank Bone Pawn is spawned through normal Model events")
	_expect(observation["bone_pawns_destroyed"] == 1, "terminal-rank Bone Pawn is immediately destroyed")
	_expect(model.board[7][4] == null, "terminal-rank summon leaves its square empty")
	_expect(not model.action_in_progress and model.current_turn == "black", "terminal-rank expiration completes the reaction action")
	model.free()

func _test_headless_reaction_priority() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(6, 6))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(rook, rook.coordinate)
	var observation := {"rage_effects": 0}
	model.ability_effect_resolved.connect(
		func(_piece: KingPiece, ability_name: String, _coords: Array):
			if ability_name == MinotaurKing.PASSIVE_ABILITY_NAME:
				observation["rage_effects"] += 1
	)
	model.begin_action("white")
	model.destroy_piece(rook, true)
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(observation["rage_effects"] == 1, "automatic Rage resolves before a pending choice")
	_expect(model.get_pending_reaction()["calling_piece"] == necromancer, "Raise Dead remains pending after higher-priority Rage")
	var target: Vector2i = model.get_pending_reaction()["targets"][0]
	await model.submit_reaction_selection(target)
	model.free()

func _test_arakne_staged_controller_selection() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(ClassicKing.new("black", Vector2i(0, 0)), Vector2i(0, 0))
	var controller := ChessBoardController.new()
	controller.model = model
	add_child(controller)
	controller.select_piece(arakne)
	_expect(Vector2i(4, 6) not in controller.legal_moves and Vector2i(4, 5) in controller.legal_moves, "initial Arakne selection shows ordinary King moves but not remote skitter endpoints")
	await controller._on_square_clicked(Vector2i(4, 5))
	var expected_skitter := arakne.get_skitter_destinations(Vector2i(4, 5))
	var expected_staged_targets: Array = [Vector2i(4, 5)]
	expected_staged_targets.append_array(expected_skitter)
	_expect(controller.skitter_intermediate == Vector2i(4, 5) and controller.legal_moves == expected_staged_targets, "choosing an empty first step highlights both stopping there and continuing along a Skitter path")
	_expect(Vector2i(4, 5) in controller.legal_moves, "the highlighted intermediate remains a separate one-step confirmation target")
	await controller._on_square_clicked(Vector2i(4, 3))
	_expect(controller.selected_piece == null and controller.skitter_intermediate == Vector2i(-1, -1), "clicking another initial King square cancels staged Skitter selection")
	controller.select_piece(arakne)
	await controller._on_square_clicked(Vector2i(4, 5))
	await controller._on_square_clicked(Vector2i(4, 5))
	_expect(arakne.coordinate == Vector2i(4, 5) and model.current_turn == "black", "clicking the intermediate again confirms a one-square move")
	controller.queue_free()
	model.free()

	var blocked_model := _new_empty_model()
	var blocked_arakne := ArakneKing.new("white", Vector2i(4, 4))
	blocked_model.add_piece(blocked_arakne, blocked_arakne.coordinate)
	blocked_model.add_piece(ClassicKing.new("black", Vector2i(0, 0)), Vector2i(0, 0))
	for blocker_coord in [Vector2i(3, 4), Vector2i(3, 6), Vector2i(5, 4), Vector2i(5, 6)]:
		blocked_model.add_piece(Pawn.new("white", blocker_coord), blocker_coord)
	var blocked_controller := ChessBoardController.new()
	blocked_controller.model = blocked_model
	add_child(blocked_controller)
	blocked_controller.select_piece(blocked_arakne)
	await blocked_controller._on_square_clicked(Vector2i(4, 5))
	_expect(blocked_arakne.coordinate == Vector2i(4, 5) and blocked_controller.skitter_intermediate == Vector2i(-1, -1), "an empty first square with no skitter options moves immediately")
	blocked_controller.queue_free()
	blocked_model.free()


func _test_special_moves() -> void:
	var skitter_model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	skitter_model.add_piece(arakne, arakne.coordinate)
	var shared_destination := Vector2i(4, 6)
	_expect(shared_destination not in arakne.get_legal_moves(), "Arakne no longer exposes remote skitter endpoints as ordinary King moves")
	_expect(not (await skitter_model.submit_move(arakne, shared_destination)), "remote Skitter endpoints cannot bypass path selection through ordinary move submission")
	var shared_paths: Array = []
	for action in skitter_model.get_legal_primary_actions("white"):
		if action.kind == ChessPrimaryAction.Kind.MOVE and action.target == shared_destination:
			shared_paths.append(action.path)
	_expect(shared_paths.size() == 2 and shared_paths[0] != shared_paths[1], "same-destination skitter routes remain distinct path-aware actions")
	var movement_events: Array[Vector2i] = []
	var skitter_events := {"count": 0}
	skitter_model.piece_move_committed.connect(func(_piece, _from, to, _gate): movement_events.append(to))
	skitter_model.skitter_step_started.connect(func(_piece, _from, _to): skitter_events.count += 1)
	var selected_path: Array[Vector2i] = []
	selected_path.assign(shared_paths[0])
	_expect(await skitter_model.submit_move_path(arakne, selected_path), "Arakne accepts an exact legal two-step path")
	_expect(movement_events == selected_path and skitter_events.count == 1 and skitter_model.board[shared_destination.x][shared_destination.y] == arakne, "Skitter commits both landings in order and marks only its second step")
	skitter_model.free()

	var return_model := _new_empty_model()
	var returning_arakne := ArakneKing.new("white", Vector2i(4, 4))
	return_model.add_piece(returning_arakne, returning_arakne.coordinate)
	var return_path: Array[Vector2i] = [Vector2i(3, 5), Vector2i(4, 4)]
	_expect(return_path in returning_arakne.get_legal_move_paths(), "Skitter may intentionally return to Arakne's occupied origin")
	_expect(await return_model.submit_move_path(returning_arakne, return_path), "the model accepts a legal return-to-origin Skitter path")
	_expect(returning_arakne.coordinate == Vector2i(4, 4) and return_model.last_move.get("from") == return_model.last_move.get("to"), "returning Skitter resolves both landings and records its actual origin destination")
	return_model.free()

	var interrupted_model := _new_empty_model()
	var interrupted_arakne := ArakneKing.new("white", Vector2i(4, 4))
	interrupted_model.add_piece(interrupted_arakne, interrupted_arakne.coordinate)
	var interrupted_path: Array[Vector2i] = [Vector2i(4, 5), Vector2i(3, 6)]
	var interrupted_skitter_events := {"count": 0}
	interrupted_model.piece_landed.connect(func(piece, _from, to, _gate):
		if piece == interrupted_arakne and to == interrupted_path[0]:
			piece.stunned = true)
	interrupted_model.skitter_step_started.connect(func(_piece, _from, _to): interrupted_skitter_events.count += 1)
	_expect(await interrupted_model.submit_move_path(interrupted_arakne, interrupted_path), "a legal path remains an accepted action when its first landing has consequences")
	_expect(interrupted_arakne.coordinate == interrupted_path[0] and interrupted_skitter_events.count == 0, "an intermediate landing consequence can stop Skitter before step two")
	_expect(interrupted_model.last_move.from == Vector2i(4, 4) and interrupted_model.last_move.to == interrupted_path[0], "an interrupted Skitter records its actual final landing")
	interrupted_model.free()

	var castle_model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(7, 4))
	var rook := Rook.new("white", Vector2i(7, 7))
	castle_model.add_piece(king, king.coordinate)
	castle_model.add_piece(rook, rook.coordinate)
	var castle_events := {"compound": 0, "ordinary": 0, "landings": []}
	castle_model.piece_castling_committed.connect(func(_king: KingPiece, _rook: ModelPiece, _king_from: Vector2i, _king_to: Vector2i, _rook_from: Vector2i, _rook_to: Vector2i, _presentation): castle_events.compound += 1)
	castle_model.piece_move_committed.connect(func(_piece: ModelPiece, _from: Vector2i, _to: Vector2i, _presentation): castle_events.ordinary += 1)
	castle_model.piece_landed.connect(func(piece: ModelPiece, _from: Vector2i, to: Vector2i, _gate: CompletionGate): castle_events.landings.append([piece, to]))
	_expect(await castle_model.submit_move(king, Vector2i(7, 6)), "headless castling command is accepted")
	_expect(castle_events.compound == 1 and castle_events.ordinary == 0, "castling publishes one atomic compound event instead of two ordinary moves")
	_expect(castle_events.landings == [[rook, Vector2i(7, 5)], [king, Vector2i(7, 6)]], "castling publishes rook and King arrivals in presentation order")
	_expect(castle_model.board[7][6] == king and castle_model.board[7][5] == rook, "castling places the king and rook on their destination squares")
	castle_model.free()

	var rook_grant_model := _new_empty_model()
	var rook_granted_pawn := Pawn.new("white", Vector2i(4, 4))
	rook_granted_pawn.grant_movement_type(&"rook")
	rook_grant_model.add_piece(rook_granted_pawn, rook_granted_pawn.coordinate)
	rook_grant_model.add_piece(ClassicKing.new("white", Vector2i(7, 7)), Vector2i(7, 7))
	rook_grant_model.add_piece(ClassicKing.new("black", Vector2i(0, 7)), Vector2i(0, 7))
	_expect(await rook_grant_model.submit_move(rook_granted_pawn, Vector2i(4, 2)), "a Rook-elevated pawn accepts a sideways move into an empty square")
	_expect(rook_grant_model.board[4][2] == rook_granted_pawn and rook_grant_model.board[4][4] == null, "a sideways elevated-pawn move commits as ordinary movement rather than en passant")
	rook_grant_model.free()

	var bishop_grant_model := _new_empty_model()
	var bishop_granted_pawn := Pawn.new("white", Vector2i(4, 4))
	bishop_granted_pawn.grant_movement_type(&"bishop")
	bishop_grant_model.add_piece(bishop_granted_pawn, bishop_granted_pawn.coordinate)
	bishop_grant_model.add_piece(ClassicKing.new("white", Vector2i(7, 7)), Vector2i(7, 7))
	bishop_grant_model.add_piece(ClassicKing.new("black", Vector2i(0, 7)), Vector2i(0, 7))
	_expect(await bishop_grant_model.submit_move(bishop_granted_pawn, Vector2i(3, 3)), "a Bishop-elevated pawn accepts an empty diagonal move")
	_expect(bishop_grant_model.board[3][3] == bishop_granted_pawn and bishop_grant_model.board[4][4] == null, "an empty diagonal elevated-pawn move is not mistaken for en passant")
	bishop_grant_model.free()

	var passant_model := _new_empty_model()
	var white_pawn := Pawn.new("white", Vector2i(3, 4))
	var black_pawn := Pawn.new("black", Vector2i(3, 5))
	passant_model.add_piece(white_pawn, white_pawn.coordinate)
	passant_model.add_piece(black_pawn, black_pawn.coordinate)
	passant_model.last_move = {"piece": black_pawn, "from": Vector2i(1, 5), "to": Vector2i(3, 5)}
	var passant_captures: Array[Dictionary] = []
	var passant_landings: Array[Vector2i] = []
	passant_model.piece_capture_committed.connect(
		func(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, captured_at: Vector2i, _presentation):
			passant_captures.append({"attacker": attacker, "defender": defender, "from": from, "to": to, "captured_at": captured_at})
	)
	passant_model.piece_landed.connect(func(piece: ModelPiece, _from: Vector2i, to: Vector2i, _gate: CompletionGate):
		if piece == white_pawn: passant_landings.append(to))
	_expect(await passant_model.submit_move(white_pawn, Vector2i(2, 5)), "headless en passant command is accepted")
	_expect(passant_model.board[2][5] == white_pawn and passant_model.board[3][5] == null, "en passant removes the adjacent pawn")
	_expect(passant_captures.size() == 1 and passant_captures[0]["captured_at"] == Vector2i(3, 5), "en passant reports its separate captured square through the lethal-capture event")
	_expect(passant_landings == [Vector2i(2, 5)], "en passant publishes the attacker's destination arrival")
	passant_model.free()

	var promotion_model := _new_empty_model()
	var promoting_pawn := Pawn.new("white", Vector2i(1, 0))
	promotion_model.add_piece(promoting_pawn, promoting_pawn.coordinate)
	_expect(await promotion_model.submit_move(promoting_pawn, Vector2i(0, 0)), "headless promotion move is accepted")
	_expect(promotion_model.board[0][0] is Queen, "promotion replaces the pawn with a Queen")
	promotion_model.free()

func _test_minotaur_charge_landing() -> void:
	var surviving_model := _new_empty_model()
	var charging_minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var defending_minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	charging_minotaur.set_cooldown(0)
	defending_minotaur.stunned = true
	surviving_model.add_piece(charging_minotaur, charging_minotaur.coordinate)
	surviving_model.add_piece(defending_minotaur, defending_minotaur.coordinate)
	_expect(await surviving_model.submit_active_ability(charging_minotaur, defending_minotaur.coordinate), "Charge against a surviving king is accepted")
	_expect(defending_minotaur.current_hp == defending_minotaur.max_hp - 2, "Charge damages the surviving king")
	_expect(surviving_model.board[4][4] == defending_minotaur, "surviving Charge target keeps its square")
	_expect(surviving_model.board[4][3] == charging_minotaur and charging_minotaur.coordinate == Vector2i(4, 3), "Charge lands adjacent to a surviving target")
	_expect(not surviving_model.action_in_progress and surviving_model.current_turn == "white", "a surviving stunned sole King automatically passes after Charge completes")
	surviving_model.free()

	var lethal_model := _new_empty_model()
	var lethal_minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var arakne := ArakneKing.new("black", Vector2i(4, 4))
	lethal_minotaur.set_cooldown(0)
	lethal_model.add_piece(lethal_minotaur, lethal_minotaur.coordinate)
	lethal_model.add_piece(arakne, arakne.coordinate)
	_expect(await lethal_model.submit_active_ability(lethal_minotaur, arakne.coordinate), "lethal Charge command is accepted")
	_expect(lethal_model.board[4][3] == lethal_minotaur and lethal_minotaur.coordinate == Vector2i(4, 3) and lethal_model.board[4][4] == null, "lethal Charge stops adjacent to a durable target")
	lethal_model.free()

func _test_model_owned_raise_dead_choice() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var bishop := Bishop.new("white", Vector2i(4, 4))
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	_expect(model.begin_action("white"), "headless Raise Dead action starts")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	_expect(model.has_pending_reaction(), "Model owns the pending Raise Dead decision")
	var pending := model.get_pending_reaction()
	var finished := {"action_type": "", "event_data": null, "sequence": -1, "resolved": false}
	model.reaction_finished.connect(func(_piece: ModelPiece, action_type: String, event_data, sequence: int, resolved: bool):
		finished.action_type = action_type
		finished.event_data = event_data
		finished.sequence = sequence
		finished.resolved = resolved
	, CONNECT_ONE_SHOT)
	_expect(pending["calling_piece"] == necromancer, "pending decision identifies its reacting piece")
	_expect(bishop.coordinate in pending["targets"], "direct destruction includes its empty death square")
	var target: Vector2i = bishop.coordinate
	_expect(not (await model.submit_reaction_selection(Vector2i(-1, -1))), "invalid reaction choice is rejected")
	_expect(model.has_pending_reaction(), "invalid reaction choice preserves pending state")
	_expect(await model.submit_reaction_selection(target), "valid reaction choice is accepted")
	_expect(model.board[target.x][target.y] is BonePawn, "headless Raise Dead summons a Bone Pawn")
	_expect(finished.get("action_type") == "raise_dead" and finished.get("event_data") == bishop.coordinate and finished.get("sequence") == pending["sequence"] and finished.get("resolved"), "Raise Dead completion identifies the exact corpse-origin queue entry after summoning")
	_expect(not model.action_in_progress and model.current_turn == "black", "reaction submission resumes and finishes the action")
	model.free()

func _test_raise_dead_excludes_occupied_death_square() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(4, 4))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	var capture_events: Array[Dictionary] = []
	model.piece_capture_committed.connect(
		func(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, captured_at: Vector2i, _presentation):
			capture_events.append({"attacker": attacker, "defender": defender, "from": from, "to": to, "captured_at": captured_at})
	)
	_expect(await model.submit_move(rook, bishop.coordinate), "lethal capture that triggers Raise Dead is accepted")
	_expect(capture_events.size() == 1 and capture_events[0]["defender"] == bishop and capture_events[0]["captured_at"] == Vector2i(4, 4), "ordinary lethal capture reports both pieces and its destination square")
	_expect(model.board[4][4] == rook, "capturing piece occupies the defender's death square")
	var pending := model.get_pending_reaction()
	_expect(Vector2i(4, 4) not in pending["targets"], "Raise Dead excludes an occupied death square")
	_expect(not pending["targets"].is_empty(), "occupied death square still leaves adjacent Raise Dead choices")
	await model.submit_reaction_selection(pending["targets"][0])
	model.free()

func _test_complete_battle_from_commands() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var black_king := ClassicKing.new("black", Vector2i(3, 3))
	arakne.set_cooldown(0)
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(black_king, black_king.coordinate)
	_expect(await model.submit_active_ability(arakne, black_king.coordinate), "headless active-ability command is accepted")
	_expect(model.battle_over, "headless command sequence completes a battle")
	_expect(model.battle_result == "white", "headless battle records the winner")
	model.free()

func _new_empty_model() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null:
				model.unregister_piece(piece)
	model.board.clear()
	for row_index in range(8):
		var row: Array = []
		for column_index in range(8):
			row.append(null)
		model.board.append(row)
	model.last_move = {}
	model.current_turn = "white"
	model.battle_over = false
	model.battle_result = ""
	model.defeated_king_colors.clear()
	model.selection_queue.clear()
	model.pending_reaction.clear()
	model.action_in_progress = false
	model.action_owner_color = ""
	return model

func _count_pieces(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null:
				count += 1
	return count

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
