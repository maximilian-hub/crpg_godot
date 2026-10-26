extends RefCounted
class_name DupreExchangeAnalyzer

const MAX_SEQUENCE_LENGTH := 6
const MATERIAL_VALUES := {
	&"pawn": 1.0, &"bone_pawn": 1.0,
	&"knight": 3.0, &"bishop": 3.0,
	&"rook": 5.0, &"queen": 9.0,
}

enum Confidence { LOW, MEDIUM, HIGH }

var model: ChessBoardModel
var calls := 0
var elapsed_usec := 0
var high_confidence_calls := 0
var medium_confidence_calls := 0
var low_confidence_calls := 0


func _init(p_model: ChessBoardModel) -> void:
	model = p_model


func analyze_capture(action: ChessPrimaryAction, projected: DupreTacticalMap) -> Dictionary:
	var started := Time.get_ticks_usec()
	calls += 1
	var result := _empty_result(&"not_capture")
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return _finish(result, started)
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null or target.color == action.piece.color:
		return _finish(result, started)
	var gain := _damage_value(target, action.piece.attack_power)
	var confidence := _pair_confidence(action.piece, target)
	if action.piece.attack_power < target.current_hp:
		result = _result(gain, 0.0, confidence, &"durable_target", [{"attacker": action.piece.piece_id, "victim": target.piece_id, "lethal": false}])
		return _finish(result, started)
	var moved_piece = projected.occupancy.get(action.target)
	var reply_risk := 0.0
	var sequence: Array = [{"attacker": action.piece.piece_id, "victim": target.piece_id, "lethal": true}]
	if moved_piece is ModelPiece:
		var risk := analyze_piece_risk(moved_piece, projected)
		reply_risk = float(risk.loss)
		sequence.append_array(risk.sequence)
		confidence = mini(confidence, int(risk.confidence))
	result = _result(gain - reply_risk, reply_risk, confidence, &"complete", sequence.slice(0, MAX_SEQUENCE_LENGTH))
	return _finish(result, started)


func analyze_piece_risk(piece: ModelPiece, tactical: DupreTacticalMap) -> Dictionary:
	var started := Time.get_ticks_usec()
	calls += 1
	if piece == null or piece.is_king:
		return _finish(_empty_result(&"king_or_missing"), started)
	var coordinate: Vector2i = tactical.piece_coordinates.get(piece.piece_id, piece.coordinate)
	var attackers := tactical.attackers(coordinate, model.get_other_color(piece.color))
	if attackers.is_empty():
		return _finish(_empty_result(&"unattacked"), started)
	var defenders := tactical.attackers(coordinate, piece.color).filter(func(candidate): return candidate != piece)
	attackers.sort_custom(func(a: ModelPiece, b: ModelPiece): return _piece_value(a) < _piece_value(b))
	defenders.sort_custom(func(a: ModelPiece, b: ModelPiece): return _piece_value(a) < _piece_value(b))
	var worst_loss := 0.0
	var best_sequence: Array = []
	var confidence := Confidence.HIGH
	for attacker in attackers:
		var victim_loss := _damage_value(piece, attacker.attack_power)
		var sequence: Array = [{"attacker": attacker.piece_id, "victim": piece.piece_id, "lethal": attacker.attack_power >= piece.current_hp}]
		var net_loss := victim_loss
		confidence = mini(confidence, _pair_confidence(attacker, piece))
		if attacker.attack_power >= piece.current_hp:
			var recapturer: ModelPiece = _least_lethal_attacker(defenders, attacker)
			if recapturer != null:
				net_loss -= _piece_value(attacker)
				sequence.append({"attacker": recapturer.piece_id, "victim": attacker.piece_id, "lethal": true})
				var remaining_attackers := attackers.filter(func(candidate): return candidate != attacker)
				var remaining_defenders := defenders.filter(func(candidate): return candidate != recapturer)
				var current_victim: ModelPiece = recapturer
				var enemy_turn := true
				while sequence.size() < MAX_SEQUENCE_LENGTH:
					var pool: Array = remaining_attackers if enemy_turn else remaining_defenders
					var next_attacker: ModelPiece = _least_lethal_attacker(pool, current_victim)
					if next_attacker == null:
						break
					net_loss += _piece_value(current_victim) if enemy_turn else -_piece_value(current_victim)
					sequence.append({"attacker": next_attacker.piece_id, "victim": current_victim.piece_id, "lethal": true})
					pool.erase(next_attacker)
					current_victim = next_attacker
					enemy_turn = not enemy_turn
					confidence = Confidence.MEDIUM
		if net_loss > worst_loss:
			worst_loss = net_loss
			best_sequence = sequence
	return _finish(_result(0.0, maxf(0.0, worst_loss), confidence, &"complete", best_sequence), started)


func maximum_risk(color: String, tactical: DupreTacticalMap, minimum_value := 3.0) -> Dictionary:
	var highest := _empty_result(&"none")
	var highest_piece: ModelPiece
	for coordinate in tactical.occupancy:
		var piece = tactical.occupancy[coordinate]
		if not piece is ModelPiece or piece.color != color or piece.is_king or _piece_value(piece) < minimum_value:
			continue
		var risk := analyze_piece_risk(piece, tactical)
		if float(risk.loss) > float(highest.loss):
			highest = risk
			highest_piece = piece
	highest["piece"] = highest_piece
	return highest


func metrics() -> Dictionary:
	return {"calls": calls, "usec": elapsed_usec, "high": high_confidence_calls, "medium": medium_confidence_calls, "low": low_confidence_calls}


func _least_lethal_attacker(candidates: Array, victim: ModelPiece):
	for candidate in candidates:
		if candidate is ModelPiece and candidate.attack_power >= victim.current_hp:
			return candidate
	return null


func _damage_value(piece: ModelPiece, damage: int) -> float:
	var value := _piece_value(piece)
	if damage >= piece.current_hp:
		return value
	return value * 0.3 * float(mini(damage, piece.current_hp)) / float(maxi(1, piece.max_hp))


func _pair_confidence(attacker: ModelPiece, victim: ModelPiece) -> int:
	if attacker.is_king or victim.is_king:
		return Confidence.LOW
	if attacker.max_hp > 1 or victim.max_hp > 1:
		return Confidence.MEDIUM
	return Confidence.HIGH


func _piece_value(piece: ModelPiece) -> float:
	return float(MATERIAL_VALUES.get(piece.get_position_type_id(), 1.0))


func _empty_result(reason: StringName) -> Dictionary:
	return _result(0.0, 0.0, Confidence.HIGH, reason, [])


func _result(delta: float, loss: float, confidence: int, reason: StringName, sequence: Array) -> Dictionary:
	return {"delta": delta, "loss": loss, "confidence": confidence, "reason": reason, "sequence": sequence}


func _finish(result: Dictionary, started: int) -> Dictionary:
	elapsed_usec += Time.get_ticks_usec() - started
	match int(result.confidence):
		Confidence.HIGH: high_confidence_calls += 1
		Confidence.MEDIUM: medium_confidence_calls += 1
		_: low_confidence_calls += 1
	return result
