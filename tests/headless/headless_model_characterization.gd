extends Node

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
	await _test_forced_pass_after_action()
	await _test_turn_entry_recovery_prevents_pass()
	await _test_nonlethal_combat()
	await _test_lethal_damage_event_order()
	await _test_arakne_staged_controller_selection()
	await _test_special_moves()
	await _test_minotaur_charge_landing()
	await _test_headless_rage()
	await _test_rage_raise_dead_includes_death_square()
	await _test_terminal_rank_raise_dead_expires_bone_pawn()
	await _test_headless_reaction_priority()
	await _test_model_owned_raise_dead_choice()
	await _test_raise_dead_excludes_occupied_death_square()
	await _test_complete_battle_from_commands()

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
	_expect(controller.skitter_intermediate == Vector2i(4, 5) and controller.legal_moves == expected_skitter, "choosing an empty first step replaces initial highlights with only its skitter destinations")
	_expect(Vector2i(4, 5) not in controller.legal_moves, "the unhighlighted intermediate remains a separate confirmation target")
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
	_expect(lethal_model.board[4][4] == lethal_minotaur and lethal_minotaur.coordinate == Vector2i(4, 4), "lethal Charge still occupies the target square")
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
	_expect(pending["calling_piece"] == necromancer, "pending decision identifies its reacting piece")
	_expect(bishop.coordinate in pending["targets"], "direct destruction includes its empty death square")
	var target: Vector2i = bishop.coordinate
	_expect(not (await model.submit_reaction_selection(Vector2i(-1, -1))), "invalid reaction choice is rejected")
	_expect(model.has_pending_reaction(), "invalid reaction choice preserves pending state")
	_expect(await model.submit_reaction_selection(target), "valid reaction choice is accepted")
	_expect(model.board[target.x][target.y] is BonePawn, "headless Raise Dead summons a Bone Pawn")
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
