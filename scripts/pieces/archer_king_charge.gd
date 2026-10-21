extends ArcherKing
class_name ArcherKingCharge

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "archer_king_charge"
	archer_variant = VARIANT_CHARGE
