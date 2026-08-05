extends KingPiece
class_name ArakneKing

const ACTIVE_ABILITY_NAME: String = "Spike Burst"
const PASSIVE_ABILITY_NAME: String = "Skittering Steps"
const ACTIVE_ABILITY_COOLDOWN: int = 1
const SPIKE_BURST_DAMAGE: int = 1

const DIAGONAL_OFFSETS = [
	Vector2i(-1, -1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(1, 1),
]

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "arakne_king"
	self.max_hp = 2
	self.current_hp = self.max_hp
	self.base_cooldown = ACTIVE_ABILITY_COOLDOWN
	self.active_ability_name = ACTIVE_ABILITY_NAME
	self.passive_ability_name = PASSIVE_ABILITY_NAME


## In addition to normal King movement, Arakne can move diagonally from an
## adjacent empty square. The intermediate and destination squares must be empty.
##
## Only genuinely adjacent squares can begin a skitter. This deliberately avoids
## treating a castling destination from super.get_legal_moves() as the first step.
func get_legal_moves() -> Array:
	var standard_moves: Array = super.get_legal_moves()
	var all_moves: Array = standard_moves.duplicate()

	for intermediate_coord in model.get_adjacent_squares(coordinate):
		if model.board[intermediate_coord.x][intermediate_coord.y] != null:
			continue

		for offset in DIAGONAL_OFFSETS:
			var skitter_coord: Vector2i = intermediate_coord + offset
			if not model.is_in_bounds(skitter_coord.x, skitter_coord.y):
				continue
			if model.board[skitter_coord.x][skitter_coord.y] != null:
				continue
			if skitter_coord not in all_moves:
				all_moves.append(skitter_coord)

	return all_moves


## Spike Burst can target one adjacent enemy piece.
func get_active_ability_targets() -> Array:
	var targets: Array = []

	for coord in model.get_adjacent_squares(coordinate):
		var piece: ModelPiece = model.board[coord.x][coord.y]
		if piece != null and is_enemy(piece):
			targets.append(coord)

	return targets


## Executes Spike Burst. The ChessBoardModel action resolver owns reaction
## processing and turn completion, just as it does for Minotaur and Necromancer.
func active_target_selected(coord: Vector2i) -> void:
	if not model.is_in_bounds(coord.x, coord.y):
		return

	var target_piece: ModelPiece = model.board[coord.x][coord.y]
	if target_piece == null or not is_enemy(target_piece):
		return

	await target_piece.take_damage(SPIKE_BURST_DAMAGE)
	reset_cooldown()


## Targeting presentation hooks. These can remain empty until Arakne receives
## an aura or other selection effect in the view layer.
func _on_active_selected() -> void:
	pass


func _on_active_deselected(_play_powerdown_sound: bool = false) -> void:
	pass
