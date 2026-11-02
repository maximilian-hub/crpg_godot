extends KingPiece
class_name ArcherKing

const ACTIVE_ABILITY_NAME := "Volley of Arrows"
const ACTIVE_ABILITY_ID: StringName = &"volley_of_arrows"
const PASSIVE_ABILITY_NAME := "Sharpshooter"
const ACTIVE_ABILITY_COOLDOWN := 4
const VOLLEY_SQUARE_COUNT := 6

const VARIANT_STANDARD: StringName = &"standard"
const VARIANT_DRAW: StringName = &"draw"
const VARIANT_QUIVER: StringName = &"quiver"
const VARIANT_COMBINATION: StringName = &"combination"
const VARIANT_CHARGE: StringName = &"charge"

var archer_variant: StringName = VARIANT_STANDARD
var draw_target := Vector2i(-1, -1)
var draw_target_piece_id := ""
var draw_turns_waited := 0
var charge_level := 0
var arrows := 2

func uses_draw_mechanic() -> bool:
	return archer_variant in [VARIANT_DRAW, VARIANT_COMBINATION]

func uses_quiver() -> bool:
	return archer_variant in [VARIANT_QUIVER, VARIANT_COMBINATION]

func uses_charge() -> bool:
	return archer_variant == VARIANT_CHARGE

func is_drawing() -> bool:
	return draw_target != Vector2i(-1, -1) or charge_level > 0

func is_suppressed() -> bool:
	return model.is_archer_suppressed(self) if model != null else false

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	type = "archer_king"
	max_hp = 2
	current_hp = max_hp
	base_cooldown = ACTIVE_ABILITY_COOLDOWN
	active_ability_name = ACTIVE_ABILITY_NAME
	active_ability_id = ACTIVE_ABILITY_ID
	passive_ability_name = PASSIVE_ABILITY_NAME
	reset_cooldown()

func has_active_ability() -> bool:
	return not is_suppressed() and not (uses_draw_mechanic() and is_drawing())

func capture_custom_state() -> Dictionary:
	return {"draw_target": [draw_target.x, draw_target.y], "draw_target_piece_id": draw_target_piece_id, "draw_turns_waited": draw_turns_waited, "charge_level": charge_level, "arrows": arrows}

func restore_custom_state(state: Dictionary) -> void:
	var target = state.get("draw_target", [-1, -1])
	if target is Array and target.size() == 2:
		draw_target = Vector2i(int(target[0]), int(target[1]))
	draw_target_piece_id = String(state.get("draw_target_piece_id", ""))
	draw_turns_waited = maxi(0, int(state.get("draw_turns_waited", 0)))
	charge_level = clampi(int(state.get("charge_level", 0)), 0, 3)
	arrows = clampi(int(state.get("arrows", 2)), 0, 2)
