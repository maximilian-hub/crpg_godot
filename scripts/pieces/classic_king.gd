extends KingPiece
class_name ClassicKing

## Intended to function as a real king piece in real chess.

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "king"
	
#### TODO: implement abilities?
## Passive: Check
# Think it would be fun to apply checking rules to Classic King,
# ie when he's threatened, you have to make a move to get him out of Check,
# you can't move into Check, etc..
#
# It could be really interesting to have this apply to 
# enemy RPG Kings as well. 
#
## Active: none?
# I can't think of any actives that wouldn't interfere
# with the spirit of the concept.
