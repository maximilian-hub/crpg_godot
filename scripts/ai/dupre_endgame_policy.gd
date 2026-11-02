extends RefCounted
class_name DupreEndgamePolicy

const ENDGAME_BLEND_START := 40.0
const ENDGAME_FULL := 16.0
const MATERIAL_VALUES := {
	&"pawn": 1.0, &"bone_pawn": 1.0, &"knight": 3.0, &"bishop": 3.0,
	&"rook": 5.0, &"queen": 9.0,
}


static func snapshot_from_model(model: ChessBoardModel) -> Dictionary:
	var pieces: Array[Dictionary] = []
	for row in model.board:
		for piece in row:
			if piece is ModelPiece:
				pieces.append(_piece_record(piece.piece_id, piece.get_position_type_id(), piece.color, piece.coordinate, piece.is_king))
	return _snapshot(pieces)


static func snapshot_from_tactical_map(tactical: DupreTacticalMap) -> Dictionary:
	var pieces: Array[Dictionary] = []
	for coordinate in tactical.occupancy:
		var piece = tactical.occupancy[coordinate]
		if piece is ModelPiece:
			pieces.append(_piece_record(piece.piece_id, piece.get_position_type_id(), piece.color, coordinate, piece.is_king))
	return _snapshot(pieces)


static func snapshot_from_core(state: ChessCoreState) -> Dictionary:
	var pieces: Array[Dictionary] = []
	for piece in state.pieces:
		pieces.append(_piece_record(piece.piece_id, piece.type_id, piece.color, piece.coordinate, piece.is_king()))
	return _snapshot(pieces)


static func analyze_model(model: ChessBoardModel, perspective: String) -> Dictionary:
	return analyze(snapshot_from_model(model), perspective)


static func analyze_core(state: ChessCoreState, perspective: String) -> Dictionary:
	var key := "dupre_endgame|%s" % perspective
	if state.analysis_cache.has(key):
		var cached: Dictionary = state.analysis_cache[key]
		var result := cached.duplicate(true)
		result["cache_hit"] = true
		return result
	var result := analyze(snapshot_from_core(state), perspective)
	state.analysis_cache[key] = result.duplicate(true)
	return result


