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
		if piece.max_hp <= 0 or piece.current_hp < 0 or piece.current_hp > piece.max_hp:
			report.structural_errors.append("Invalid HP at %s" % piece.coordinate)
		if piece.stun_timer < 0 or piece.current_cooldown < 0:
			report.structural_errors.append("Negative timer at %s" % piece.coordinate)
		if String(piece.type_id).ends_with("king") or piece.type_id == &"king":
			if kings.has(piece.color):
				kings[piece.color] += 1
	for color in ["white", "black"]:
		if kings[color] != 1:
			report.playability_errors.append("%s must have exactly one king (found %s)." % [color.capitalize(), kings[color]])
	return report
