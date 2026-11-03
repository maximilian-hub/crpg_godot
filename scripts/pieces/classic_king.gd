extends KingPiece
class_name ClassicKing

## Intended to function as a real king piece in real chess.

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "king"
	
## Classic King deliberately uses Chess RPG's universal damage rules. Threatened
## squares remain legal destinations, and a player may accept damage for tempo or
## position. There is no orthodox forced-check or illegal-into-check exception.
