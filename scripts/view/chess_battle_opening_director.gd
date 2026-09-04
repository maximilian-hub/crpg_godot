extends Node
class_name ChessBattleOpeningDirector

signal opening_completed()
signal white_activation_completed()
signal black_activation_started()

const HAND_RIG_SCENE := preload("res://scenes/player_hand_rig.tscn")

enum Stage { IDLE, SETUP, WHITE_ACTIVATION, AWAITING_BLACK_ACTIVATION, BLACK_ACTIVATION, COMPLETE }

var model: ChessBoardModel
var board: ChessBoardView
var adapter: ChessPresentationAdapter
var policy: ChessPresentationPolicy
var player_color := "white"
var player_profile: ChessArmyPresentationProfile
var opponent_profile: ChessArmyPresentationProfile
var is_running := false
var stage := Stage.IDLE

var is_pending: bool:
	get:
		return stage not in [Stage.IDLE, Stage.COMPLETE]

var setup_sequences: Array[ChessArmySetupSequence] = []
var temporary_hands: Array[ChessHandRig] = []
var permanent_hands: Array[ChessHandRig] = []
var _generation := 0
var _pending_setups := 0
var opening_seed := 0


func configure(
		battle_model: ChessBoardModel,
		board_view: ChessBoardView,
		presentation_adapter: ChessPresentationAdapter,
		presentation_policy: ChessPresentationPolicy,
		controlled_color: String,
		controlled_profile: ChessArmyPresentationProfile,
		enemy_profile: ChessArmyPresentationProfile
	) -> void:
	model = battle_model
	board = board_view
	adapter = presentation_adapter
	policy = presentation_policy
	player_color = "black" if controlled_color == "black" else "white"
	player_profile = controlled_profile
	opponent_profile = enemy_profile


func play() -> void:
	if stage == Stage.AWAITING_BLACK_ACTIVATION or stage == Stage.COMPLETE:
		return
	if is_running:
		await white_activation_completed
		return
	if not _can_present() or not policy.should_animate():
		finish_immediately()
		return
	_generation += 1
	if opening_seed == 0:
		opening_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	var token := _generation
	is_running = true
	stage = Stage.SETUP
	_hide_all_pieces()
	_build_setup_for_army(player_color, player_profile, token)
	_build_setup_for_army(model.get_other_color(player_color), opponent_profile, token)
	_prepare_dormant_kings()
	if setup_sequences.is_empty():
		_start_white_activation(token)
	else:
		_pending_setups = setup_sequences.size()
		for sequence in setup_sequences:
			sequence.play()
	await white_activation_completed


func play_black_activation() -> void:
	if stage != Stage.AWAITING_BLACK_ACTIVATION:
		return
	var token := _generation
	stage = Stage.BLACK_ACTIVATION
	is_running = true
	black_activation_started.emit()
	await _play_color_activation("black", _profile_for_color("black"), token)
	if token != _generation:
		return
	_complete(token)


func finish_immediately() -> void:
	var white_was_pending := stage in [Stage.IDLE, Stage.SETUP, Stage.WHITE_ACTIVATION]
	_generation += 1
	for sequence in setup_sequences:
		if is_instance_valid(sequence):
			sequence.restart(false)
	if adapter != null and model != null:
		for color in [player_color, model.get_other_color(player_color)]:
			var magic := adapter.get_king_magic_controller(color)
			if is_instance_valid(magic):
				magic.finish_activation_immediately()
	_reveal_all_pieces()
	_cleanup_hands_and_sequences()
	is_running = false
	stage = Stage.COMPLETE
	if white_was_pending:
		white_activation_completed.emit()
	opening_completed.emit()


func cancel() -> void:
	finish_immediately()


func _can_present() -> bool:
	return model != null and board != null and adapter != null and policy != null


func _prepare_dormant_kings() -> void:
	for color in ["white", "black"]:
		var magic := adapter.get_king_magic_controller(color)
		if is_instance_valid(magic):
			magic.prepare_for_activation()


