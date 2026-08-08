##~~~~~~~~NEW FILE: minotaur_king.gd~~~~~~~~~~~~
extends KingPiece
class_name MinotaurKing

const PASSIVE_ABILITY_NAME: String = "Retaliating Rage"
const ACTIVE_ABILITY_NAME: String = "Charge"
const ACTIVE_ABILITY_COOLDOWN = 4

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "minotaur_king"
	self.max_hp = 4
	self.current_hp = self.max_hp
	self.base_cooldown = 4
	self.active_ability_name = "Charge"
	self.passive_ability_name = "Retaliating Rage"

func get_active_ability_targets() -> Array:
	var row = coordinate.x
	var col = coordinate.y
	var moves := []
	var directions = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]

	for dir in directions:
		var r = row + dir.x
		var c = col + dir.y
		var empty_count = 0

		while model.is_in_bounds(r, c):
			var target_piece = model.board[r][c]
			if target_piece == null:
				empty_count += 1
				r += dir.x
				c += dir.y
			else:
				if empty_count >= 2:
					moves.append(Vector2i(r, c))
				break

		if empty_count >= 2 and not model.is_in_bounds(r, c):
			var last_valid_square = Vector2i(r - dir.x, c - dir.y)
			if model.board[last_valid_square.x][last_valid_square.y] == null:
				moves.append(last_valid_square)

	return moves

func has_active_ability() -> bool:
	return true

## Executes Charge, but the Model's action resolver owns turn completion.
func active_target_selected(coord: Vector2i):
	await charge(coord)
	reset_cooldown()

func charge(coord: Vector2i):
	var target_piece: ModelPiece = model.board[coord.x][coord.y]
	var hit_wall := target_piece == null

	if target_piece != null:
		if target_piece.is_king:
			await target_piece.take_damage(2)
			# Stop on the final empty square when the defending king survives.
			if target_piece.current_hp > 0:
				var direction := Vector2i(
					sign(coord.x - coordinate.x),
					sign(coord.y - coordinate.y)
				)
				await model.actually_move_piece(self, coord - direction)
				return
		else:
			model.destroy_piece(target_piece, true)

	await model.actually_move_piece(self, coord)

	if hit_wall:
		stun()

## Every surviving hit queues one Rage. The Model resolves it later, so
## adjacent Minotaurs can alternate without recursively nesting function calls.
func take_damage(damage: int = 1):
	super.take_damage(damage)
	if current_hp > 0 and not stunned:
		model.queue_selection_opportunity(self, "retaliating_rage", null)

## Called by the Model when this automatic reaction reaches the front of the queue.
func resolve_automatic_reaction(action_type: String, event_data) -> void:
	if action_type == "retaliating_rage":
		await retaliating_rage()

func retaliating_rage() -> void:
	if stunned:
		return
	await model.announce_ability_started(self, passive_ability_name)
	await _perform_rage_damage()

func _perform_rage_damage() -> void:
	var exploded_squares: Array = []
	var adjacent_squares = model.get_adjacent_squares(coordinate)

	for adj_coord in adjacent_squares:
		exploded_squares.append(adj_coord)
		var target: ModelPiece = model.board[adj_coord.x][adj_coord.y]
		if target != null:
			target.take_damage(1)

	model.ability_effect_resolved.emit(self, passive_ability_name, exploded_squares)
