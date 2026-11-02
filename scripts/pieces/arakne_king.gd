extends KingPiece
class_name ArakneKing

const ACTIVE_ABILITY_NAME := "Spike Burst"
const ACTIVE_ABILITY_ID: StringName = &"spike_burst"
const PASSIVE_ABILITY_NAME := "Skittering Steps"
const ACTIVE_ABILITY_COOLDOWN := 1
const SPIKE_BURST_DAMAGE := 1

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "arakne_king"
	max_hp = 2
	current_hp = max_hp
	base_cooldown = ACTIVE_ABILITY_COOLDOWN
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return true