func _build_setup_for_army(color: String, profile: ChessArmyPresentationProfile, token: int) -> void:
	if profile == null or profile.setup_profile == null:
		printerr("Opening presentation has no setup profile for ", color, ".")
		return
	var primary := board.get_hand_rig_for_color(color)
	if not is_instance_valid(primary):
		printerr("Opening presentation has no permanent hand for ", color, ".")
		return
	var companion := HAND_RIG_SCENE.instantiate() as ChessHandRig
	board.add_child(companion)
	temporary_hands.append(companion)
	permanent_hands.append(primary)
	var seat := ChessHandRig.Seat.NEAR if color == board.viewing_color else ChessHandRig.Seat.FAR
	var activating_left := profile.setup_profile.activating_hand == ChessArmySetupProfile.ActivatingHand.LEFT
	var left_hand := primary if activating_left else companion
	var right_hand := companion if activating_left else primary
	_configure_setup_hand(left_hand, profile.hand_style, seat, true)
	_configure_setup_hand(right_hand, profile.hand_style, seat, false)
	var sequence := ChessArmySetupSequence.new()
	add_child(sequence)
	setup_sequences.append(sequence)
	sequence.configure(profile.setup_profile.duplicate(true), board, left_hand, right_hand, _piece_views_by_coordinate(), seat, opening_seed ^ color.hash())
	sequence.set_playback_speed(1.0 / maxf(policy.duration_scale(), 0.01))
	sequence.setup_completed.connect(func(): _on_setup_completed(token), CONNECT_ONE_SHOT)


func _configure_setup_hand(hand: ChessHandRig, style: ChessHandStyle, seat: int, mirrored: bool) -> void:
	hand.seat = seat
	hand.set_hand_style(style)
	hand.set_visual_mirrored(mirrored)
	hand.set_board_sound_set(board.visual_style.interaction_sounds if board.visual_style != null else null)
	hand.visible = false


func _piece_views_by_coordinate() -> Dictionary:
	var result := {}
	for piece in adapter.piece_views:
		var piece_view: PieceView = adapter.piece_views[piece]
		if is_instance_valid(piece_view):
			result[piece.coordinate] = piece_view
	return result


func _on_setup_completed(token: int) -> void:
	if token != _generation or not is_running:
		return
	_pending_setups -= 1
	if _pending_setups <= 0:
		_start_white_activation(token)


func _start_white_activation(token: int) -> void:
	if token != _generation or not is_running:
		return
	_cleanup_hands_and_sequences()
	stage = Stage.WHITE_ACTIVATION
	await _play_color_activation("white", _profile_for_color("white"), token)
	if token != _generation:
		return
	is_running = false
	stage = Stage.AWAITING_BLACK_ACTIVATION
	white_activation_completed.emit()


func _play_color_activation(color: String, profile: ChessArmyPresentationProfile, token: int) -> void:
	var magic := adapter.get_king_magic_controller(color)
	if not is_instance_valid(magic) or not is_instance_valid(magic.hand) or not magic.hand.can_animate():
		printerr("Opening presentation has no King activation controller for ", color, ".")
		return
	var activating_left := profile != null and profile.setup_profile != null and profile.setup_profile.activating_hand == ChessArmySetupProfile.ActivatingHand.LEFT
	magic.hand.set_visual_mirrored(activating_left)
	await magic.play_activation(1.0 / maxf(policy.duration_scale(), 0.01))
	if token == _generation and is_instance_valid(magic.hand):
		magic.hand.set_visual_mirrored(false)


func _profile_for_color(color: String) -> ChessArmyPresentationProfile:
	return player_profile if color == player_color else opponent_profile


func _complete(token: int) -> void:
	if token != _generation:
		return
	_reveal_all_pieces()
	_cleanup_hands_and_sequences()
	is_running = false
	stage = Stage.COMPLETE
	opening_completed.emit()


func _hide_all_pieces() -> void:
	for piece_view in adapter.piece_views.values():
		if is_instance_valid(piece_view):
			piece_view.visible = false


func _reveal_all_pieces() -> void:
	if adapter == null:
		return
	for piece_view in adapter.piece_views.values():
		if is_instance_valid(piece_view):
			piece_view.visible = true


func _cleanup_hands_and_sequences() -> void:
	for hand in permanent_hands:
		if is_instance_valid(hand):
			hand.cancel_setup_placement()
			hand.set_visual_mirrored(false)
	for hand in temporary_hands:
		if is_instance_valid(hand):
			hand.cancel_setup_placement()
			hand.queue_free()
	for sequence in setup_sequences:
		if is_instance_valid(sequence):
			sequence.queue_free()
	permanent_hands.clear()
	temporary_hands.clear()
	setup_sequences.clear()
	_pending_setups = 0
