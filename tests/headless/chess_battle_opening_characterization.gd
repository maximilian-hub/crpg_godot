extends Node

const GAME := preload("res://scenes/chess_game.tscn")

var failures := 0
var checks := 0


func _ready() -> void:
	await _test_staggered_opening("white")
	await _test_staggered_opening("black")
	await _test_reactions_precede_black_activation()
	await _test_black_cpu_waits_for_activation()
	await _test_cancellation()
	await _test_instant_bypass()
	if failures == 0:
		print("CHESS BATTLE OPENING CHARACTERIZATION: PASS (%d checks)" % checks)
	else:
		printerr("CHESS BATTLE OPENING CHARACTERIZATION: FAIL (%d/%d)" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_staggered_opening(player_color: String) -> void:
	var context := await _create_game(player_color)
	var game: ChessGame = context.game
	var adapter: ChessPresentationAdapter = context.adapter
	var director: ChessBattleOpeningDirector = game.opening_director
	var board_view := game.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	_check(board_view.visual_style == game.battle_presentation.board_style and board_view.visual_style.material_surface_enabled, "%s view applies the default battle profile before the opening presentation" % player_color)
	_check(context.setup_concurrent, "%s view runs both army setups concurrently" % player_color)
	_check(context.black_dormant_during_setup, "%s view presents Black's King as inert stone without an Aura during setup" % player_color)
	_check(context.white_ran_without_black, "%s view activates White alone immediately after setup" % player_color)
	_check(director.stage == ChessBattleOpeningDirector.Stage.AWAITING_BLACK_ACTIVATION and game.opening_pending and not game.opening_in_progress, "%s view waits for White's first settled action after White activation" % player_color)
	_check(not game.controller.is_input_locked and not game.white_cpu_player.is_enabled and not game.black_cpu_player.is_enabled, "%s view releases a player-controlled White turn while Black remains pending" % player_color)
	var white_magic := adapter.get_king_magic_controller("white")
	var black_magic := adapter.get_king_magic_controller("black")
	_check(white_magic.resolved_aura_profile.core_color.is_equal_approx(Color(0.65625, 0.65625, 0.65625, 1)) and black_magic.resolved_aura_profile.core_color.is_equal_approx(Color(0.364044, 0, 0.589844, 1)), "%s view resolves Arakne and Necromancer Auras by King type rather than player/opponent army" % player_color)
	_check(white_magic.hand_aura.profile.core_color.is_equal_approx(white_magic.king_aura.profile.core_color) and black_magic.hand_aura.profile.core_color.is_equal_approx(black_magic.king_aura.profile.core_color), "%s view applies each King's universal Aura identity to both King and ritual hand" % player_color)
	_check(white_magic.king_aura.silhouette_power > 0.0 and black_magic.stone_sprite.visible and is_zero_approx(black_magic.king.sprite.self_modulate.a) and is_zero_approx(black_magic.king_aura.silhouette_power) and is_zero_approx(black_magic.king_aura.particle_power), "%s view leaves White awakened while Black remains inert stone during White's first turn" % player_color)

	var black_boundary := {"started": false, "locked": false, "settled": false, "black_turn": false}
	director.black_activation_started.connect(func():
		black_boundary.started = true
		black_boundary.locked = game.controller.is_input_locked
		black_boundary.settled = game.model.is_settled()
		black_boundary.black_turn = game.model.current_turn == "black"
	, CONNECT_ONE_SHOT)
	var final_completed := {"value": false}
	game.opening_completed.connect(func(): final_completed.value = true, CONNECT_ONE_SHOT)
	var moved := await game.model.submit_move(game.model.board[6][0], Vector2i(5, 0))
	await _wait_until(func(): return final_completed.value, 5.0)
	_check(moved and black_boundary.started and black_boundary.locked and black_boundary.settled and black_boundary.black_turn, "%s view gates the settled Black turn before starting Black activation" % player_color)
	_check(final_completed.value and not game.opening_pending and not game.controller.is_input_locked, "%s view unlocks Black only after its ritual completes" % player_color)
	_check(not adapter.get_king_magic_controller("black").running and adapter.get_king_magic_controller("black").king_aura.silhouette_power > 0.0, "%s view finishes with Black's resting Aura active" % player_color)
	await _destroy_game(game)


func _test_reactions_precede_black_activation() -> void:
	var context := await _create_game("white")
	var game: ChessGame = context.game
	var director: ChessBattleOpeningDirector = game.opening_director
	var order: Array[String] = []
	var boundary := {"queue_empty": false, "no_pending": false}
	game.model.reaction_selection_resolved.connect(func(_piece, _action, _target): order.append("reaction_resolved"), CONNECT_ONE_SHOT)
	director.black_activation_started.connect(func():
		order.append("black_activation")
		boundary.queue_empty = game.model.selection_queue.is_empty()
		boundary.no_pending = not game.model.has_pending_reaction()
	, CONNECT_ONE_SHOT)
	var victim: ModelPiece = game.model.board[0][1]
	game.model.piece_move_committed.connect(func(_piece, _from, _to, _completion):
		if game.model.is_piece_active(victim):
			game.model.destroy_piece(victim, true)
	, CONNECT_ONE_SHOT)
	var accepted := await game.model.submit_move(game.model.board[6][0], Vector2i(5, 0))
	_check(accepted and game.model.has_pending_reaction(), "The injected first White move pauses on Black's queued reaction selection")
	var pending := game.model.get_pending_reaction()
	if not pending.is_empty():
		await game.model.submit_reaction_selection(pending.targets[0])
	await _wait_until(func(): return not game.opening_pending, 5.0)
	_check(order == ["reaction_resolved", "black_activation"], "Every queued reaction resolves before Black activation begins")
	_check(boundary.queue_empty and boundary.no_pending and game.model.is_settled(), "Black activation begins only after both reaction containers and the action are settled")
	await _destroy_game(game)


func _test_cancellation() -> void:
	var context := await _create_game("white", 2.0)
	var game: ChessGame = context.game
	var director: ChessBattleOpeningDirector = game.opening_director
	var started := {"value": false}
	director.black_activation_started.connect(func(): started.value = true, CONNECT_ONE_SHOT)
	await game.model.submit_move(game.model.board[6][0], Vector2i(5, 0))
	await _wait_until(func(): return started.value, 3.0)
	director.cancel()
	await get_tree().process_frame
	_check(started.value and not game.opening_pending and game.get_node("ChessPresentationAdapter").piece_views.values().all(func(piece): return piece.visible), "Cancelling delayed Black activation resolves onto a visible board")
	_check(not director.temporary_hands.size() and not game.controller.is_input_locked, "Delayed activation cancellation clears temporary state and releases the turn gate")
	await _destroy_game(game)


func _test_black_cpu_waits_for_activation() -> void:
	var context := await _create_game("white", 0.01, ChessGame.ControlMode.PLAYER_VS_CPU)
	var game: ChessGame = context.game
	var director: ChessBattleOpeningDirector = game.opening_director
	var order: Array[String] = []
	director.black_activation_started.connect(func(): order.append("black_activation"), CONNECT_ONE_SHOT)
	game.opening_completed.connect(func(): order.append("opening_completed"), CONNECT_ONE_SHOT)
	game.model.action_started.connect(func(color: String):
		if color == "black":
			order.append("black_action")
	)
	await game.model.submit_move(game.model.board[6][0], Vector2i(5, 0))
	await _wait_until(func(): return "black_action" in order, 5.0)
	_check(order.slice(0, 3) == ["black_activation", "opening_completed", "black_action"], "The deferred Black CPU command begins only after Black activation and the final opening boundary")
	await _destroy_game(game)


func _test_instant_bypass() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var game := GAME.instantiate() as ChessGame
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	var adapter := game.get_node("ChessPresentationAdapter") as ChessPresentationAdapter
	adapter.presentation_policy = ChessPresentationPolicy.new()
	adapter.presentation_policy.speed = ChessPresentationPolicy.Speed.INSTANT
	viewport.add_child(game)
	await get_tree().process_frame
	_check(not game.opening_pending and adapter.piece_views.values().all(func(piece): return piece.visible), "Instant presentation resolves both activations without a delayed barrier")
	_check(not game.controller.is_input_locked and game.opening_director.stage == ChessBattleOpeningDirector.Stage.COMPLETE, "Instant presentation starts ordinary play in the completed opening state")
	await _destroy_game(game)


func _create_game(player_color: String, black_buildup := 0.01, control_mode := ChessGame.ControlMode.PLAYER_VS_PLAYER) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var game := GAME.instantiate() as ChessGame
	game.control_mode = control_mode
	game.player_color = player_color
	game.player_presentation = _fast_profile(load("res://assets/player_army_presentation.tres"))
	game.opponent_presentation = _fast_profile(load("res://assets/opponent_army_presentation.tres"))
	var black_profile: ChessArmyPresentationProfile = game.player_presentation if player_color == "black" else game.opponent_presentation
	black_profile.king_presentation.activation_profile.buildup_duration = black_buildup
	viewport.add_child(game)
	await get_tree().process_frame
	var director: ChessBattleOpeningDirector = game.opening_director
	var adapter := game.get_node("ChessPresentationAdapter") as ChessPresentationAdapter
	var setup_concurrent := director.setup_sequences.size() == 2 and director.setup_sequences.all(func(sequence): return sequence.running)
	var black_setup_magic := adapter.get_king_magic_controller("black")
	var black_dormant_during_setup := black_setup_magic.activation_sequence != null and black_setup_magic.stone_sprite.visible and is_zero_approx(black_setup_magic.king.sprite.self_modulate.a) and is_zero_approx(black_setup_magic.king_aura.silhouette_power) and is_zero_approx(black_setup_magic.king_aura.particle_power)
	var observation := {"white_ran_without_black": false}
	var white_ready := {"value": false}
	game.white_activation_completed.connect(func(): white_ready.value = true, CONNECT_ONE_SHOT)
	await _wait_until(func():
		var white_magic := adapter.get_king_magic_controller("white")
		var black_magic := adapter.get_king_magic_controller("black")
		if director.stage == ChessBattleOpeningDirector.Stage.WHITE_ACTIVATION and white_magic != null and black_magic != null and not black_magic.running:
			observation.white_ran_without_black = true
		return white_ready.value
	, 5.0)
	return {"game": game, "adapter": adapter, "setup_concurrent": setup_concurrent, "black_dormant_during_setup": black_dormant_during_setup, "white_ran_without_black": observation.white_ran_without_black}


func _fast_profile(source: ChessArmyPresentationProfile) -> ChessArmyPresentationProfile:
	var result := source.duplicate(true) as ChessArmyPresentationProfile
	for motion in [result.setup_profile.left_motion, result.setup_profile.right_motion]:
		motion.pickup_delay = 0.001
		motion.entry_duration = 0.01
		motion.placement_hold = 0.001
		motion.release_hold = 0.001
		motion.retreat_duration = 0.01
	for cue in result.setup_profile.cues:
		cue.gap_before = 0.0
	var activation: ChessKingActivationProfile = result.king_presentation.activation_profile
	for property in ["approach_duration", "approach_settle_duration", "invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "aura_release_duration", "climax_hand_return_duration", "post_climax_retreat_delay", "retreat_duration", "resolve_duration"]:
		activation.set(property, 0.01)
	activation.buildup_crackle_times = PackedFloat32Array()
	activation.crackle_duration = 0.001
	return result


func _wait_until(predicate: Callable, timeout: float) -> void:
	while not predicate.call() and timeout > 0.0:
		await get_tree().process_frame
		timeout -= get_process_delta_time()


func _destroy_game(game: Node) -> void:
	var viewport := game.get_parent()
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: ", description)
