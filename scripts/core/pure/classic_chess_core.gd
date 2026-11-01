extends RefCounted
class_name ClassicChessCore

const SUPPORTED_TYPES: Array[StringName] = [&"pawn", &"knight", &"bishop", &"rook", &"queen", &"classic_king"]
const PROMOTION_OPTIONS: Array[StringName] = [&"queen", &"rook", &"bishop", &"knight"]
const MAX_CONSECUTIVE_FORCED_PASSES := 6


static func import_position(position: ChessPosition) -> Dictionary:
	if position == null:
		return {"ok": false, "error": "Position is null."}
	if position.board_size != Vector2i(8, 8) or position.board_type != &"default":
		return {"ok": false, "error": "Only the default 8x8 board is supported."}
	if not position.tile_effects.is_empty() or not position.autonomous_entities.is_empty():
		return {"ok": false, "error": "Tile effects and autonomous entities are outside the Classic slice."}
	if int(position.lunacy_by_color.get("white", 0)) != 0 or int(position.lunacy_by_color.get("black", 0)) != 0 or int(position.socratic_turns_by_color.get("white", 0)) != 0 or int(position.socratic_turns_by_color.get("black", 0)) != 0:
		return {"ok": false, "error": "Rhetorician state is outside the Classic slice."}
	var state := ChessCoreState.new()
	state.board_size = position.board_size
	state.board_type = position.board_type
	state.current_turn = position.current_turn
	state.battle_over = position.battle_over
	state.battle_result = position.battle_result
	state.defeated_king_colors.assign(position.defeated_king_colors)
	state.random_states = position.random_states.duplicate(true)
	state.global_turn_number = position.global_turn_number
	var occupied := {}
	for source in position.pieces:
		var type_id := ChessPieceCatalog.normalize_type_id(source.type_id)
		if type_id not in SUPPORTED_TYPES:
			return {"ok": false, "error": "Unsupported Classic piece type: %s" % source.type_id}
		if not source.granted_movement_types.is_empty() or not source.custom_state.is_empty():
			return {"ok": false, "error": "RPG piece modifiers are outside the Classic slice."}
		if source.current_cooldown != 0 or source.cooldown_reset_pending:
			return {"ok": false, "error": "Active-ability cooldown state is outside the Classic slice."}
		if source.coordinate.x < 0 or source.coordinate.y < 0 or source.coordinate.x >= 8 or source.coordinate.y >= 8 or occupied.has(source.coordinate):
			return {"ok": false, "error": "Piece coordinates are invalid or overlapping."}
		var piece := ChessCorePiece.from_piece_state(source)
		if piece.piece_id.is_empty(): piece.piece_id = state.allocate_piece_id()
		_reserve_id(state, piece.piece_id)
		state.add_piece(piece)
		occupied[piece.coordinate] = true
	if position.last_move != null and position.last_move.is_present:
		var moved_id := ""
		var candidate := state.occupant(position.last_move.to)
		if candidate != null and candidate.color == position.last_move.piece_color and candidate.type_id == ChessPieceCatalog.normalize_type_id(position.last_move.piece_type_id):
			moved_id = candidate.piece_id
		state.last_move = {
			"piece_id": moved_id,
			"piece_type": ChessPieceCatalog.normalize_type_id(position.last_move.piece_type_id),
			"piece_color": position.last_move.piece_color,
			"from": position.last_move.from,
			"to": position.last_move.to,
		}
	return {"ok": true, "state": state, "error": ""}


static func export_position(state: ChessCoreState) -> ChessPosition:
	if state == null or state.pending_choice != null:
		return null
	var result := ChessPosition.new()
	result.board_size = state.board_size
	result.board_type = state.board_type
	result.current_turn = state.current_turn
	result.battle_over = state.battle_over
	result.battle_result = state.battle_result
	result.defeated_king_colors.assign(state.defeated_king_colors)
	result.random_states = state.random_states.duplicate(true)
	result.global_turn_number = state.global_turn_number
	for piece in state.pieces: result.pieces.append(piece.to_piece_state())
	if not state.last_move.is_empty():
		result.last_move.is_present = true
		result.last_move.from = state.last_move.get("from", Vector2i.ZERO)
		result.last_move.to = state.last_move.get("to", Vector2i.ZERO)
		result.last_move.piece_type_id = state.last_move.get("piece_type", &"")
		result.last_move.piece_color = state.last_move.get("piece_color", "")
	return result


