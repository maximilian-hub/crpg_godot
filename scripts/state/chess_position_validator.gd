extends RefCounted
class_name ChessPositionValidator

static func validate(position: ChessPosition) -> ChessPositionValidation:
	var report := ChessPositionValidation.new()
	if position == null:
		report.structural_errors.append("Position is null.")
		return report
	if position.schema_version != ChessPosition.CURRENT_SCHEMA_VERSION:
		report.structural_errors.append("Unsupported schema version: %s" % position.schema_version)
	if position.board_size.x <= 0 or position.board_size.y <= 0:
		report.structural_errors.append("Board dimensions must be positive.")
	if position.current_turn not in ["white", "black"]:
		report.structural_errors.append("Invalid current turn: %s" % position.current_turn)
	var occupied := {}
	var piece_ids := {}
	var effect_ids := {}
	var entity_ids := {}
	var kings := {"white": 0, "black": 0}
	for piece in position.pieces:
		if piece == null:
			report.structural_errors.append("Position contains a null piece state.")
			continue
		if not ChessPieceCatalog.has_type(piece.type_id):
			report.structural_errors.append("Unknown piece type: %s" % piece.type_id)
		if piece.color not in ["white", "black"]:
			report.structural_errors.append("Invalid piece color: %s" % piece.color)
		if piece.coordinate.x < 0 or piece.coordinate.y < 0 or piece.coordinate.x >= position.board_size.x or piece.coordinate.y >= position.board_size.y:
			report.structural_errors.append("Piece coordinate out of bounds: %s" % piece.coordinate)
		if occupied.has(piece.coordinate):
			report.structural_errors.append("Duplicate occupancy at %s" % piece.coordinate)
		occupied[piece.coordinate] = true
		if not piece.piece_id.is_empty():
			if piece_ids.has(piece.piece_id): report.structural_errors.append("Duplicate piece id: %s" % piece.piece_id)
			piece_ids[piece.piece_id] = true
		if piece.max_hp <= 0 or piece.current_hp < 0 or piece.current_hp > piece.max_hp:
			report.structural_errors.append("Invalid HP at %s" % piece.coordinate)
		if piece.stun_timer < 0 or piece.current_cooldown < 0:
			report.structural_errors.append("Negative timer at %s" % piece.coordinate)
		if piece.cooldown_reset_pending and piece.current_cooldown > 0:
			report.structural_errors.append("Active and pending cooldown overlap at %s" % piece.coordinate)
		if String(piece.type_id).ends_with("king") or piece.type_id == &"king":
			if kings.has(piece.color):
				kings[piece.color] += 1
	for effect in position.tile_effects:
		if effect == null or effect.effect_id.is_empty() or effect.type_id == &"" or effect.coordinate.x < 0 or effect.coordinate.y < 0 or effect.coordinate.x >= position.board_size.x or effect.coordinate.y >= position.board_size.y:
			report.structural_errors.append("Invalid tile effect.")
			continue
		if effect_ids.has(effect.effect_id): report.structural_errors.append("Duplicate tile effect id: %s" % effect.effect_id)
		effect_ids[effect.effect_id] = true
		if effect.owner_color not in ["white", "black"]: report.structural_errors.append("Invalid tile effect owner color.")
		if not effect.source_piece_id.is_empty() and not piece_ids.has(effect.source_piece_id): report.structural_errors.append("Tile effect source does not exist: %s" % effect.source_piece_id)
	for entity in position.autonomous_entities:
		if entity == null or entity.entity_id.is_empty() or entity.type_id == &"" or entity.coordinate.x < 0 or entity.coordinate.y < 0 or entity.coordinate.x >= position.board_size.x or entity.coordinate.y >= position.board_size.y:
			report.structural_errors.append("Invalid autonomous entity.")
			continue
		if entity_ids.has(entity.entity_id): report.structural_errors.append("Duplicate autonomous entity id: %s" % entity.entity_id)
		entity_ids[entity.entity_id] = true
		if entity.owner_color not in ["white", "black"]: report.structural_errors.append("Invalid autonomous entity owner color.")
		if not piece_ids.has(entity.source_piece_id): report.structural_errors.append("Autonomous entity source does not exist: %s" % entity.source_piece_id)
		if not piece_ids.has(entity.target_piece_id): report.structural_errors.append("Autonomous entity target does not exist: %s" % entity.target_piece_id)
	for color in ["white", "black"]:
		if kings[color] != 1:
			report.playability_errors.append("%s must have exactly one king (found %s)." % [color.capitalize(), kings[color]])
	return report
