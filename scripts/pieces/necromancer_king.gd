extends KingPiece
class_name NecromancerKing

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "necromancer_king"
	max_hp = 2
	current_hp = max_hp
	base_cooldown = 2
	active_ability_name = "Summon Bone Pawn"
	active_ability_id = &"summon_bone_pawn"
	passive_ability_name = "Raise Dead"
	reset_cooldown()

func has_active_ability() -> bool:
	return true
