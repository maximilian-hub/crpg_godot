extends ArcherKing
class_name ArcherKingCombination

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "archer_king_combination"
	archer_variant = VARIANT_COMBINATION
