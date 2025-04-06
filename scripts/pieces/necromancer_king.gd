#~~~~~~~~ NEW FILE: necromancer_king.gd ~~~~~~~~
extends KingPiece # and KingPiece extends ModelPiece
class_name NecromancerKing

const BonePawn = preload("res://scripts/pieces/bone_pawn.gd")

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "necromancer_king"
	self.max_hp = 2
	self.current_hp = self.max_hp
	self.base_cooldown = 2
	self.active_ability_name = "Summon Bone Pawn"
	self.passive_ability_name = "Raise Dead"

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

func _on_piece_destroyed(destroyed_piece: ModelPiece):
	# Active Rase Dead only if the destroyed piece is a major or minor piece.
	for base_type in model.MAJOR_MINOR_BASE_TYPES:
		if destroyed_piece.type.contains(base_type):
			raise_dead(destroyed_piece) 

func raise_dead(dead_piece: ModelPiece):
	var raisable_squares = model.get_empty_adjacent_squares(dead_piece.coordinate)	
	controller.initiate_non_move_selection_mode(self, raisable_squares)

	# Now that non_move_selection_mode has been initiated,
	# if user selects a square,
	# a bone pawn will be summoned from _on_target_selected().
	
	## TODO: make this work if both players have Necro King
	# Okay, say I'm white and you're black, and it's my turn.
	# I take your Knight. What happens?
		# We each get to choose to summon a bone pawn.
	# Who goes first? 
		# Whoever's piece was taken goes first.
		# TODO: I'll add an aura around the summoning king to make it clear who's summoning.
	
	# So how does this work?
		# model emits piece_destroyed
		# each necro's _on_piece_destroyed is called, which calls raise_dead 
		# to start the selection mode.
			# i'm not sure who's currently winning, but one overrides and skips past the other.
		# maybe the model can have a queue of user selections.
			# instead of _on_piece_destroyed() called raise_dead(),
			# it can send a thingy... to the model queue.
				# what's the thingy? can i just send the function along with its parameter somehow?
			
			# one way or another, this adding to the queue triggers the model to cycle through
			# selection modes until they are done.
	
	
	
	## TODO: handle multiple pieces dying at once, eg from Minotaur King's Retaliate
	## TODO: should we disallow summoning on the final rank, or let them wither immediately?

## Called when a summon target is selected.
# Assumes the target is empty.
func _on_special_target_selected(coord: Vector2i):
	summon_bone_pawn(coord)
	if model.current_turn == self.color: model.switch_turn() # If you choose to Raise Dead when your turn is coming up, your turn is skipped.
	
