##~~~~~~~~NEW FILE: minotaur_king.gd~~~~~~~~~~~~
extends KingPiece # <-- Inherit from KingPiece now
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

# --- Overridden Methods ---

## Override: Calculate targets for the Charge ability.
func get_active_ability_targets() -> Array:
	# (This is the renamed 'get_charge_moves' logic)
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
			var target_piece = model.board[r][c] # Renamed 'target' to 'target_piece' for clarity

			if target_piece == null:
				empty_count += 1
				r += dir.x
				c += dir.y
			else: # Hit a piece
				# Can only target if >= 2 empty squares before it
				if empty_count >= 2:
					moves.append(Vector2i(r, c))
				break # Stop searching in this direction

		# Check if we hit a wall after >= 2 empty squares
		# Add the last valid empty square as a target (for wall impact)
		if empty_count >= 2 and not model.is_in_bounds(r, c):
			# The last valid square was before hitting the boundary
			var last_valid_square = Vector2i(r - dir.x, c - dir.y)
			if model.board[last_valid_square.x][last_valid_square.y] == null: # Ensure it's actually empty
				moves.append(last_valid_square)

	return moves

## Override: Execute the Charge ability when a target is selected.
func active_target_selected(coord: Vector2i):
	var target_piece = model.board[coord.x][coord.y]
	
	view.aura_loop_player.stop()

	charge(coord)

	# --- Post-Ability Actions ---
	reset_cooldown() # Reset cooldown using the inherited method
	model.switch_turn() # Consume the turn



# --- Minotaur-Specific Methods ---

## The actual mechanics of moving and potentially stunning.
func charge(coord: Vector2i):
	var target_piece = model.board[coord.x][coord.y] # Check again inside charge

	if target_piece != null:
		if target_piece.is_king:
			target_piece.take_damage(2) # Example: Charge does extra damage to kings?
		else:
			model.destroy_piece(target_piece, true)
			model.board[coord.x][coord.y] = null
	
	model.actually_move_piece(self, coord)

	if target_piece == null: stun()
	# TODO: Add wall impact sound/visual effect

## Override take_damage to include Retaliating Rage passive.
func take_damage(damage: int = 1):
	super.take_damage(damage) 
	if current_hp > 0: retaliating_rage()

func retaliating_rage() -> void:
	if stunned: return
	emit_signal("piece_started_ability", self, passive_ability_name) # trigger animation
	await view.rage_intro_animation_completed  # wait for animation to finish
	_perform_rage_damage()

func _perform_rage_damage() -> void:
	var exploded_squares: Array = [] # for the view
	var adjacent_squares = model.get_adjacent_squares(coordinate)

	for adj_coord in adjacent_squares:
		exploded_squares.append(adj_coord)
		var target = model.board[adj_coord.x][adj_coord.y]
		if target != null: target.take_damage(1) 

	emit_signal("passive_ability_effect", self, passive_ability_name, exploded_squares) 
	model.process_selection_queue()


func _on_active_selected():
	view.spawn_ss_aura(view_node) # move to own view
