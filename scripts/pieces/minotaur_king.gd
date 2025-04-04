##~~~~~~~~NEW FILE: minotaur_king.gd~~~~~~~~~~~~
extends KingPiece # <-- Inherit from KingPiece now
class_name MinotaurKing

signal piece_started_ability(piece: KingPiece, ability_name: String)
signal passive_ability_effect(piece: KingPiece, ability_name: String, affected_coords: Array)

# Specific constants for the Minotaur King
const PASSIVE_NAME: String = "Retaliating Rage"
const ACTIVE_NAME_MINOTAUR: String = "Charge" # Use a specific const name
const BASE_COOLDOWN_MINOTAUR: int = 4 # Use a specific const name

func _init(color: String, coord: Vector2i):
	# Call the KingPiece constructor, passing the specific type
	super._init(color, "minotaur_king", coord)

	# Set Minotaur-specific properties
	self.max_hp = 4
	self.current_hp = self.max_hp # Use self.max_hp after it's set
	self.base_cooldown = BASE_COOLDOWN_MINOTAUR # Set the specific base cooldown
	self.active_ability_name = ACTIVE_NAME_MINOTAUR # Set the specific ability name

	# Ensure cooldown starts ready (or set to base_cooldown if preferred)
	set_cooldown(0) # Explicitly set initial state via the proper method


# --- Overridden Methods ---

## Provide the specific name for this King's ability.
func get_active_ability_name() -> String:
	return ACTIVE_NAME_MINOTAUR

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
	# --- Minotaur Charge Logic ---
	var target_piece = model.board[coord.x][coord.y]

	# Visuals/Sound: Stop the looping aura sound *before* the action
	# This ideally should be signaled, but keeping original logic for now
	if view and view.has_method("get_node") and view.get_node("AuraLoopPlayer"): # Safety checks
		view.aura_loop_player.stop()

	# Core charge logic
	charge(coord)

	# --- Post-Ability Actions ---
	reset_cooldown() # Reset cooldown using the inherited method
	if model: # Safety check
		model.switch_turn() # Consume the turn
	else:
		printerr("MinotaurKing cannot switch turn, model reference is null.")


# --- Minotaur-Specific Methods ---

## The actual mechanics of moving and potentially stunning.
func charge(coord: Vector2i):
	var target_piece = model.board[coord.x][coord.y] # Check again inside charge

	if target_piece != null:
		# Combat happens *before* moving into the square
		# Assuming charge instantly destroys non-King pieces for now
		# TODO: Implement proper combat interaction if needed (HP, etc.)
		if target_piece.is_king:
			target_piece.take_damage(2) # Example: Charge does extra damage to kings?
		else:
			target_piece.destroy() # Instantly destroy non-kings
			# Set the target square to null *before* moving the minotaur there
			model.board[coord.x][coord.y] = null
	
	# Move the Minotaur King
	# Using model.actually_move_piece ensures board state is updated correctly
	# Pass null for pawn_node as Minotaur doesn't promote
	model.actually_move_piece(self, coord, null)

	# If target_piece was null, it means we charged into an empty square (hit a wall/end of path)
	if target_piece == null:
		stun() # Hitting a wall stuns the Minotaur
		# TODO: Add wall impact sound/visual effect via view signal

## Override take_damage to include Retaliating Rage passive.
func take_damage(damage: int = 1):
	var hp_before = current_hp
	super.take_damage(damage) # Call base take_damage logic (handles HP, destroy check)
	# Only retaliate if HP actually decreased and the piece is not destroyed
	if current_hp < hp_before and current_hp > 0:
		retaliating_rage()


func retaliating_rage() -> void:
	if stunned: return
	emit_signal("piece_started_ability", self, PASSIVE_NAME) # trigger animation
	await view.rage_intro_animation_completed  # wait for animation to finish
	_perform_rage_damage()

func _perform_rage_damage() -> void:
	var exploded_squares: Array = []
	var adjacent_squares = model.get_adjacent_squares(coordinate)

	for adj_coord in adjacent_squares:
		# No need for bounds check here IF get_adjacent_squares already does it
		exploded_squares.append(adj_coord)
		var target = model.board[adj_coord.x][adj_coord.y]
		if target != null:
			target.take_damage(1) # Standard rage damage

	# Use signal for View interaction (Recommended change)
	emit_signal("passive_ability_effect", self, PASSIVE_NAME, exploded_squares) # Signal view for effects
