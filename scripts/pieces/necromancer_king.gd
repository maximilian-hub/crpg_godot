#~~~~~~~~ In necromancer_king.gd ~~~~~~~~
extends KingPiece
class_name NecromancerKing

const BonePawn = preload("res://scripts/pieces/bone_pawn.gd")

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "necromancer_king"
	self.max_hp = 2
	self.current_hp = self.max_hp
	self.base_cooldown = 0
	self.active_ability_name = "Summon Bone Pawn"

# --- Overridden Methods ---


## Active: Summon Bone Pawn - Find empty squares up to the furthest rank occupied.
func get_active_ability_targets() -> Array:
	print("NK attempting to get target squares")
	var targets = model.get_empty_squares_to_furthest_rank(self.color)
	print(targets)
	return targets




#func get_active_ability_targets() -> Array:
	#var targets = []
#
	#var furthest_rank = -1
#
	## Determine the direction of "forward" based on color
	## White moves towards rank 0, Black moves towards rank 7 (on standard 8x8)
	## Find the rank closest to the *opponent's* side that contains one of our pieces.
	#if color == "white":
		#furthest_rank = model.board.size() - 1 # Start assuming furthest is the back rank
		#for r in range(model.board.size()):
			#for c in range(model.board[r].size()):
				#var piece = model.board[r][c]
				#if piece != null and piece.color == self.color:
					#furthest_rank = min(furthest_rank, r) # Find the smallest row index (closest to rank 0)
	#else: # black
		#furthest_rank = 0 # Start assuming furthest is the back rank (rank 0)
		#for r in range(model.board.size()):
			#for c in range(model.board[r].size()):
				#var piece = model.board[r][c]
				#if piece != null and piece.color == self.color:
					#furthest_rank = max(furthest_rank, r) # Find the largest row index (closest to rank 7)
#
	#if furthest_rank == -1: # Should only happen if only the king exists, maybe?
		## Default to king's rank if no other pieces found? Or return empty?
		## Let's allow summoning on the king's rank in this edge case.
		#furthest_rank = self.coordinate.x
		#print("NecromancerKing: No other pieces found, using King's rank for summon limit.")
#
#
	## Now find all empty squares between the Necromancer's starting rank and the furthest rank (inclusive)
	#if color == "white":
		## Iterate from furthest rank (e.g., 2) up to the starting rank (e.g., 7)
		#for r in range(furthest_rank, model.board.size()):
			#for c in range(model.board[r].size()):
				#if model.board[r][c] == null:
					#targets.append(Vector2i(r, c))
	#else: # black
		## Iterate from starting rank (e.g., 0) up to the furthest rank (e.g., 5)
		#for r in range(furthest_rank + 1): # range is exclusive of end, so add 1
			#for c in range(model.board[r].size()):
				#if model.board[r][c] == null:
					#targets.append(Vector2i(r, c))
#
	#return targets

## Active: Execute the Summon Bone Pawn ability.
func active_target_selected(target: Vector2i):
	print("Necromancer %s summoning Bone Pawn at %s" % [color, target])

	# 1. Create the BonePawn model instance
	var new_pawn = BonePawn.new(self.color, target)
	new_pawn.model = self.model 
	new_pawn.view = self.view   

	# 2. Connect signals (like turn changes for potential future BonePawn effects)
	model.connect("turn_changed", new_pawn._on_turn_changed)
	# Add any other necessary signal connections here (e.g., if BonePawns had health regen)

	# 3. Update the model board state
	model.board[target.x][target.y] = new_pawn

	# 4. Tell the View to create the visual representation
	if view.has_method("add_piece_node"):
		view.add_piece_node(new_pawn) # Use the new function in ChessBoard
	else:
		printerr("NecromancerKing: View reference invalid or lacks add_piece_node method.")

	# 5. Reset Cooldown & End Turn
	reset_cooldown() # Put the ability on cooldown
	model.switch_turn() # Consume the player's turn

# --- Passive Ability ---

## Passive: Raise Dead - Called by ModelPiece.destroy() when a non-king, non-bone-pawn piece dies.
func _on_other_piece_destroyed(destroyed_piece: ModelPiece):
	# This check is redundant if ModelPiece.destroy() already filters, but safe to keep.
	if destroyed_piece.is_king or destroyed_piece.type == "bone_pawn":
		return
	if not is_instance_valid(model) or not is_instance_valid(view):
		printerr("NecromancerKing: Missing model or view reference for passive ability.")
		return

	print("Necromancer '%s' passive 'Raise Dead' triggered by death of %s '%s' at %s" % [color, destroyed_piece.color, destroyed_piece.type, destroyed_piece.coordinate])

	var adjacent_empty_squares = []
	var potential_squares = model.get_adjacent_squares(destroyed_piece.coordinate)

	# Find all adjacent squares that are currently empty
	for sq in potential_squares:
		# Need to check bounds again just in case get_adjacent_squares gives invalid coords (it shouldn't but safety first)
		if model.is_in_bounds(sq.x, sq.y) and model.board[sq.x][sq.y] == null:
			adjacent_empty_squares.append(sq)

	if adjacent_empty_squares.is_empty():
		print("Raise Dead: No empty adjacent squares to summon Bone Pawn.")
		return # No place to summon

	# --- Summoning Logic ---
	# Option A (Simple): Summon on the first available empty adjacent square found.
	var summon_coord = adjacent_empty_squares[0]

	# Option B (Complex/Future):
	# - Signal Controller/View to highlight 'adjacent_empty_squares'.
	# - Enter a state waiting for player input on one of those squares.
	# - Controller handles the click, calls back to a method like 'passive_target_selected(coord)'.
	# - Perform summon logic there.
	# For now, we use Option A.

	print("Raise Dead: Summoning Bone Pawn at %s" % summon_coord)

	# --- Perform Summon (using Option A logic) ---
	var new_pawn = BonePawn.new(self.color, summon_coord)
	new_pawn.model = self.model
	new_pawn.view = self.view
	model.connect("turn_changed", new_pawn._on_turn_changed)
	# Connect any other necessary signals

	model.board[summon_coord.x][summon_coord.y] = new_pawn

	if view.has_method("add_piece_node"):
		view.add_piece_node(new_pawn)
	else:
		printerr("NecromancerKing (Raise Dead): View reference invalid or lacks add_piece_node method.")

	# Passive ability typically does NOT cost a turn or cooldown.
