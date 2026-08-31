extends Node

const GAME := preload("res://scenes/chess_game.tscn")

var failures := 0
var checks := 0


func _ready() -> void:
	await _test_concurrent_opening("white")
	await _test_concurrent_opening("black")
	await _test_cancellation()
	await _test_instant_bypass()
	if failures == 0:
		print("CHESS BATTLE OPENING CHARACTERIZATION: PASS (%d checks)" % checks)
	else:
		printerr("CHESS BATTLE OPENING CHARACTERIZATION: FAIL (%d/%d)" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_concurrent_opening(player_color: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var game := GAME.instantiate() as ChessGame
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_CPU
	game.player_color = player_color
	game.player_presentation = _fast_profile(load("res://assets/player_army_presentation.tres"))
	game.opponent_presentation = _fast_profile(load("res://assets/opponent_army_presentation.tres"))
	var completion := {"emitted": false, "input_locked": true, "cpu_enabled": false, "hands_ready": false}
	game.opening_completed.connect(func():
		completion.emitted = true
		completion.input_locked = game.controller.is_input_locked
		completion.cpu_enabled = game.white_cpu_player.is_enabled or game.black_cpu_player.is_enabled
		var completed_board := game.get_node("CanvasLayer/ChessBoard") as ChessBoardView
		completion.hands_ready = not completed_board.near_hand_rig.visual_mirrored and not completed_board.far_hand_rig.visual_mirrored and not completed_board.near_hand_rig.visible and not completed_board.far_hand_rig.visible
	)
	viewport.add_child(game)
	await get_tree().process_frame
	var director: ChessBattleOpeningDirector = game.opening_director
	var adapter: ChessPresentationAdapter = game.get_node("ChessPresentationAdapter")
	var board: ChessBoardView = game.get_node("CanvasLayer/ChessBoard")
	_check(director != null and director.is_running and game.controller.is_input_locked, "%s opening begins with its director running and input locked" % player_color)
	_check(not game.white_cpu_player.is_enabled and not game.black_cpu_player.is_enabled, "%s opening keeps both automatic players disabled" % player_color)
	_check(director.setup_sequences.size() == 2 and director.setup_sequences.all(func(sequence): return sequence.running), "%s opening runs both army setup sequences concurrently" % player_color)
	_check(director.temporary_hands.size() == 2 and director.permanent_hands.size() == 2, "%s opening supplies one temporary companion hand to each permanent army hand" % player_color)
	var seats := director.setup_sequences.map(func(sequence): return sequence.seat)
	_check(ChessHandRig.Seat.NEAR in seats and ChessHandRig.Seat.FAR in seats, "%s opening transforms one setup for each board seat" % player_color)
	_check(adapter.piece_views.values().any(func(piece): return not piece.visible), "%s opening does not expose the already-complete initial board" % player_color)

	var saw_concurrent_activation := false
	var timeout := 5.0
	while not completion.emitted and timeout > 0.0:
		var white_magic := adapter.get_king_magic_controller("white")
		var black_magic := adapter.get_king_magic_controller("black")
		if white_magic != null and black_magic != null and white_magic.running and black_magic.running:
			saw_concurrent_activation = true
		await get_tree().process_frame
		timeout -= get_process_delta_time()
	_check(timeout > 0.0 and saw_concurrent_activation, "%s opening starts both King activations concurrently after setup" % player_color)
	_check(adapter.piece_views.values().all(func(piece): return piece.visible), "%s opening finishes with every current piece visible" % player_color)
	_check(director.temporary_hands.is_empty() and director.setup_sequences.is_empty(), "%s opening removes its temporary hands and setup sequences" % player_color)
	_check(completion.hands_ready, "%s opening restores both permanent gameplay hands before gameplay resumes" % player_color)
	_check(not completion.input_locked and completion.cpu_enabled, "%s opening unlocks gameplay and starts the configured opponent CPU" % player_color)
	var white_magic := adapter.get_king_magic_controller("white")
	var black_magic := adapter.get_king_magic_controller("black")
	_check(white_magic.king_aura.silhouette_power > 0.0 and black_magic.king_aura.silhouette_power > 0.0, "%s opening leaves both Kings at their persistent resting Aura" % player_color)
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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
	_check(not game.opening_in_progress and adapter.piece_views.values().all(func(piece): return piece.visible), "Instant presentation bypasses the opening on a complete visible board")
	_check(not game.controller.is_input_locked and game.opening_director.temporary_hands.is_empty(), "Instant presentation leaves no opening lock or temporary hands")
	viewport.queue_free()
	await get_tree().process_frame


func _test_cancellation() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var game := GAME.instantiate() as ChessGame
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	game.player_presentation = _fast_profile(load("res://assets/player_army_presentation.tres"))
	game.opponent_presentation = _fast_profile(load("res://assets/opponent_army_presentation.tres"))
	for profile in [game.player_presentation, game.opponent_presentation]:
		profile.king_presentation.activation_profile.buildup_duration = 2.0
	viewport.add_child(game)
	await get_tree().process_frame
	var adapter := game.get_node("ChessPresentationAdapter") as ChessPresentationAdapter
	var timeout := 3.0
	while timeout > 0.0:
		var white_magic := adapter.get_king_magic_controller("white")
		var black_magic := adapter.get_king_magic_controller("black")
		if white_magic.running and black_magic.running:
			break
		await get_tree().process_frame
		timeout -= get_process_delta_time()
	game.opening_director.cancel()
	await get_tree().process_frame
	_check(not game.opening_in_progress and adapter.piece_views.values().all(func(piece): return piece.visible), "Cancelling during activation completes onto a visible board")
	_check(game.opening_director.temporary_hands.is_empty() and not game.controller.is_input_locked, "Opening cancellation cleans temporary state and releases the startup gate")
	for color in ["white", "black"]:
		var magic := adapter.get_king_magic_controller(color)
		_check(not magic.running and magic.king_aura.silhouette_power > 0.0, "Opening cancellation resolves the %s King to its resting Aura" % color)
	viewport.queue_free()
	await get_tree().process_frame


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


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: ", description)
