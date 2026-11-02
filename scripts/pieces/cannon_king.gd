extends KingPiece
class_name CannonKing

const ACTIVE_ABILITY_NAME := "Arc Mortar"
const ACTIVE_ABILITY_ID: StringName = &"arc_mortar"
const PASSIVE_ABILITY_NAME := "Calculated Trajectory"
const ARC_MORTAR_DAMAGE := 1
const ARC_MORTAR_RANGE := 5
const ARC_MORTAR_DELAY_ROUNDS := 3

var scheduled_arc_cooldown := 4

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "cannon_king"
	max_hp = 5
	current_hp = max_hp
	base_cooldown = 4
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return true

func capture_custom_state() -> Dictionary:
	return {"scheduled_arc_cooldown": scheduled_arc_cooldown}

func restore_custom_state(state: Dictionary) -> void:
	scheduled_arc_cooldown = int(state.get("scheduled_arc_cooldown", base_cooldown))
