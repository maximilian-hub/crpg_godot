extends ModelPiece
class_name Knight

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "knight"
