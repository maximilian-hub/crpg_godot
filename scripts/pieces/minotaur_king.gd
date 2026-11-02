extends KingPiece
class_name MinotaurKing

const PASSIVE_ABILITY_NAME := "Retaliating Rage"
const ACTIVE_ABILITY_NAME := "Charge"
const ACTIVE_ABILITY_ID: StringName = &"charge"
const ACTIVE_ABILITY_COOLDOWN := 4

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "minotaur_king"
	max_hp = 4
	current_hp = max_hp
	base_cooldown = ACTIVE_ABILITY_COOLDOWN
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return true
