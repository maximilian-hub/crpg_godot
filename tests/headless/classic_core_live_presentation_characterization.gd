extends Node

const GAME_SCENE := preload("res://scenes/chess_game.tscn")
var failures: Array[String] = []
var checks := 0
var game: ChessGame
var model: ChessBoardModel
var adapter: ChessPresentationAdapter


func _ready() -> void:
	game = GAME_SCENE.instantiate()
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	game.play_opening_presentation = false
	game.apply_initial_piece_placement_variation = false
	add_child(game)
	await get_tree().process_frame
	model = game.model
	adapter = game.get_node("ChessPresentationAdapter")
	adapter.presentation_policy.speed = ChessPresentationPolicy.Speed.INSTANT
	await _test_move_and_capture()
	await _test_castle()
	await _test_promotion()
	await _test_arakne_presentation()
	await _test_necromancer_presentation()
	await _test_minotaur_presentation()
	await _test_quarterly_presentation()
	if failures.is_empty():
		print("CLASSIC CORE LIVE PRESENTATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("CLASSIC CORE LIVE PRESENTATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_move_and_capture() -> void:
	_load([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4)), Pawn.new("black", Vector2i(4, 1))])
	var rook := model.board[4][4] as ModelPiece
	var victim := model.board[4][1] as ModelPiece
	_expect(await model.submit_move(rook, Vector2i(4, 2)), "presented core quiet move completes")
	_expect(is_instance_valid(adapter.get_piece_view(rook)) and model.board[4][2] == rook, "quiet presentation retains mover view identity")
	model.current_turn = "white"; model._classic_core_bridge.state.current_turn = "white"
	_expect(await model.submit_move(rook, Vector2i(4, 1)), "presented core capture completes")
	_expect(model.board[4][1] == rook and not adapter.piece_views.has(victim), "capture presentation removes defender mapping")


