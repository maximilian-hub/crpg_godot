extends Node

const MAX_PLIES := 10


func _ready() -> void:
	var results := []
	results.append(await _play(&"dupre_white_vs_ryck", ChessCpuPlayer.BrainKind.DUPRE, ChessCpuPlayer.BrainKind.RYCK, 101))
	results.append(await _play(&"ryck_white_vs_dupre", ChessCpuPlayer.BrainKind.RYCK, ChessCpuPlayer.BrainKind.DUPRE, 101))
	results.append(await _play(&"dupre_white_vs_lemay", ChessCpuPlayer.BrainKind.DUPRE, ChessCpuPlayer.BrainKind.LEMAY, 211))
	results.append(await _play(&"lemay_white_vs_dupre", ChessCpuPlayer.BrainKind.LEMAY, ChessCpuPlayer.BrainKind.DUPRE, 211))
	print("DUPRE CONTROLLED GAMES: ", JSON.stringify(results))
	print("DUPRE CONTROLLED GAME CHARACTERIZATION: PASS")
	get_tree().quit(0)


func _play(label: StringName, white_brain: ChessCpuPlayer.BrainKind, black_brain: ChessCpuPlayer.BrainKind, seed_value: int) -> Dictionary:
	var model := _position()
	add_child(model)
	var white := _cpu(model, "white", white_brain, seed_value)
	var black := _cpu(model, "black", black_brain, seed_value)
	var position_keys := {}
	var reversals := 0
	var dupre_fallbacks := 0
	var actions := []
	var last_by_piece := {}
	for _ply in range(MAX_PLIES):
		if model.battle_over:
			break
		var cpu := white if model.current_turn == "white" else black
		var thought = await cpu.think()
		if thought == null:
			break
		if thought.brain_id == &"dupre" and bool(thought.search_profile.get("unverified_selection", false)):
			dupre_fallbacks += 1
		var record := {
			"color": thought.color,
			"piece": String(thought.piece_type_id),
			"from": str(thought.piece_coordinate),
			"to": str(thought.target),
			"brain": String(thought.brain_id),
		}
		var piece_key := "%s|%s" % [thought.color, thought.piece_type_id]
		var prior: Dictionary = last_by_piece.get(piece_key, {})
		if prior.get("from", Vector2i(-1, -1)) == thought.target and prior.get("to", Vector2i(-1, -1)) == thought.piece_coordinate and prior.get("piece", "") == String(thought.piece_type_id):
			reversals += 1
		last_by_piece[piece_key] = {"piece": String(thought.piece_type_id), "from": thought.piece_coordinate, "to": thought.target}
		actions.append(record)
		if not await cpu.execute_thought():
			break
		position_keys[ChessPositionCodec.to_json(model.capture_position())] = true
	var result := {
		"label": String(label),
		"plies": actions.size(),
		"winner": model.battle_result,
		"reversals": reversals,
		"dupre_unverified_selections": dupre_fallbacks,
		"unique_positions": position_keys.size(),
		"material_balance": _material(model, "white") - _material(model, "black"),
		"actions": actions,
	}
	white.queue_free()
	black.queue_free()
	model.free()
	await get_tree().process_frame
	return result


func _position() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null: model.unregister_piece(piece)
	model.board.clear()
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	for piece in [
		ClassicKing.new("white", Vector2i(7, 4)), Rook.new("white", Vector2i(7, 0)), Knight.new("white", Vector2i(7, 1)), Pawn.new("white", Vector2i(6, 0)), Pawn.new("white", Vector2i(6, 3)),
		ClassicKing.new("black", Vector2i(0, 4)), Rook.new("black", Vector2i(0, 0)), Knight.new("black", Vector2i(0, 1)), Pawn.new("black", Vector2i(1, 0)), Pawn.new("black", Vector2i(1, 3)),
	]: model.add_piece(piece, piece.coordinate)
	model.current_turn = "white"
	return model


func _cpu(model: ChessBoardModel, color: String, kind: ChessCpuPlayer.BrainKind, seed_value: int) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, color)
	cpu.set_brain(kind)
	cpu.set_random_seed(seed_value)
	return cpu


func _material(model: ChessBoardModel, color: String) -> int:
	var value := 0
	for row in model.board:
		for piece in row:
			if piece != null and piece.color == color and not piece.is_king:
				value += {"pawn": 1, "knight": 3, "bishop": 3, "rook": 5, "queen": 9}.get(piece.type, 1)
	return value
