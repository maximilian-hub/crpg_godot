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
			"id": piece.piece_id,
			"coordinate": [piece.coordinate.x, piece.coordinate.y],
			"max_hp": piece.max_hp, "current_hp": piece.current_hp,
			"attack_power": piece.attack_power, "has_moved": piece.has_moved,
			"stunned": piece.stunned, "stun_timer": piece.stun_timer,
			"current_cooldown": piece.current_cooldown,
			"cooldown_reset_pending": piece.cooldown_reset_pending,
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
	var effect_dicts: Array[Dictionary] = []
	var sorted_effects := position.tile_effects.duplicate()
	sorted_effects.sort_custom(func(a: ChessTileEffectState, b: ChessTileEffectState): return a.effect_id < b.effect_id)
	for effect in sorted_effects:
		effect_dicts.append({"id": effect.effect_id, "type": String(effect.type_id), "coordinate": [effect.coordinate.x, effect.coordinate.y], "owner_color": effect.owner_color, "source_piece_id": effect.source_piece_id, "custom": effect.custom_state.duplicate(true)})
	var entity_dicts: Array[Dictionary] = []
	var sorted_entities := position.autonomous_entities.duplicate()
	sorted_entities.sort_custom(func(a: ChessAutonomousEntityState, b: ChessAutonomousEntityState): return a.entity_id < b.entity_id)
	for entity in sorted_entities:
		entity_dicts.append({"id": entity.entity_id, "type": String(entity.type_id), "coordinate": [entity.coordinate.x, entity.coordinate.y], "owner_color": entity.owner_color, "source_piece_id": entity.source_piece_id, "target_piece_id": entity.target_piece_id, "custom": entity.custom_state.duplicate(true)})
	return {
		"schema": "crpg_chess_position", "version": position.schema_version,
		"board": {"rows": position.board_size.x, "columns": position.board_size.y, "type": String(position.board_type)},
		"current_turn": position.current_turn, "last_move": last,
		"battle": {"over": position.battle_over, "result": position.battle_result, "defeated_king_colors": position.defeated_king_colors.duplicate()},
		"pieces": piece_dicts, "tile_effects": effect_dicts, "autonomous_entities": entity_dicts,
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
	var input_version := int(data.get("version", -1))
	if input_version not in [1, ChessPosition.CURRENT_SCHEMA_VERSION]:
		errors.append("Unsupported position version.")
	var board_data = data.get("board", {})
	if not board_data is Dictionary:
		errors.append("Board must be an object.")
		board_data = {}
	var position := ChessPosition.new()
	position.schema_version = ChessPosition.CURRENT_SCHEMA_VERSION if input_version == 1 else input_version
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
		piece.piece_id = String(raw.get("id", ""))
		piece.color = String(raw.get("color", ""))
		piece.coordinate = _decode_coord(raw.get("coordinate", []), errors, "pieces[%s].coordinate" % index)
		piece.max_hp = int(raw.get("max_hp", 1))
		piece.current_hp = int(raw.get("current_hp", piece.max_hp))
		piece.attack_power = int(raw.get("attack_power", 1))
		piece.has_moved = bool(raw.get("has_moved", false))
		piece.stunned = bool(raw.get("stunned", false))
		piece.stun_timer = int(raw.get("stun_timer", 0))
		piece.current_cooldown = int(raw.get("current_cooldown", 0))
		piece.cooldown_reset_pending = bool(raw.get("cooldown_reset_pending", false))
		var custom = raw.get("custom", {})
		piece.custom_state = custom.duplicate(true) if custom is Dictionary else {}
		position.pieces.append(piece)
	for raw in data.get("tile_effects", []):
		if not raw is Dictionary: continue
		var effect := ChessTileEffectState.new()
		effect.effect_id = String(raw.get("id", "")); effect.type_id = StringName(raw.get("type", ""))
		effect.coordinate = _decode_coord(raw.get("coordinate", []), errors, "tile_effect.coordinate")
		effect.owner_color = String(raw.get("owner_color", "")); effect.source_piece_id = String(raw.get("source_piece_id", ""))
		var effect_custom = raw.get("custom", {})
		effect.custom_state = effect_custom.duplicate(true) if effect_custom is Dictionary else {}
		position.tile_effects.append(effect)
	for raw in data.get("autonomous_entities", []):
		if not raw is Dictionary: continue
		var entity := ChessAutonomousEntityState.new()
		entity.entity_id = String(raw.get("id", "")); entity.type_id = StringName(raw.get("type", ""))
		entity.coordinate = _decode_coord(raw.get("coordinate", []), errors, "autonomous_entity.coordinate")
		entity.owner_color = String(raw.get("owner_color", "")); entity.source_piece_id = String(raw.get("source_piece_id", "")); entity.target_piece_id = String(raw.get("target_piece_id", ""))
		var entity_custom = raw.get("custom", {})
		entity.custom_state = entity_custom.duplicate(true) if entity_custom is Dictionary else {}
		position.autonomous_entities.append(entity)
	var validation := ChessPositionValidator.validate(position)
	errors.append_array(validation.structural_errors)
	return {"position": position if errors.is_empty() else null, "errors": errors}

static func _decode_coord(value, errors: Array[String], field: String) -> Vector2i:
	if not value is Array or value.size() != 2:
		errors.append("%s must be a two-item array." % field)
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))
