extends KingPiece
class_name ArcherKing

const ACTIVE_ABILITY_NAME := "Volley of Arrows"
const ACTIVE_ABILITY_ID: StringName = &"volley_of_arrows"
const PASSIVE_ABILITY_NAME := "Sharpshooter"
const ACTIVE_ABILITY_COOLDOWN := 4
const VOLLEY_SQUARE_COUNT := 6

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "archer_king"
	max_hp = 2
	current_hp = max_hp
	base_cooldown = ACTIVE_ABILITY_COOLDOWN
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func get_legal_moves() -> Array:
	var moves: Array = []
	var attack_position := get_live_attack_position()
	for row in range(model.board.size()):
		for column in range(model.board[row].size()):
			var target := Vector2i(row, column)
			var distance := maxi(absi(target.x - coordinate.x), absi(target.y - coordinate.y))
			var occupant: ModelPiece = model.board[row][column]
			if distance == 1 and occupant == null:
				moves.append(target)
			elif can_natively_attack_square(coordinate, target, attack_position) and occupant != null and occupant.color != color:
				moves.append(target)
	return moves

func can_natively_attack_square(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	if not position.is_in_bounds(target):
		return false
	var delta := target - origin
	var distance := maxi(absi(delta.x), absi(delta.y))
	if distance < 2 or distance > 4:
		return false
	return position.get_visibility_map(origin).has(target)

func has_active_ability() -> bool:
	return true

func get_active_ability_targets() -> Array:
	return [coordinate]

func active_target_selected(target: Vector2i) -> void:
	if target != coordinate:
		return
	schedule_cooldown()
	await model.resolve_archer_volley(self)