static func legal_actions(state: ChessCoreState, color: String) -> Array[ChessCoreAction]:
	var result: Array[ChessCoreAction] = []
	if state == null or state.battle_over or state.pending_choice != null or color != state.current_turn:
		return result
	var ordered := state.pieces.duplicate()
	ordered.sort_custom(func(a: ChessCorePiece, b: ChessCorePiece):
		if a.coordinate.x != b.coordinate.x: return a.coordinate.x < b.coordinate.x
		return a.coordinate.y < b.coordinate.y
	)
	for piece: ChessCorePiece in ordered:
		if piece.color != color or piece.stunned or piece.current_hp <= 0:
			continue
		for target in _legal_destinations(state, piece):
			var action := ChessCoreAction.new()
			action.piece_id = piece.piece_id
			action.color = piece.color
			action.from = piece.coordinate
			action.target = target
			action.path = [target]
			result.append(action)
	return result


static func resolve_action(source: ChessCoreState, submitted: ChessCoreAction) -> ChessCoreStepResult:
	if source == null or submitted == null:
		return ChessCoreStepResult.rejected(source, "State and action are required.")
	var matched: ChessCoreAction
	for action in legal_actions(source, source.current_turn):
		if action.key() == submitted.key():
			matched = action
			break
	if matched == null:
		return ChessCoreStepResult.rejected(source, "Action is not legal in this state.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	result.events.append(_event(&"action_started", {"color": state.current_turn}))
	state.consecutive_forced_passes = 0
	var piece := state.piece_by_id(matched.piece_id)
	var origin := piece.coordinate
	var target_piece := state.occupant(matched.target)
	var is_en_passant := piece.type_id == &"pawn" and target_piece == null and origin.y != matched.target.y and _en_passant_victim(state, piece, matched.target) != null
	var is_castle := piece.type_id == &"classic_king" and absi(matched.target.y - origin.y) == 2
	if is_castle:
		_resolve_castle(state, piece, matched.target, result.events)
	elif is_en_passant:
		var victim := _en_passant_victim(state, piece, matched.target)
		_commit_capture(state, piece, victim, matched.target, victim.coordinate, result.events)
	elif target_piece != null:
		if target_piece.current_hp <= piece.attack_power:
			_commit_capture(state, piece, target_piece, matched.target, matched.target, result.events)
		else:
			target_piece.current_hp -= piece.attack_power
			result.events.append(_event(&"piece_damaged", {"piece_id": target_piece.piece_id, "amount": piece.attack_power, "current_hp": target_piece.current_hp, "max_hp": target_piece.max_hp}))
	else:
		state.move_piece(piece, matched.target)
		piece.has_moved = true
		result.events.append(_event(&"piece_moved", {"piece_id": piece.piece_id, "from": origin, "to": matched.target}))
		result.events.append(_event(&"piece_landed", {"piece_id": piece.piece_id, "from": origin, "to": matched.target}))
	state.last_move = {"piece_id": piece.piece_id, "piece_type": piece.type_id, "piece_color": piece.color, "from": origin, "to": matched.target}
	if not state.defeated_king_colors.is_empty():
		_complete_battle(state, result.events)
		result.status = ChessCoreStepResult.Status.COMPLETED
		return result
	if piece.type_id == &"pawn" and piece.coordinate.x == (0 if piece.color == "white" else 7):
		var choice := ChessCoreChoice.new()
		choice.kind = &"promotion"
		choice.piece_id = piece.piece_id
		choice.options.assign(PROMOTION_OPTIONS)
		state.pending_choice = choice
		state.resolution_context = {"action_owner": piece.color}
		result.choice = choice.copy()
		result.events.append(_event(&"choice_requested", {"kind": &"promotion", "piece_id": piece.piece_id, "options": Array(PROMOTION_OPTIONS)}))
		result.status = ChessCoreStepResult.Status.PENDING_CHOICE
		return result
	_finish_action(state, result.events)
	result.status = ChessCoreStepResult.Status.COMPLETED
	return result


static func resolve_choice(source: ChessCoreState, option: StringName) -> ChessCoreStepResult:
	if source == null or source.pending_choice == null or source.pending_choice.kind != &"promotion":
		return ChessCoreStepResult.rejected(source, "No promotion choice is pending.")
	if option not in source.pending_choice.options:
		return ChessCoreStepResult.rejected(source, "Promotion choice is invalid.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	var pawn := state.piece_by_id(state.pending_choice.piece_id)
	if pawn == null or pawn.type_id != &"pawn":
		return ChessCoreStepResult.rejected(source, "The promoting pawn is no longer present.")
	var old_id := pawn.piece_id
	var coordinate := pawn.coordinate
	var color := pawn.color
	state.remove_piece(pawn)
	var promoted := ChessCorePiece.new()
	promoted.type_id = option
	promoted.piece_id = state.allocate_piece_id()
	promoted.color = color
	promoted.coordinate = coordinate
	promoted.has_moved = true
	state.add_piece(promoted)
	state.pending_choice = null
	state.resolution_context.clear()
	result.events.append(_event(&"piece_promoted", {"old_piece_id": old_id, "new_piece_id": promoted.piece_id, "piece_type": option, "coordinate": coordinate}))
	_finish_action(state, result.events)
	result.status = ChessCoreStepResult.Status.COMPLETED
	return result


static func _legal_destinations(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	match piece.type_id:
		&"pawn": return _pawn_moves(state, piece)
		&"knight": return _jump_moves(state, piece, [Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1), Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2)])
		&"bishop": return _ray_moves(state, piece, [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)])
		&"rook": return _ray_moves(state, piece, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)])
		&"queen": return _ray_moves(state, piece, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)])
		&"classic_king":
			var moves: Array[Vector2i] = []
			for row in range(8):
				for column in range(8):
					var target := Vector2i(row, column)
					var delta := target - piece.coordinate
					if target != piece.coordinate and absi(delta.x) <= 1 and absi(delta.y) <= 1 and _available(state, target, piece.color): moves.append(target)
			if not piece.has_moved:
				for target in [Vector2i(7 if piece.color == "white" else 0, 2), Vector2i(7 if piece.color == "white" else 0, 6)]:
					if _can_castle(state, piece, target): moves.append(target)
			return moves
	return []


