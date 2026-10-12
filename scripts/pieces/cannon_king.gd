extends KingPiece
class_name CannonKing

const ACTIVE_ABILITY_NAME := "Arc Mortar"
const ACTIVE_ABILITY_ID: StringName = &"arc_mortar"
const PASSIVE_ABILITY_NAME := "Calculated Trajectory"
const ARC_MORTAR_DAMAGE := 1
const ARC_MORTAR_RANGE := 5

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

func get_active_ability_targets() -> Array:
	var targets: Array = []
	if model == null:
		return targets
	for row in range(model.board.size() - 1):
		for column in range(model.board[row].size() - 1):
			var anchor := Vector2i(row, column)
			var delta := anchor - coordinate
			if maxi(absi(delta.x), absi(delta.y)) <= ARC_MORTAR_RANGE:
				targets.append(anchor)
	return targets

func active_target_selected(target: Vector2i) -> void:
	if target not in get_active_ability_targets():
		return
	var area := model.get_mortar_area(target)
	var has_enemy := false
	for coord in area:
		var occupant: ModelPiece = model.board[coord.x][coord.y]
		if occupant != null and occupant.color != color:
			has_enemy = true
			break
	scheduled_arc_cooldown = base_cooldown if has_enemy else maxi(0, base_cooldown - 1)
	schedule_cooldown()
	await model.launch_arc_mortar(self, target)

func _on_turn_changed(current_turn: String):
	if current_turn == color and cooldown_reset_pending:
		if stunned:
			decrement_stun_timer()
		initial_cooldown_turn_pending = false
		set_cooldown(scheduled_arc_cooldown)
		return
	super._on_turn_changed(current_turn)

func capture_custom_state() -> Dictionary:
	return {"scheduled_arc_cooldown": scheduled_arc_cooldown}

func restore_custom_state(state: Dictionary) -> void:
	scheduled_arc_cooldown = int(state.get("scheduled_arc_cooldown", base_cooldown))
