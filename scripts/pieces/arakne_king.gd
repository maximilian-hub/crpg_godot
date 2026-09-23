extends KingPiece
class_name ArakneKing

const ACTIVE_ABILITY_NAME: String = "Spike Burst"
const ACTIVE_ABILITY_ID: StringName = &"spike_burst"
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
	self.active_ability_id = ACTIVE_ABILITY_ID
	self.passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()


## Initial selection exposes only ordinary King destinations. Empty adjacent
## destinations may then branch into a second, non-capturing diagonal step.
func get_legal_moves() -> Array:
	return super.get_legal_moves()


func get_skitter_destinations(intermediate: Vector2i) -> Array[Vector2i]:
	var destinations: Array[Vector2i] = []
	for offset in DIAGONAL_OFFSETS:
		var destination: Vector2i = intermediate + Vector2i(offset)
		if not model.is_in_bounds(destination.x, destination.y):
			continue
		var occupant: ModelPiece = model.board[destination.x][destination.y]
		# Before the path begins, Arakne still occupies its origin. Treat that
		# square as a legal return destination; it is empty after step one lands.
		if occupant == null or occupant == self:
			destinations.append(destination)
	return destinations


func can_begin_skitter(intermediate: Vector2i) -> bool:
	var delta := intermediate - coordinate
	return (
		absi(delta.x) <= 1
		and absi(delta.y) <= 1
		and delta != Vector2i.ZERO
		and model.is_in_bounds(intermediate.x, intermediate.y)
		and model.board[intermediate.x][intermediate.y] == null
	)


func get_legal_move_paths() -> Array:
	var paths: Array = []
	for intermediate: Vector2i in get_legal_moves():
		paths.append([intermediate])
		if not can_begin_skitter(intermediate):
			continue
		for destination in get_skitter_destinations(intermediate):
			paths.append([intermediate, destination])
	return paths


## Spike Burst can target one adjacent enemy piece.
func get_active_ability_targets() -> Array:
	var targets: Array = []

	for coord in model.get_adjacent_squares(coordinate):
		var piece: ModelPiece = model.board[coord.x][coord.y]
		if piece != null and is_enemy(piece):
			targets.append(coord)

	return targets


func has_active_ability() -> bool:
	return true


## Executes Spike Burst. The ChessBoardModel action resolver owns reaction
## processing and turn completion, just as it does for Minotaur and Necromancer.
func active_target_selected(coord: Vector2i) -> void:
	if not model.is_in_bounds(coord.x, coord.y):
		return

	var target_piece: ModelPiece = model.board[coord.x][coord.y]
	if target_piece == null or not is_enemy(target_piece):
		return

	await target_piece.take_damage(SPIKE_BURST_DAMAGE)
	schedule_cooldown()
