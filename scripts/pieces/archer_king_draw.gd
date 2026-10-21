extends ArcherKing
class_name ArcherKingDraw

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "archer_king_draw"
	archer_variant = VARIANT_DRAW
