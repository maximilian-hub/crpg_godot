extends RefCounted
class_name QuarterlyInitiativeAiPolicy

const FREE_CYCLE_REWARD := 24.0
const OFF_CYCLE_COST := 12.0
const MIN_HP_SACRIFICE_ROUND := 15
const PAWN_UPGRADE_REWARD := 8.0
const QUEEN_HYBRID_REWARD := 11.0
const UNPROTECTED_TARGET_REWARD := 12.0
const KING_TARGET_REWARD := 40.0


static func eligible_options(model: ChessBoardModel, recipient: ModelPiece, options: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	if model.global_turn_number % 4 == 0:
		for option in options:
			if not is_redundant(recipient, StringName(option)):
				result.append(StringName(option))
		return result
	for option in options:
		var movement_type := StringName(option)
		if grant_is_sacrifice_worthy(model, recipient, movement_type):
			result.append(movement_type)
	return result


static func action_is_available(model: ChessBoardModel, king: QuarterlyInitiativeKing, recipient: ModelPiece, options: Array) -> bool:
	if recipient == null:
		return false
	if model.global_turn_number % 4 != 0 and (model.global_turn_number < MIN_HP_SACRIFICE_ROUND or king.current_hp <= 2):
		return false
	return not eligible_options(model, recipient, options).is_empty()


static func best_grant(model: ChessBoardModel, recipient: ModelPiece, options: Array) -> Dictionary:
	var best_score := -INF
	var best_options: Array[StringName] = []
	for raw_option in options:
		var option := StringName(raw_option)
		var score := score_grant(model, recipient, option)
		if score > best_score:
			best_score = score
			best_options.assign([option])
		elif is_equal_approx(score, best_score):
			best_options.append(option)
	return {"score": best_score, "options": best_options}


static func action_score(model: ChessBoardModel, recipient: ModelPiece, options: Array) -> float:
	var best := best_grant(model, recipient, eligible_options(model, recipient, options))
	if float(best.score) == -INF:
		return -INF
	return (FREE_CYCLE_REWARD if model.global_turn_number % 4 == 0 else -OFF_CYCLE_COST) + float(best.score)


static func deterministic_choice(model: ChessBoardModel, recipient: ModelPiece, options: Array) -> StringName:
	# Selection must always settle an authoritative action, including deliberately
	# poor opponent replies that Dupre itself would have filtered at the root.
	var best := best_grant(model, recipient, options)
	var choices: Array = best.options
	if choices.is_empty():
		return StringName(options[0]) if not options.is_empty() else &""
	choices.sort()
	return StringName(choices[0])


static func grant_is_sacrifice_worthy(model: ChessBoardModel, recipient: ModelPiece, movement_type: StringName) -> bool:
	if is_redundant(recipient, movement_type):
		return false
	var native_moves: Array = recipient.get_legal_moves()
	var tactical := DupreTacticalMap.from_model(model)
	var qualifying_fork_targets := 0
	for destination in model._get_moves_as(recipient, movement_type):
		if destination in native_moves:
			continue
		var target: ModelPiece = model.board[destination.x][destination.y]
		if target == null or target.color == recipient.color:
			continue
		if target.is_king:
			return true
		if target.type in ["queen", "rook"] or (target.type in ["bishop", "knight"] and tactical.attack_count(target.coordinate, target.color) == 0):
			qualifying_fork_targets += 1
			if qualifying_fork_targets >= 2:
				return true
	return false


static func score_grant(model: ChessBoardModel, recipient: ModelPiece, movement_type: StringName) -> float:
	if is_redundant(recipient, movement_type):
		return -INF
	var score := 1.0
	if recipient.type == "pawn":
		score += PAWN_UPGRADE_REWARD
	elif (recipient.type == "rook" and movement_type == &"bishop") or (recipient.type == "bishop" and movement_type == &"rook"):
		score += QUEEN_HYBRID_REWARD
	var native_moves: Array = recipient.get_legal_moves()
	var tactical := DupreTacticalMap.from_model(model)
	for destination in model._get_moves_as(recipient, movement_type):
		if destination in native_moves:
			continue
		var target: ModelPiece = model.board[destination.x][destination.y]
		if target == null or target.color == recipient.color:
			continue
		if target.is_king:
			score += KING_TARGET_REWARD
		elif tactical.attack_count(target.coordinate, target.color) == 0:
			score += UNPROTECTED_TARGET_REWARD + _piece_value(target)
		else:
			score += _piece_value(target) * 0.5
	return score


static func is_redundant(recipient: ModelPiece, movement_type: StringName) -> bool:
	if movement_type in recipient.granted_movement_types:
		return true
	match movement_type:
		&"pawn": return recipient.type == "pawn"
		&"knight": return recipient.type == "knight"
		&"bishop": return recipient.type in ["bishop", "queen"]
		&"rook": return recipient.type in ["rook", "queen"]
	return true


static func _piece_value(piece: ModelPiece) -> float:
	if piece.is_king: return 100.0
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0
