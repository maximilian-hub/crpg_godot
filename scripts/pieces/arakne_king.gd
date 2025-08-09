extends KingPiece
class_name ArakneKing

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "arakne_king"
	self.max_hp = 3
	self.current_hp = self.max_hp
	self.base_cooldown = 1
	self.active_ability_name = "Spike Burst"
	self.passive_ability_name = "Skittering Steps"

func get_legal_moves() -> Array:
	var standard_moves = super.get_legal_moves()
	var skitter_moves := []

	for move in standard_moves:
		var piece_at_move = model.board[move.x][move.y]
		if piece_at_move == null:
			# This is a standard move to an empty square, so we can skitter from here.
			var diagonal_offsets = [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]
			for offset in diagonal_offsets:
				var skitter_coord = move + offset
				if model.is_in_bounds(skitter_coord.x, skitter_coord.y):
					var piece_at_skitter = model.board[skitter_coord.x][skitter_coord.y]
					if piece_at_skitter == null:
						skitter_moves.append(skitter_coord)

	# Combine and remove duplicates, just in case.
	var all_moves = standard_moves + skitter_moves
	var unique_moves = []
	for move in all_moves:
		if not move in unique_moves:
			unique_moves.append(move)

	return unique_moves

func get_active_ability_targets() -> Array:
	var targets = []
	var adjacent_squares = model.get_adjacent_squares(coordinate)
	for coord in adjacent_squares:
		var piece = model.board[coord.x][coord.y]
		if piece != null and is_enemy(piece):
			targets.append(coord)
	return targets

func active_target_selected(coord: Vector2i):
	var target_piece = model.board[coord.x][coord.y]
	if target_piece != null:
		target_piece.take_damage(1)

	reset_cooldown()
	model.switch_turn()

#TODO: MAN it really feels like these shouldn't be here. Aren't these king scripts supposed to be the Model?? 
# and yet here's view stuff 😖
func _on_active_selected():
	#TODO: add visual effect here
	return

func _on_active_deselected(play_powerdown_sound: bool = false):
	#view.fade_out_ss_aura(view_node, play_powerdown_sound)
	#TODO: add visual effect here
	return
