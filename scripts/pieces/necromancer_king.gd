extends KingPiece
class_name NecromancerKing

const BASE_COOLDOWN_NECROMANCER = 2
const ACTIVE_NAME_NECROMANCER = "Summon Bone Pawn"

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "necromancer_king"
	self.max_hp = 2
	self.current_hp = self.max_hp 
	self.base_cooldown = BASE_COOLDOWN_NECROMANCER
	self.active_ability_name = ACTIVE_NAME_NECROMANCER
