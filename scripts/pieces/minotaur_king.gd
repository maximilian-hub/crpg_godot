##~~~~~~~~NEW FILE: minotaur_king.gd~~~~~~~~~~~~
extends KingPiece
class_name MinotaurKing

signal piece_started_ability(piece: KingPiece, ability_name: String)
signal passive_ability_effect(piece: KingPiece, ability_name: String, affected_coords: Array)

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

## Executes Charge, but the Model's action resolver owns turn completion.
func active_target_selected(coord: Vector2i):
	view.aura_loop_player.stop()
	await charge(coord)
	reset_cooldown()

func charge(coord: Vector2i):
	var target_piece: ModelPiece = model.board[coord.x][coord.y]
	var hit_wall := target_piece == null

	if target_piece != null:
		if target_piece.is_king:
			await target_piece.take_damage(2)
			# A surviving king still occupies the destination; do not overwrite it.
			if target_piece.current_hp > 0:
				return
		else:
			model.destroy_piece(target_piece, true)

	await model.actually_move_piece(self, coord)

	if hit_wall:
		stun()

## Damage must await Retaliating Rage so the original action cannot finish early.
func take_damage(damage: int = 1):
	super.take_damage(damage)
	if current_hp > 0:
		await retaliating_rage()

func retaliating_rage() -> void:
	if stunned:
		return
	emit_signal("piece_started_ability", self, passive_ability_name)
	await view.rage_intro_animation_completed
	await _perform_rage_damage()

func _perform_rage_damage() -> void:
	var exploded_squares: Array = []
	var adjacent_squares = model.get_adjacent_squares(coordinate)

	for adj_coord in adjacent_squares:
		exploded_squares.append(adj_coord)
		var target: ModelPiece = model.board[adj_coord.x][adj_coord.y]
		if target != null:
			await target.take_damage(1)

	emit_signal("passive_ability_effect", self, passive_ability_name, exploded_squares)

func _on_active_selected():
	view.spawn_ss_aura(view_node)

func _on_active_deselected(play_powerdown_sound: bool = false):
	view.fade_out_ss_aura(view_node, play_powerdown_sound)