func _test_castle() -> void:
	_load([ClassicKing.new("white", Vector2i(7, 4)), Rook.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	var king := model.board[7][4] as ModelPiece
	var rook := model.board[7][7] as ModelPiece
	_expect(await model.submit_move(king, Vector2i(7, 6)), "presented core castle completes")
	_expect(model.board[7][6] == king and model.board[7][5] == rook and is_instance_valid(adapter.get_piece_view(king)) and is_instance_valid(adapter.get_piece_view(rook)), "castling presentation preserves both visual identities")


func _test_promotion() -> void:
	_load([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("white", Vector2i(1, 0))])
	var pawn := model.board[1][0] as ModelPiece
	model.promotion_selection_requested.connect(func(_piece, _options): model.call_deferred("submit_promotion_selection", &"knight"), CONNECT_ONE_SHOT)
	_expect(await model.submit_move(pawn, Vector2i(0, 0)), "presented core promotion completes")
	var promoted := model.board[0][0] as ModelPiece
	_expect(promoted is Knight and is_instance_valid(adapter.get_piece_view(promoted)) and not adapter.piece_views.has(pawn), "promotion presentation replaces the visual mapping")


func _test_arakne_presentation() -> void:
	var source := ArakneKing.new("white", Vector2i(4, 4)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	_load([source, ClassicKing.new("black", Vector2i(0, 7))])
	var arakne := model.board[4][4] as ArakneKing
	var view := adapter.get_piece_view(arakne)
	_expect(await model.submit_move_path(arakne, [Vector2i(4, 5), Vector2i(3, 6)]), "presented core Skitter completes")
	_expect(model.board[3][6] == arakne and adapter.get_piece_view(arakne) == view, "Skitter preserves Arakne's visual identity across both landings")

	source = ArakneKing.new("white", Vector2i(4, 4)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(4, 5)); target.max_hp = 2; target.current_hp = 2
	_load([source, ClassicKing.new("black", Vector2i(0, 7)), target])
	arakne = model.board[4][4] as ArakneKing
	var live_target := model.board[4][5] as ModelPiece
	_expect(await model.submit_active_ability(arakne, live_target.coordinate), "presented core Spike Burst completes")
	_expect(live_target.current_hp == 1 and is_instance_valid(adapter.get_piece_view(live_target)) and arakne.cooldown_reset_pending, "Spike Burst preserves its target view, damage, and scheduled cooldown presentation")

	source = ArakneKing.new("white", Vector2i(4, 4)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	_load([source, ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(4, 5))])
	arakne = model.board[4][4] as ArakneKing
	live_target = model.board[4][5] as ModelPiece
	_expect(await model.submit_active_ability(arakne, live_target.coordinate), "presented lethal Spike Burst completes")
	_expect(model.board[4][5] == null and not adapter.piece_views.has(live_target), "lethal Spike Burst removes the ordinary target's visual mapping")

	source = ArakneKing.new("white", Vector2i(4, 4)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	_load([source, ClassicKing.new("black", Vector2i(3, 3))])
	arakne = model.board[4][4] as ArakneKing
	_expect(await model.submit_active_ability(arakne, Vector2i(3, 3)), "presented King-lethal Spike Burst completes")
	_expect(model.battle_over and model.battle_result == "white" and model.is_settled(), "King-lethal Spike Burst completes the existing battle presentation lifecycle")


func _test_necromancer_presentation() -> void:
	var source := NecromancerKing.new("white", Vector2i(7, 4)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	_load([source, ClassicKing.new("black", Vector2i(0, 4)), Pawn.new("white", Vector2i(5, 0))])
	var necromancer := model.board[7][4] as NecromancerKing
	_expect(await model.submit_active_ability(necromancer, Vector2i(6, 3)), "presented core Bone Pawn summon completes")
	var summoned := model.board[6][3] as ModelPiece
	_expect(summoned is BonePawn and is_instance_valid(adapter.get_piece_view(summoned)) and necromancer.cooldown_reset_pending, "active summon retains its portal-backed visual mapping and cooldown")

	var black_necro := NecromancerKing.new("black", Vector2i(0, 7)); black_necro.set_cooldown(0); black_necro.initial_cooldown_turn_pending = false
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(4, 3))
	_load([ClassicKing.new("white", Vector2i(7, 7)), rook, black_necro, bishop])
	var live_rook := model.board[4][0] as Rook
	_expect(await model.submit_move(live_rook, Vector2i(4, 3)) and model.has_pending_reaction(), "presented core capture reveals Raise Dead selection")
	var target: Vector2i = model.get_pending_reaction().targets[0]
	_expect(await model.submit_reaction_selection(target), "presented core Raise Dead choice completes")
	summoned = model.board[target.x][target.y] as ModelPiece
	_expect(summoned is BonePawn and is_instance_valid(adapter.get_piece_view(summoned)) and model.is_settled(), "Raise Dead preserves aura/portal presentation and the summoned visual mapping")


func _test_minotaur_presentation() -> void:
	var source := MinotaurKing.new("white", Vector2i(4, 0)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	var target := MinotaurKing.new("black", Vector2i(4, 4)); target.stunned = true; target.stun_timer = 20
	_load([source, target])
	var minotaur := model.board[4][0] as MinotaurKing
	var target_view := adapter.get_piece_view(model.board[4][4])
	_expect(await model.submit_active_ability(minotaur, Vector2i(4, 4)), "presented durable Charge completes")
	_expect(model.board[4][3] == minotaur and model.board[4][4].current_hp == 2 and adapter.get_piece_view(model.board[4][4]) == target_view, "durable Charge presents adjacent landing and retains the damaged target view")

	var rook := Rook.new("white", Vector2i(4, 0))
	var victim := Bishop.new("white", Vector2i(3, 3))
	var defender := MinotaurKing.new("black", Vector2i(4, 4))
	_load([ClassicKing.new("white", Vector2i(7, 7)), rook, victim, defender])
	var live_victim := model.board[3][3] as ModelPiece
	_expect(await model.submit_move(model.board[4][0], Vector2i(4, 4)), "presented automatic Rage completes")
	_expect(not adapter.piece_views.has(live_victim) and model.board[3][3] == null and model.is_settled(), "Rage presentation removes destroyed adjacent-piece visuals and settles")


func _test_quarterly_presentation() -> void:
	var source := QuarterlyInitiativeKing.new("white", Vector2i(7, 7)); source.set_cooldown(0); source.initial_cooldown_turn_pending = false
	_load([source, Rook.new("white", Vector2i(5, 5)), ClassicKing.new("black", Vector2i(0, 0))])
	var quarterly := model.board[7][7] as QuarterlyInitiativeKing
	var rook := model.board[5][5] as Rook
	var view := adapter.get_piece_view(rook)
	model.movement_type_selection_requested.connect(func(_king, _target, _options): model.call_deferred("submit_movement_type_grant", &"bishop"), CONNECT_ONE_SHOT)
	_expect(await model.submit_active_ability(quarterly, rook.coordinate), "presented core Stakeholder Pandering completes")
	_expect(&"bishop" in rook.granted_movement_types and adapter.get_piece_view(rook) == view and quarterly.current_hp == 3, "Quarterly grant preserves recipient view identity, movement badge state, and HP presentation")


func _load(pieces: Array) -> void:
	var position := ChessPosition.new()
	position.current_turn = "white"
	for piece in pieces: position.pieces.append(piece.capture_piece_state())
	model.load_position(position)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "presentation fixture activates core authority")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