static func analyze(snapshot: Dictionary, perspective: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var enemy := _other_color(perspective)
	var non_pawn_material := 0.0
	var material := {"white": 0.0, "black": 0.0}
	var kings := {}
	for piece: Dictionary in snapshot.pieces:
		if bool(piece.is_king):
			kings[piece.color] = piece
			continue
		var value := _material_value(piece.type_id)
		material[piece.color] = float(material[piece.color]) + value
		if piece.type_id not in [&"pawn", &"bone_pawn"]:
			non_pawn_material += value
	var weight := clampf((ENDGAME_BLEND_START - non_pawn_material) / (ENDGAME_BLEND_START - ENDGAME_FULL), 0.0, 1.0)
	if weight <= 0.0:
		return middlegame_analysis(float(material[perspective]) - float(material[enemy]), float(material.white) + float(material.black), non_pawn_material, Time.get_ticks_usec() - started)
	var passed: Array[Dictionary] = []
	for piece: Dictionary in snapshot.pieces:
		if piece.type_id != &"pawn" or not _is_passed_pawn(piece, snapshot.pieces):
			continue
		var direction := -1 if piece.color == "white" else 1
		var front: Vector2i = piece.coordinate + Vector2i(direction, 0)
		passed.append({
			"piece_id": piece.piece_id,
			"color": piece.color,
			"coordinate": piece.coordinate,
			"distance": piece.coordinate.x if piece.color == "white" else 7 - piece.coordinate.x,
			"blocked": snapshot.occupancy.has(front),
			"protected": _pawn_supported(piece, snapshot.pieces),
		})
	var raw_score := 0.0
	var components := {"passed_pawns": 0.0, "king_activity": 0.0, "rook_support": 0.0}
	for passer in passed:
		var sign_value := 1.0 if passer.color == perspective else -1.0
		var distance := maxi(1, int(passer.distance))
		var pawn_score := float(8 - distance) * 0.42 + (1.4 if distance <= 2 else 0.0)
		if bool(passer.protected): pawn_score += 0.75
		if bool(passer.blocked): pawn_score -= 0.55
		var own_king: Dictionary = kings.get(passer.color, {})
		if not own_king.is_empty():
			pawn_score += maxf(0.0, 4.0 - _king_distance(own_king.coordinate, passer.coordinate)) * 0.20
		var defending_king: Dictionary = kings.get(_other_color(String(passer.color)), {})
		if not defending_king.is_empty():
			pawn_score -= maxf(0.0, 4.0 - _king_distance(defending_king.coordinate, passer.coordinate)) * 0.16
		components.passed_pawns += sign_value * pawn_score
		components.rook_support += sign_value * _rook_behind_bonus(passer, snapshot.pieces)
	for color in ["white", "black"]:
		var king: Dictionary = kings.get(color, {})
		if king.is_empty(): continue
		var centrality := 7.0 - (absf(float(king.coordinate.x) - 3.5) + absf(float(king.coordinate.y) - 3.5))
		components.king_activity += (1.0 if color == perspective else -1.0) * centrality * 0.12
	for value in components.values(): raw_score += float(value)
	return {
		"endgame_weight": weight,
		"phase": &"endgame" if weight >= 0.75 else (&"transition" if weight > 0.0 else &"middlegame"),
		"material_balance": float(material[perspective]) - float(material[enemy]),
		"total_material": float(material.white) + float(material.black),
		"non_pawn_material": non_pawn_material,
		"friendly_passed_pawns": passed.filter(func(p): return p.color == perspective).size(),
		"enemy_passed_pawns": passed.filter(func(p): return p.color == enemy).size(),
		"score": raw_score * weight,
		"components": components,
		"analysis_usec": Time.get_ticks_usec() - started,
		"cache_hit": false,
	}


static func middlegame_analysis(material_balance := 0.0, total_material := 0.0, non_pawn_material := ENDGAME_BLEND_START, elapsed_usec := 0) -> Dictionary:
	return {
		"endgame_weight": 0.0, "phase": &"middlegame",
		"material_balance": material_balance, "total_material": total_material,
		"non_pawn_material": non_pawn_material,
		"friendly_passed_pawns": 0, "enemy_passed_pawns": 0,
		"score": 0.0, "components": {}, "analysis_usec": elapsed_usec,
		"cache_hit": false,
	}


static func transition_bonus(before: Dictionary, after: Dictionary, perspective: String) -> Dictionary:
	var before_analysis := analyze(before, perspective)
	var after_analysis := analyze(after, perspective)
	var positional := float(after_analysis.score) - float(before_analysis.score)
	var trade := 0.0
	var reduction := maxf(0.0, float(before_analysis.total_material) - float(after_analysis.total_material))
	var balance_before := float(before_analysis.material_balance)
	var balance_after := float(after_analysis.material_balance)
	var weight := maxf(float(before_analysis.endgame_weight), float(after_analysis.endgame_weight))
	if reduction > 0.0 and balance_after >= balance_before - 0.1:
		if balance_before >= 3.0:
			trade = minf(reduction, 9.0) * 0.25 * weight
		elif balance_before <= -3.0 and balance_after <= balance_before + 0.1:
			trade = -minf(reduction, 9.0) * 0.18 * weight
	return {
		"score": positional + trade,
		"positional": positional,
		"trade": trade,
		"before": before_analysis,
		"after": after_analysis,
	}


static func _snapshot(pieces: Array[Dictionary]) -> Dictionary:
	var occupancy := {}
	for piece in pieces: occupancy[piece.coordinate] = piece
	return {"pieces": pieces, "occupancy": occupancy}


static func _piece_record(piece_id: String, type_id: StringName, color: String, coordinate: Vector2i, is_king: bool) -> Dictionary:
	return {"piece_id": piece_id, "type_id": type_id, "color": color, "coordinate": coordinate, "is_king": is_king}


static func _is_passed_pawn(pawn: Dictionary, pieces: Array[Dictionary]) -> bool:
	for piece in pieces:
		if piece.color == pawn.color or piece.type_id != &"pawn" or absi(piece.coordinate.y - pawn.coordinate.y) > 1:
			continue
		if pawn.color == "white" and piece.coordinate.x < pawn.coordinate.x: return false
		if pawn.color == "black" and piece.coordinate.x > pawn.coordinate.x: return false
	return true


static func _pawn_supported(pawn: Dictionary, pieces: Array[Dictionary]) -> bool:
	var support_row: int = pawn.coordinate.x + (1 if pawn.color == "white" else -1)
	for piece in pieces:
		if piece.color == pawn.color and piece.type_id == &"pawn" and piece.coordinate.x == support_row and absi(piece.coordinate.y - pawn.coordinate.y) == 1:
			return true
	return false


static func _rook_behind_bonus(passer: Dictionary, pieces: Array[Dictionary]) -> float:
	for piece in pieces:
		if piece.color != passer.color or piece.type_id != &"rook" or piece.coordinate.y != passer.coordinate.y:
			continue
		if (passer.color == "white" and piece.coordinate.x > passer.coordinate.x) or (passer.color == "black" and piece.coordinate.x < passer.coordinate.x):
			return 1.25
	return 0.0


static func _material_value(type_id: StringName) -> float:
	return float(MATERIAL_VALUES.get(type_id, 0.0))


static func _king_distance(a: Vector2i, b: Vector2i) -> float:
	return float(maxi(absi(a.x - b.x), absi(a.y - b.y)))


static func _other_color(color: String) -> String:
	return "black" if color == "white" else "white"
