#~~~~~~~~NEW FILE: minotaur_king.gd~~~~~~~~~~~~
extends ModelPiece
class_name MinotaurKing

# TODO: Make a KingPiece class to generalize cooldown functionality.
# TODO: Maybe? Make an Ability class to hold ability data like CDs, name, perform()

const PASSIVE_NAME: String = "Retaliating Rage"
const ACTIVE_NAME: String = "Charge"
const CHARGE_COOLDOWN: int = 4					# KingPiece class
var current_cooldown: int = CHARGE_COOLDOWN						# KingPiece class


func _init(color: String, coord: Vector2i):
	self.color = color
	self.coordinate = coord
	self.max_hp = 4
	self.current_hp = 4
	self.type = "minotaur_king"
	

func take_damage(damage: int = 1):
	super.take_damage()
	if current_hp > 0: retaliating_rage()

func retaliating_rage() -> void:
	if stunned: return # don't retaliate if stunned
	
	await view.start_minotaur_rage_intro(coordinate) #what's this do?

	var board = model.board
	var exploded_squares: Array = []

	var adjacent_squares = model.get_adjacent_squares(coordinate)

	for coord in adjacent_squares:
		if coord.x >= 0 and coord.x < board.size() and coord.y >= 0 and coord.y < board[coord.x].size():
			exploded_squares.append(coord)

			var target = board[coord.x][coord.y]
			if target != null:
				target.take_damage()

	view.minotaur_retaliate(coordinate, exploded_squares)

# KingPiece class
func set_cooldown(x: int):
	current_cooldown = x
	if current_cooldown > 0: 
		view.update_cooldown(self)
	else: view.ready_cooldown(self)

# KingPiece class
func reset_cooldown():
	set_cooldown(CHARGE_COOLDOWN)

# KingPiece class
func decrement_cooldown():
	if current_cooldown > 0: set_cooldown(current_cooldown - 1)

# KingPiece class
func _on_turn_changed(current_turn: String):
	super._on_turn_changed(current_turn)
	if current_turn == color: decrement_cooldown()

func get_charge_moves() -> Array:
	var row = coordinate.x
	var col = coordinate.y
	var moves := []
	var directions = [
		Vector2i(-1, 0),  # up
		Vector2i(1, 0),   # down
		Vector2i(0, 1),   # right
		Vector2i(0, -1),  # left
	]

	for dir in directions:
		var r = row + dir.x
		var c = col + dir.y
		var empty_count = 0

		while model.is_in_bounds(r, c):
			var target = model.board[r][c]

			if target == null:
				empty_count += 1
				r += dir.x
				c += dir.y
			else:
				if empty_count >= 2:
					moves.append(Vector2i(r, c))
				break  # stop after first piece

		# Optionally: if we hit the wall after 2+ empties
		if empty_count >= 2 and not model.is_in_bounds(r, c):
			var last = Vector2i(r - dir.x, c - dir.y)
			moves.append(last)

	return moves

## Called when a target is selected for the active ability.
# inherited from KingPiece class?
# @require coord is a legal move
func active_target_selected(coord: Vector2i):
	charge(coord)

## Sends Minotaur King charging to the specified square.
# If there is a piece there, combat ensues.
# If not, it means he's hitting a wall and gets stunned.
func charge(coord: Vector2i):
	var target = model.board[coord.x][coord.y]
	
	if target != null: target.destroy()
		
	model.actually_move_piece(self, coord) # TODO implement injecting unique animations
	
	if target == null: stun() # hitting a wall
	reset_cooldown()
	model.switch_turn()
