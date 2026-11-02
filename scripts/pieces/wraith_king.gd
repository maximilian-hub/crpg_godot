extends KingPiece
class_name WraithKing

const ACTIVE_ABILITY_NAME := "Summon Wraith"
const ACTIVE_ABILITY_ID: StringName = &"summon_wraith"
const PASSIVE_ABILITY_NAME := "Lingering Malice"
const SUMMON_WRAITH_DAMAGE := 1
const WRAITH_MOVE_INTERVAL_ROUNDS := 3
const MAX_ACTIVE_WRAITHS := 2

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "wraith_king"
	max_hp = 4
	current_hp = max_hp
	base_cooldown = 0
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return true
