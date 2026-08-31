extends Node
class_name ChessBattleOpeningDirector

signal opening_completed()

const HAND_RIG_SCENE := preload("res://scenes/player_hand_rig.tscn")

var model: ChessBoardModel
var board: ChessBoardView
var adapter: ChessPresentationAdapter
var policy: ChessPresentationPolicy
var player_color := "white"
var player_profile: ChessArmyPresentationProfile
var opponent_profile: ChessArmyPresentationProfile
var is_running := false

var setup_sequences: Array[ChessArmySetupSequence] = []
var temporary_hands: Array[ChessHandRig] = []
var permanent_hands: Array[ChessHandRig] = []
var _generation := 0
var _pending_setups := 0
var _pending_activations := 0


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
	if is_running:
		await opening_completed
		return
	if not _can_present() or not policy.should_animate():
		finish_immediately()
		return
	_generation += 1
	var token := _generation
	is_running = true
	_hide_all_pieces()
	_build_setup_for_army(player_color, player_profile, token)
	_build_setup_for_army(model.get_other_color(player_color), opponent_profile, token)
	if setup_sequences.is_empty():
		_start_activations(token)
	else:
		_pending_setups = setup_sequences.size()
		for sequence in setup_sequences:
			sequence.play()
	await opening_completed


func finish_immediately() -> void:
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
	opening_completed.emit()


func cancel() -> void:
	finish_immediately()


func _can_present() -> bool:
	return model != null and board != null and adapter != null and policy != null


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
	sequence.configure(profile.setup_profile.duplicate(true), board, left_hand, right_hand, _piece_views_by_coordinate(), seat)
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
		_start_activations(token)


func _start_activations(token: int) -> void:
	if token != _generation or not is_running:
		return
	var controllers: Array[ChessKingMagicController] = []
	for color in [player_color, model.get_other_color(player_color)]:
		var magic := adapter.get_king_magic_controller(color)
		if is_instance_valid(magic) and is_instance_valid(magic.hand) and magic.hand.can_animate():
			controllers.append(magic)
		else:
			printerr("Opening presentation has no King activation controller for ", color, ".")
	if controllers.is_empty():
		_complete(token)
		return
	_pending_activations = controllers.size()
	var playback_speed := 1.0 / maxf(policy.duration_scale(), 0.01)
	for magic in controllers:
		_run_activation(magic, playback_speed, token)


func _run_activation(magic: ChessKingMagicController, playback_speed: float, token: int) -> void:
	await magic.play_activation(playback_speed)
	if token != _generation or not is_running:
		return
	_pending_activations -= 1
	if _pending_activations <= 0:
		_complete(token)


func _complete(token: int) -> void:
	if token != _generation:
		return
	_reveal_all_pieces()
	_cleanup_hands_and_sequences()
	is_running = false
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
	_pending_activations = 0
