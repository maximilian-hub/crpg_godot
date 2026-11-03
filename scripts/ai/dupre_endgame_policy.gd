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
				pieces.append(_model_piece_record(piece, piece.coordinate))
	return _snapshot(pieces, model.current_turn, Vector2i(model.board.size(), model.board[0].size() if not model.board.is_empty() else 0))


static func snapshot_from_tactical_map(tactical: DupreTacticalMap, current_turn := "") -> Dictionary:
	var pieces: Array[Dictionary] = []
	for coordinate in tactical.occupancy:
		var piece = tactical.occupancy[coordinate]
		if piece is ModelPiece:
			pieces.append(_model_piece_record(piece, coordinate))
	return _snapshot(pieces, current_turn, tactical.board_size)


static func snapshot_from_core(state: ChessCoreState) -> Dictionary:
	var pieces: Array[Dictionary] = []
	for piece in state.pieces:
		pieces.append(_piece_record(piece.piece_id, piece.type_id, piece.color, piece.coordinate, piece.is_king(), piece.has_moved, piece.current_hp, piece.max_hp, piece.attack_power, piece.stunned))
	return _snapshot(pieces, state.current_turn, state.board_size)


static func analyze_model(model: ChessBoardModel, perspective: String, technique_enabled := true) -> Dictionary:
	return analyze(snapshot_from_model(model), perspective, technique_enabled)


static func analyze_core(state: ChessCoreState, perspective: String, technique_enabled := true) -> Dictionary:
	var key := "dupre_endgame|%s|%s" % [perspective, technique_enabled]
	if state.analysis_cache.has(key):
		var cached: Dictionary = state.analysis_cache[key]
		var result := cached.duplicate(true)
		result["cache_hit"] = true
		return result
	var result := analyze(snapshot_from_core(state), perspective, technique_enabled)
	state.analysis_cache[key] = result.duplicate(true)
	return result


static func analyze(snapshot: Dictionary, perspective: String, technique_enabled := true) -> Dictionary:
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
			"promotion_plies": _promotion_plies(piece, snapshot),
		})
	var raw_score := 0.0
	var components := {"passed_pawns": 0.0, "king_activity": 0.0, "rook_support": 0.0, "promotion_race": 0.0, "king_escort": 0.0, "rook_technique": 0.0}
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
		if technique_enabled:
			components.promotion_race += sign_value * _promotion_pressure(passer)
			components.king_escort += sign_value * _escort_pressure(passer, kings)
	if technique_enabled:
		components.promotion_race += _race_tempo_balance(passed, perspective)
		components.rook_technique += _rook_technique_score(passed, snapshot, perspective)
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
		"friendly_fastest_promotion_plies": _fastest_promotion_plies(passed, perspective),
		"enemy_fastest_promotion_plies": _fastest_promotion_plies(passed, enemy),
		"blocked_passed_pawns": passed.filter(func(p): return int(p.promotion_plies) < 0).size(),
		"technique_enabled": technique_enabled,
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
		"friendly_fastest_promotion_plies": -1, "enemy_fastest_promotion_plies": -1,
		"blocked_passed_pawns": 0, "technique_enabled": false,
		"score": 0.0, "components": {}, "analysis_usec": elapsed_usec,
		"cache_hit": false,
	}


static func transition_bonus(before: Dictionary, after: Dictionary, perspective: String, technique_enabled := true) -> Dictionary:
	var before_analysis := analyze(before, perspective, technique_enabled)
	return transition_bonus_from_analysis(before_analysis, after, perspective, technique_enabled)


## Root policy already owns the analysis of the settled position. Reusing it
## avoids re-analyzing the same "before" board once for every legal action.
static func transition_bonus_from_analysis(before_analysis: Dictionary, after: Dictionary, perspective: String, technique_enabled := true) -> Dictionary:
	var after_analysis := analyze(after, perspective, technique_enabled)
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


static func _snapshot(pieces: Array[Dictionary], current_turn := "white", board_size := Vector2i(8, 8)) -> Dictionary:
	var occupancy := {}
	for piece in pieces: occupancy[piece.coordinate] = piece
	return {"pieces": pieces, "occupancy": occupancy, "current_turn": current_turn, "board_size": board_size}


static func _model_piece_record(piece: ModelPiece, coordinate: Vector2i) -> Dictionary:
	return _piece_record(piece.piece_id, piece.get_position_type_id(), piece.color, coordinate, piece.is_king, piece.has_moved, piece.current_hp, piece.max_hp, piece.attack_power, piece.stunned)


static func _piece_record(piece_id: String, type_id: StringName, color: String, coordinate: Vector2i, is_king: bool, has_moved := true, current_hp := 1, max_hp := 1, attack_power := 1, stunned := false) -> Dictionary:
	return {
		"piece_id": piece_id, "type_id": type_id, "color": color,
		"coordinate": coordinate, "is_king": is_king, "has_moved": has_moved,
		"current_hp": current_hp, "max_hp": max_hp,
		"attack_power": attack_power, "stunned": stunned,
	}


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


