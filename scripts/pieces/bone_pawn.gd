##~~~~~~~~NEW FILE: bone_pawn.gd~~~~~~~~~~~~
extends ModelPiece
class_name BonePawn

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "bone_pawn"