static func _pawn_moves(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var direction := -1 if piece.color == "white" else 1
	var one := piece.coordinate + Vector2i(direction, 0)
	if _in_bounds(one) and state.occupant(one) == null:
		result.append(one)
		var two := piece.coordinate + Vector2i(direction * 2, 0)
		if not piece.has_moved and _in_bounds(two) and state.occupant(two) == null: result.append(two)
	for column_delta in [-1, 1]:
		var target := piece.coordinate + Vector2i(direction, column_delta)
		if not _in_bounds(target): continue
		var occupant := state.occupant(target)
		if occupant != null and occupant.color != piece.color:
			result.append(target)
		elif _en_passant_victim(state, piece, target) != null:
			result.append(target)
	return result


static func _jump_moves(state: ChessCoreState, piece: ChessCorePiece, offsets: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in offsets:
		var target: Vector2i = piece.coordinate + offset
		if _in_bounds(target) and _available(state, target, piece.color): result.append(target)
	return result


static func _ray_moves(state: ChessCoreState, piece: ChessCorePiece, directions: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in directions:
		var target: Vector2i = piece.coordinate + direction
		while _in_bounds(target):
			var occupant := state.occupant(target)
			if occupant == null:
				result.append(target)
			elif occupant.color != piece.color:
				result.append(target)
				break
			else:
				break
			target += direction
	return result


static func _can_castle(state: ChessCoreState, king: ChessCorePiece, target: Vector2i) -> bool:
	var row := 7 if king.color == "white" else 0
	if king.coordinate != Vector2i(row, 4) or target.x != row or target.y not in [2, 6] or state.occupant(target) != null:
		return false
	var rook_column := 0 if target.y == 2 else 7
	var rook := state.occupant(Vector2i(row, rook_column))
	if rook == null or rook.type_id != &"rook" or rook.color != king.color or rook.has_moved:
		return false
	for column in range(mini(4, rook_column) + 1, maxi(4, rook_column)):
		if state.occupant(Vector2i(row, column)) != null: return false
	return true


static func _en_passant_victim(state: ChessCoreState, pawn: ChessCorePiece, target: Vector2i) -> ChessCorePiece:
	if state.occupant(target) != null or absi(target.y - pawn.coordinate.y) != 1:
		return null
	var direction := -1 if pawn.color == "white" else 1
	if target.x != pawn.coordinate.x + direction or state.last_move.is_empty(): return null
	var previous_from: Vector2i = state.last_move.get("from", Vector2i.ZERO)
	var previous_to: Vector2i = state.last_move.get("to", Vector2i.ZERO)
	if absi(previous_to.x - previous_from.x) != 2 or previous_to != Vector2i(pawn.coordinate.x, target.y): return null
	var victim := state.occupant(previous_to)
	if victim == null or victim.type_id != &"pawn" or victim.color == pawn.color: return null
	if not String(state.last_move.get("piece_id", "")).is_empty() and victim.piece_id != state.last_move.get("piece_id", ""): return null
	return victim


static func _resolve_castle(state: ChessCoreState, king: ChessCorePiece, target: Vector2i, events: Array[ChessCoreEvent]) -> void:
	var origin := king.coordinate
	var rook_from := Vector2i(origin.x, 7 if target.y == 6 else 0)
	var rook_to := Vector2i(origin.x, 5 if target.y == 6 else 3)
	var rook := state.occupant(rook_from)
	state.move_piece(king, target); king.has_moved = true
	state.move_piece(rook, rook_to); rook.has_moved = true
	events.append(_event(&"pieces_castled", {"king_id": king.piece_id, "rook_id": rook.piece_id, "king_from": origin, "king_to": target, "rook_from": rook_from, "rook_to": rook_to}))
	events.append(_event(&"piece_landed", {"piece_id": rook.piece_id, "from": rook_from, "to": rook_to}))
	events.append(_event(&"piece_landed", {"piece_id": king.piece_id, "from": origin, "to": target}))


static func _commit_capture(state: ChessCoreState, attacker: ChessCorePiece, defender: ChessCorePiece, target: Vector2i, captured_at: Vector2i, events: Array[ChessCoreEvent]) -> void:
	var origin := attacker.coordinate
	state.remove_piece(defender)
	state.move_piece(attacker, target)
	attacker.has_moved = true
	if defender.is_king() and defender.color not in state.defeated_king_colors: state.defeated_king_colors.append(defender.color)
	events.append(_event(&"piece_captured", {"attacker_id": attacker.piece_id, "defender_id": defender.piece_id, "from": origin, "to": target, "captured_at": captured_at}))
	events.append(_event(&"piece_destroyed", {"piece_id": defender.piece_id, "coordinate": captured_at}))
	events.append(_event(&"piece_landed", {"piece_id": attacker.piece_id, "from": origin, "to": target}))


static func _finish_action(state: ChessCoreState, events: Array[ChessCoreEvent]) -> void:
	var completed_color := state.current_turn
	_switch_turn(state, events)
	_resolve_forced_passes(state, events)
	if not state.battle_over:
		events.append(_event(&"action_finished", {"color": completed_color}))


static func _switch_turn(state: ChessCoreState, events: Array[ChessCoreEvent]) -> void:
	state.current_turn = "black" if state.current_turn == "white" else "white"
	if state.current_turn == "white": state.global_turn_number += 1
	for piece in state.pieces:
		if piece.color == state.current_turn and piece.stunned and piece.stun_timer > 0:
			piece.stun_timer -= 1
			if piece.stun_timer == 0: piece.stunned = false
	events.append(_event(&"turn_changed", {"color": state.current_turn, "global_turn_number": state.global_turn_number}))


static func _resolve_forced_passes(state: ChessCoreState, events: Array[ChessCoreEvent]) -> void:
	while not state.battle_over and legal_actions(state, state.current_turn).is_empty():
		state.consecutive_forced_passes += 1
		events.append(_event(&"turn_passed", {"color": state.current_turn, "count": state.consecutive_forced_passes}))
		if state.consecutive_forced_passes >= MAX_CONSECUTIVE_FORCED_PASSES:
			state.battle_over = true
			state.battle_result = "draw"
			events.append(_event(&"battle_finished", {"result": "draw"}))
			return
		_switch_turn(state, events)
	state.consecutive_forced_passes = 0


static func _complete_battle(state: ChessCoreState, events: Array[ChessCoreEvent]) -> void:
	state.battle_over = true
	var white_defeated := "white" in state.defeated_king_colors
	var black_defeated := "black" in state.defeated_king_colors
	state.battle_result = "draw" if white_defeated and black_defeated else ("black" if white_defeated else "white")
	events.append(_event(&"battle_finished", {"result": state.battle_result}))


static func _available(state: ChessCoreState, target: Vector2i, color: String) -> bool:
	var occupant := state.occupant(target)
	return occupant == null or occupant.color != color


static func _in_bounds(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < 8 and coordinate.y < 8


static func _reserve_id(state: ChessCoreState, id: String) -> void:
	var suffix := id.get_slice("_", id.get_slice_count("_") - 1)
	if suffix.is_valid_int(): state.next_state_id = maxi(state.next_state_id, suffix.to_int() + 1)


static func _event(kind: StringName, data: Dictionary) -> ChessCoreEvent:
	return ChessCoreEvent.make(kind, data)
