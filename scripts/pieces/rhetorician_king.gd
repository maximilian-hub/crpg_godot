extends KingPiece
class_name RhetoricianKing

const ACTIVE_ABILITY_NAME := "Can Logic Move Them?"
const ACTIVE_ABILITY_ID: StringName = &"can_logic_move_them"
const PASSIVE_ABILITY_NAME := "Can Words Prevent Harm?"

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "rhetorician_king"
	max_hp = 4
	current_hp = max_hp
	base_cooldown = 4
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return true

func get_active_ability_targets() -> Array:
	var targets: Array = []
	if model == null:
		return targets
	for row in model.board:
		for piece in row:
			if piece == null or piece.color == color:
				continue
			var delta: Vector2i = piece.coordinate - coordinate
			var distance := maxi(absi(delta.x), absi(delta.y))
			# An adjacent piece has no distinct square closer to the King.
			if distance == 2:
				targets.append(piece.coordinate)
	return targets

func active_target_selected(target: Vector2i) -> void:
	if model == null or not model.is_in_bounds(target.x, target.y):
		return
	var target_piece: ModelPiece = model.board[target.x][target.y]
	if target_piece == null or target_piece.color == color:
		return
	schedule_cooldown()
	await model.compel_piece_toward(target_piece, self)
