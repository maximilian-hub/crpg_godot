extends RefCounted
class_name ChessPositionEditor

static func place_piece(source: ChessPosition, piece: ChessPieceState) -> Dictionary:
	var next := source.copy()
	_remove_at(next, piece.coordinate)
	next.pieces.append(piece.copy())
	_reset_derived_state(next)
	return _result(next)

static func move_piece(source: ChessPosition, from: Vector2i, to: Vector2i) -> Dictionary:
	var next := source.copy()
	var moving := _find_at(next, from)
	if moving == null:
		return {"position": null, "errors": ["No piece at %s." % from]}
	_remove_at(next, to)
	moving.coordinate = to
	_reset_derived_state(next)
	return _result(next)

static func remove_piece(source: ChessPosition, at: Vector2i) -> Dictionary:
	var next := source.copy()
	if _find_at(next, at) == null:
		return {"position": null, "errors": ["No piece at %s." % at]}
	_remove_at(next, at)
	_reset_derived_state(next)
	return _result(next)

static func clear_board(source: ChessPosition) -> Dictionary:
	var next := source.copy()
	next.pieces.clear()
	_reset_derived_state(next)
	return _result(next)

static func set_current_turn(source: ChessPosition, color: String) -> Dictionary:
	var next := source.copy()
	next.current_turn = color
	_reset_derived_state(next)
	return _result(next)

static func update_piece_state(source: ChessPosition, at: Vector2i, values: Dictionary) -> Dictionary:
	var next := source.copy()
	var piece := _find_at(next, at)
	if piece == null:
		return {"position": null, "errors": ["No piece at %s." % at]}
	for property in ["max_hp", "current_hp", "attack_power", "has_moved", "stunned", "stun_timer", "current_cooldown"]:
		if values.has(property):
			piece.set(property, values[property])
	_reset_derived_state(next)
	return _result(next)

static func _find_at(position: ChessPosition, at: Vector2i) -> ChessPieceState:
	for piece in position.pieces:
		if piece.coordinate == at:
			return piece
	return null

static func _remove_at(position: ChessPosition, at: Vector2i) -> void:
	for index in range(position.pieces.size() - 1, -1, -1):
		if position.pieces[index].coordinate == at:
			position.pieces.remove_at(index)

static func _reset_derived_state(position: ChessPosition) -> void:
	position.last_move = ChessLastMoveState.new()
	position.battle_over = false
	position.battle_result = ""
	position.defeated_king_colors.clear()

static func _result(position: ChessPosition) -> Dictionary:
	var report := ChessPositionValidator.validate(position)
	return {"position": position if report.is_structurally_valid() else null, "errors": report.structural_errors}