static func _promotion_plies(pawn: Dictionary, snapshot: Dictionary) -> int:
	if bool(pawn.get("stunned", false)):
		return -1
	var direction := -1 if pawn.color == "white" else 1
	var board_size: Vector2i = snapshot.get("board_size", Vector2i(8, 8))
	var occupancy: Dictionary = snapshot.get("occupancy", {})
	var promotion_row := 0 if pawn.color == "white" else int(board_size.x) - 1
	var distance := absi(int(pawn.coordinate.x) - promotion_row)
	if distance <= 0:
		return 0
	# A file blocker makes the current race indeterminate. Captures or removal may
	# reopen it later, but the static evaluator must not advertise a false clock.
	for step in range(1, distance + 1):
		if occupancy.has(pawn.coordinate + Vector2i(direction * step, 0)):
			return -1
	var moves := distance
	var starting_row := int(board_size.x) - 2 if pawn.color == "white" else 1
	if not bool(pawn.get("has_moved", true)) and pawn.coordinate.x == starting_row and distance >= 2:
		moves -= 1
	var waiting_ply := 0 if String(snapshot.get("current_turn", "white")) == String(pawn.color) else 1
	return waiting_ply + moves * 2 - 1


static func _promotion_pressure(passer: Dictionary) -> float:
	var plies := int(passer.promotion_plies)
	if plies < 0:
		return -0.35
	# Imminent promotion is a material-scale event. The sharp final-step increase
	# makes spending the tempo competitive with generic King centralization while
	# remaining far below tactical win/loss scores.
	if plies <= 2: return 14.0
	if plies <= 4: return 3.5
	if plies <= 6: return 2.2
	return clampf(1.8 - float(plies - 6) * 0.16, 0.15, 1.8)


static func _escort_pressure(passer: Dictionary, kings: Dictionary) -> float:
	var own: Dictionary = kings.get(passer.color, {})
	var enemy: Dictionary = kings.get(_other_color(String(passer.color)), {})
	if own.is_empty() or enemy.is_empty():
		return 0.0
	var direction := -1 if passer.color == "white" else 1
	var critical: Vector2i = passer.coordinate + Vector2i(direction, 0)
	var own_distance := _king_distance(own.coordinate, critical)
	var enemy_distance := _king_distance(enemy.coordinate, critical)
	# This is pressure, not orthodox square control: either King remains free to
	# enter an attacked square and let authoritative combat resolve the result.
	return clampf((enemy_distance - own_distance) * 0.14, -0.7, 0.7)


static func _race_tempo_balance(passers: Array[Dictionary], perspective: String) -> float:
	var friendly := _fastest_promotion_plies(passers, perspective)
	var enemy := _fastest_promotion_plies(passers, _other_color(perspective))
	if friendly < 0 and enemy < 0: return 0.0
	if friendly >= 0 and enemy < 0: return 0.8
	if friendly < 0 and enemy >= 0: return -0.8
	return clampf(float(enemy - friendly) * 0.18, -1.2, 1.2)


static func _fastest_promotion_plies(passers: Array[Dictionary], color: String) -> int:
	var result := -1
	for passer in passers:
		var plies := int(passer.promotion_plies)
		if passer.color == color and plies >= 0 and (result < 0 or plies < result):
			result = plies
	return result


static func _rook_technique_score(passers: Array[Dictionary], snapshot: Dictionary, perspective: String) -> float:
	var result := 0.0
	for rook: Dictionary in snapshot.pieces:
		if rook.type_id != &"rook" or bool(rook.get("stunned", false)):
			continue
		var rook_value := 0.0
		for passer in passers:
			if rook.coordinate.y != passer.coordinate.y or not _file_between_clear(rook.coordinate, passer.coordinate, snapshot.occupancy):
				continue
			var direction := -1 if passer.color == "white" else 1
			var behind := signi(rook.coordinate.x - passer.coordinate.x) == -direction
			var in_front := signi(rook.coordinate.x - passer.coordinate.x) == direction
			if rook.color == passer.color:
				# Existing rook_support already rewards the canonical placement; this
				# smaller term rewards maintaining a clear, useful support ray.
				if behind: rook_value += 0.35
			elif behind:
				rook_value += 0.9
			elif in_front:
				rook_value += 0.55
		result += rook_value if rook.color == perspective else -rook_value
	return result


static func _file_between_clear(a: Vector2i, b: Vector2i, occupancy: Dictionary) -> bool:
	if a.y != b.y: return false
	var direction := signi(b.x - a.x)
	for row in range(a.x + direction, b.x, direction):
		if occupancy.has(Vector2i(row, a.y)): return false
	return true


static func _material_value(type_id: StringName) -> float:
	return float(MATERIAL_VALUES.get(type_id, 0.0))


static func _king_distance(a: Vector2i, b: Vector2i) -> float:
	return float(maxi(absi(a.x - b.x), absi(a.y - b.y)))


static func _other_color(color: String) -> String:
	return "black" if color == "white" else "white"
