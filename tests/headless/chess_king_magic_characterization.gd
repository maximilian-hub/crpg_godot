extends Node

const GAME := preload("res://scenes/chess_game.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var game := GAME.instantiate() as ChessGame
	game.play_opening_presentation = false
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	game.opponent_presentation = preload("res://assets/opponent_army_presentation.tres")
	viewport.add_child(game)
	await get_tree().process_frame
	var model: ChessBoardModel = game.model
	var adapter: ChessPresentationAdapter = game.get_node("ChessPresentationAdapter")
	var view: ChessBoardView = game.get_node("CanvasLayer/ChessBoard")
	var white_king: KingPiece = model.get_king("white")
	var black_king: KingPiece = model.get_king("black")
	var white_magic: ChessKingMagicController = adapter.king_magic_controllers[white_king]
	var black_magic: ChessKingMagicController = adapter.king_magic_controllers[black_king]
	_make_fast(white_magic)
	_make_fast(black_magic)

	_check(white_magic.hand.seat == ChessHandRig.Seat.NEAR and black_magic.hand.seat == ChessHandRig.Seat.FAR, "army magic resolves the hand rig for each displayed seat")
	var authored := Vector2(150, -180)
	_check(ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.NEAR) == authored and ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.FAR) == -authored, "far hover occupies the opposite side of its king")
	_check(ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.NEAR, true) == Vector2(-150, -180) and ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.FAR, true) == Vector2(150, 180), "left-hand activation combines hand mirroring with the far-seat half turn")

	var grabbed_kings: Array[Node2D] = []
	view.near_hand_rig.piece_grabbed.connect(func(piece: Node2D):
		if piece.model is KingPiece: grabbed_kings.append(piece))
	var white_view := adapter.get_piece_view(white_king) as PieceView
	var destination := Vector2i(5, 4)
	await white_magic.play_move(white_king.coordinate, destination)
	_check(grabbed_kings.is_empty() and white_view.get_parent() == view.get_node("Pieces"), "magical movement never reparents or grasps the king")
	_check(white_view.coordinate == destination and white_view.position == view.grid_to_screen(destination.x, destination.y), "magical movement settles on the exact projected ground anchor")

	var defender := adapter.get_piece_view(model.board[1][0]) as PieceView
	var defender_start := defender.position
	white_view.position = view.grid_to_screen(4, 0)
	await white_magic.play_capture(Vector2i(4, 0), Vector2i(3, 1), defender)
	_check(defender.position.x > view.get_viewport_rect().size.x and defender.rotation > 0.0, "rightward king impact spins and arcs the defender beyond the right edge")
	defender.position = defender_start
	defender.rotation = 0.0
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 44
	var first := ChessKingMagicController.knockoff_side(Vector2.ZERO, Vector2(0, 100), seeded)
	seeded.seed = 44
	_check(first in [-1, 1] and first == ChessKingMagicController.knockoff_side(Vector2.ZERO, Vector2(0, 100), seeded), "direct vertical impacts choose a seedable random left/right arc")

	var attack_origin := white_view.position
	var attack_observation := {"contacts": 0}
	await white_magic.play_attack(Vector2i(3, 1), Vector2i(2, 2), func(): attack_observation["contacts"] += 1)
	_check(attack_observation["contacts"] == 1, "nonlethal magical lunge applies one contact callback")
	_check(white_view.position.is_equal_approx(attack_origin), "nonlethal magical lunge rebounds exactly home")

	_make_activation_fast(black_magic)
	await black_magic.play_activation()
	_check(not black_magic.hand.visible and black_magic.hand.position == black_magic.activation_sequence.hand_rest_position, "far-seat full activation uses its transformed hover and returns offscreen")
	_check(is_equal_approx(black_magic.king_aura.silhouette_power, black_magic.profile.activation_profile.resting_aura_power), "full activation retains the configured resting king silhouette")

	viewport.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("CHESS KING MAGIC CHARACTERIZATION: PASS (%d checks)" % checks)
	else:
		print("CHESS KING MAGIC CHARACTERIZATION: FAIL (%d failures)" % failures.size())
		for failure in failures: print(" - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _make_fast(magic: ChessKingMagicController) -> void:
	magic.profile = magic.profile.duplicate(true)
	var move: Resource = magic.profile.movement_profile
	for property in ["hand_approach_duration", "invocation_duration", "settle_duration", "hand_retreat_duration", "travel_duration", "attack_rebound_duration", "knockoff_duration"]:
		move.set(property, 0.01)


func _make_activation_fast(magic: ChessKingMagicController) -> void:
	var activation: Resource = magic.profile.activation_profile
	for property in ["approach_duration", "approach_settle_duration", "invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "aura_release_duration", "resolve_duration", "climax_hand_return_duration", "post_climax_retreat_delay", "retreat_duration"]:
		activation.set(property, 0.01)
	activation.buildup_crackle_times = PackedFloat32Array()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
