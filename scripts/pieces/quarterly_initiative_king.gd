extends KingPiece
class_name QuarterlyInitiativeKing

const ACTIVE_ABILITY_NAME := "Stakeholder Pandering"
const ACTIVE_ABILITY_ID: StringName = &"stakeholder_pandering"

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "quarterly_initiative_king"
	max_hp = 4
	current_hp = max_hp
	base_cooldown = 2
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = "Efficiency / Performance Cycle"
	reset_cooldown()

func has_active_ability() -> bool:
	return true
