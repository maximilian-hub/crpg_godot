extends RefCounted
class_name ChessPositionCodec

static func to_dictionary(position: ChessPosition) -> Dictionary:
	var piece_dicts: Array[Dictionary] = []
	var sorted_pieces := position.pieces.duplicate()
	sorted_pieces.sort_custom(func(a: ChessPieceState, b: ChessPieceState):
		return [a.coordinate.x, a.coordinate.y, String(a.type_id), a.color] < [b.coordinate.x, b.coordinate.y, String(b.type_id), b.color])
	for piece in sorted_pieces:
		piece_dicts.append({
			"type": String(piece.type_id), "color": piece.color,
			"coordinate": [piece.coordinate.x, piece.coordinate.y],
			"max_hp": piece.max_hp, "current_hp": piece.current_hp,
			"attack_power": piece.attack_power, "has_moved": piece.has_moved,
			"stunned": piece.stunned, "stun_timer": piece.stun_timer,
			"current_cooldown": piece.current_cooldown,
			"custom": piece.custom_state.duplicate(true),
		})
	var last = null
	if position.last_move != null and position.last_move.is_present:
		last = {
			"from": [position.last_move.from.x, position.last_move.from.y],
			"to": [position.last_move.to.x, position.last_move.to.y],
			"piece_type": String(position.last_move.piece_type_id),
			"piece_color": position.last_move.piece_color,
		}
	return {
		"schema": "crpg_chess_position", "version": position.schema_version,
		"board": {"rows": position.board_size.x, "columns": position.board_size.y, "type": String(position.board_type)},
		"current_turn": position.current_turn, "last_move": last,
		"battle": {"over": position.battle_over, "result": position.battle_result, "defeated_king_colors": position.defeated_king_colors.duplicate()},
		"pieces": piece_dicts,
	}

static func to_json(position: ChessPosition, pretty := true) -> String:
	return JSON.stringify(to_dictionary(position), "  " if pretty else "")

static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return {"position": null, "errors": ["JSON parse error at line %s: %s" % [json.get_error_line(), json.get_error_message()]]}
	if not json.data is Dictionary:
		return {"position": null, "errors": ["Position JSON must contain an object."]}
	return from_dictionary(json.data)

static func from_dictionary(data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if data.get("schema", "") != "crpg_chess_position":
		errors.append("Unknown position schema.")
	if int(data.get("version", -1)) != ChessPosition.CURRENT_SCHEMA_VERSION:
		errors.append("Unsupported position version.")
	var board_data = data.get("board", {})
	if not board_data is Dictionary:
		errors.append("Board must be an object.")
		board_data = {}
	var position := ChessPosition.new()
	position.schema_version = int(data.get("version", ChessPosition.CURRENT_SCHEMA_VERSION))
	position.board_size = Vector2i(int(board_data.get("rows", 0)), int(board_data.get("columns", 0)))
	position.board_type = StringName(board_data.get("type", "default"))
	position.current_turn = String(data.get("current_turn", ""))
	var battle = data.get("battle", {})
	if battle is Dictionary:
		position.battle_over = bool(battle.get("over", false))
		position.battle_result = String(battle.get("result", ""))
		for color in battle.get("defeated_king_colors", []):
			position.defeated_king_colors.append(String(color))
	var last = data.get("last_move")
	if last is Dictionary:
		position.last_move.is_present = true
		position.last_move.from = _decode_coord(last.get("from", []), errors, "last_move.from")
		position.last_move.to = _decode_coord(last.get("to", []), errors, "last_move.to")
		position.last_move.piece_type_id = StringName(last.get("piece_type", ""))
		position.last_move.piece_color = String(last.get("piece_color", ""))
	var raw_pieces = data.get("pieces", [])
	if not raw_pieces is Array:
		errors.append("Pieces must be an array.")
		raw_pieces = []
	for index in range(raw_pieces.size()):
		var raw = raw_pieces[index]
		if not raw is Dictionary:
			errors.append("Piece %s must be an object." % index)
			continue
		var piece := ChessPieceState.new()
		piece.type_id = StringName(raw.get("type", ""))
		piece.color = String(raw.get("color", ""))
		piece.coordinate = _decode_coord(raw.get("coordinate", []), errors, "pieces[%s].coordinate" % index)
		piece.max_hp = int(raw.get("max_hp", 1))
		piece.current_hp = int(raw.get("current_hp", piece.max_hp))
		piece.attack_power = int(raw.get("attack_power", 1))
		piece.has_moved = bool(raw.get("has_moved", false))
		piece.stunned = bool(raw.get("stunned", false))
		piece.stun_timer = int(raw.get("stun_timer", 0))
		piece.current_cooldown = int(raw.get("current_cooldown", 0))
		var custom = raw.get("custom", {})
		piece.custom_state = custom.duplicate(true) if custom is Dictionary else {}
		position.pieces.append(piece)
	var validation := ChessPositionValidator.validate(position)
	errors.append_array(validation.structural_errors)
	return {"position": position if errors.is_empty() else null, "errors": errors}

static func _decode_coord(value, errors: Array[String], field: String) -> Vector2i:
	if not value is Array or value.size() != 2:
		errors.append("%s must be a two-item array." % field)
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))
