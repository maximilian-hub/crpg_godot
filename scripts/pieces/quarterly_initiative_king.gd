extends KingPiece
class_name QuarterlyInitiativeKing

const ACTIVE_ABILITY_NAME := "Stakeholder Pandering"
const ACTIVE_ABILITY_ID: StringName = &"stakeholder_pandering"

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "quarterly_initiative_king"
	max_hp = 4
	current_hp = max_hp
	base_cooldown = 2
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = "Efficiency / Performance Cycle"
	reset_cooldown()

func has_active_ability() -> bool:
	return true

func get_legal_moves() -> Array:
	var moves := super.get_legal_moves()
	for coord in model.get_adjacent_squares(coordinate):
		var occupant: ModelPiece = model.board[coord.x][coord.y]
		if occupant != null and occupant.color == color and coord not in moves:
			moves.append(coord)
	return moves

func get_active_ability_targets() -> Array:
	var targets: Array = []
	for row in model.board:
		for piece in row:
			if piece != null and piece.color == color and piece != self:
				targets.append(piece.coordinate)
	return targets

func active_target_selected(target: Vector2i) -> void:
	var piece: ModelPiece = model.board[target.x][target.y]
	if piece == null or piece.color != color or piece == self:
		return
	if model.global_turn_number % 4 != 0:
		await take_damage(1)
		if not model.is_piece_active(self):
			return
	var movement_type: StringName = await model.request_movement_type_grant(self, piece)
	if movement_type == &"":
		return
	piece.grant_movement_type(movement_type)
	schedule_cooldown()
