extends ArcherKing
class_name ArcherKingQuiver

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "archer_king_quiver"
	archer_variant = VARIANT_QUIVER
