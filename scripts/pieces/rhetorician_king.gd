extends KingPiece
class_name RhetoricianKing

const ACTIVE_ABILITY_NAME := "Can Logic Move Them?"
const ACTIVE_ABILITY_ID: StringName = &"can_logic_move_them"
const PASSIVE_ABILITY_NAME := "Can Words Prevent Harm?"

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "rhetorician_king"
	max_hp = 4
	current_hp = max_hp
	base_cooldown = 4
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return true
