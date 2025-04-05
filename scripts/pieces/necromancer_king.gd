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
	return model.get_empty_squares_to_furthest_rank(self.color)

## Active: Execute the Summon Bone Pawn ability.
func active_target_selected(target: Vector2i):
	summon_bone_pawn(target)
	reset_cooldown() 
	model.switch_turn() 

func summon_bone_pawn(target: Vector2i):
	var new_pawn = BonePawn.new(self.color, target)
	new_pawn.model = self.model 
	new_pawn.view = self.view   
	model.connect("turn_changed", new_pawn._on_turn_changed)
	model.board[target.x][target.y] = new_pawn
	view.add_piece_node(new_pawn) # Use the new function in ChessBoard


func _on_piece_destroyed(piece: ModelPiece):
	var raisable_piece = false

	for base_type in model.MAJOR_MINOR_BASE_TYPES:
		if piece.type.contains(base_type):
			raisable_piece = true
			break 
	if raisable_piece:
		var raisable_squares = model.get_adjacent_squares(piece.coordinate)	
		controller.initiate_non_move_selection_mode(self, raisable_squares)
	
	# Now that non_move_selection_mode has been initiated,
	# if user selects a square,
	# a bone pawn will be summoned from _on_target_selected().

## Called when a 
func _on_special_target_selected(coord: Vector2i):
	summon_bone_pawn(coord)
	

#
### Passive: Raise Dead - Called by ModelPiece.destroy() when a non-king, non-bone-pawn piece dies.
#func _on_other_piece_destroyed(destroyed_piece: ModelPiece):
	## This check is redundant if ModelPiece.destroy() already filters, but safe to keep.
	#if destroyed_piece.is_king or destroyed_piece.type == "bone_pawn":
		#return
	#if not is_instance_valid(model) or not is_instance_valid(view):
		#printerr("NecromancerKing: Missing model or view reference for passive ability.")
		#return
#
	#print("Necromancer '%s' passive 'Raise Dead' triggered by death of %s '%s' at %s" % [color, destroyed_piece.color, destroyed_piece.type, destroyed_piece.coordinate])
#
	#var adjacent_empty_squares = []
	#var potential_squares = model.get_adjacent_squares(destroyed_piece.coordinate)
#
	## Find all adjacent squares that are currently empty
	#for sq in potential_squares:
		## Need to check bounds again just in case get_adjacent_squares gives invalid coords (it shouldn't but safety first)
		#if model.is_in_bounds(sq.x, sq.y) and model.board[sq.x][sq.y] == null:
			#adjacent_empty_squares.append(sq)
#
	#if adjacent_empty_squares.is_empty():
		#print("Raise Dead: No empty adjacent squares to summon Bone Pawn.")
		#return # No place to summon
#
	## --- Summoning Logic ---
	## Option A (Simple): Summon on the first available empty adjacent square found.
	#var summon_coord = adjacent_empty_squares[0]
#
	## Option B (Complex/Future):
	## - Signal Controller/View to highlight 'adjacent_empty_squares'.
	## - Enter a state waiting for player input on one of those squares.
	## - Controller handles the click, calls back to a method like 'passive_target_selected(coord)'.
	## - Perform summon logic there.
	## For now, we use Option A.
#
	#print("Raise Dead: Summoning Bone Pawn at %s" % summon_coord)
#
	## --- Perform Summon (using Option A logic) ---
	#var new_pawn = BonePawn.new(self.color, summon_coord)
	#new_pawn.model = self.model
	#new_pawn.view = self.view
	#model.connect("turn_changed", new_pawn._on_turn_changed)
	## Connect any other necessary signals
#
	#model.board[summon_coord.x][summon_coord.y] = new_pawn
#
	#if view.has_method("add_piece_node"):
		#view.add_piece_node(new_pawn)
	#else:
		#printerr("NecromancerKing (Raise Dead): View reference invalid or lacks add_piece_node method.")
#
	## Passive ability typically does NOT cost a turn or cooldown.
