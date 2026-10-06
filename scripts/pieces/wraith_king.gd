extends KingPiece
class_name WraithKing

const ACTIVE_ABILITY_NAME := "Summon Wraith"
const ACTIVE_ABILITY_ID: StringName = &"summon_wraith"
const PASSIVE_ABILITY_NAME := "Lingering Malice"

var bonus_step_used_in_action := false

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

func is_active_ability_ready() -> bool:
	return super.is_active_ability_ready() and model != null and not model.has_autonomous_entity_from_source(piece_id, &"wraith")

func get_active_ability_targets() -> Array:
	var targets: Array = []
	if model == null or model.has_autonomous_entity_from_source(piece_id, &"wraith"):
		return targets
	for row in model.board:
		for piece in row:
			if piece != null and piece.color != color:
				targets.append(piece.coordinate)
	return targets

func active_target_selected(target: Vector2i) -> void:
	var target_piece: ModelPiece = model.board[target.x][target.y] if model.is_in_bounds(target.x, target.y) else null
	if target_piece == null or target_piece.color == color:
		return
	schedule_cooldown()
	await model.summon_wraith(self, target_piece)

func begin_primary_action() -> void:
	bonus_step_used_in_action = false

func on_direct_capture(captured_at: Vector2i) -> void:
	model.add_tile_effect(&"cursed_mark", captured_at, color, piece_id)
	on_landed_on_mark(captured_at)

func on_landed_on_mark(coord: Vector2i) -> void:
	if not model.has_tile_effect(&"cursed_mark", coord, piece_id):
		return
	if bonus_step_used_in_action:
		return
	bonus_step_used_in_action = true
	model.queue_selection_opportunity(self, "lingering_malice", coord)

func get_selection_targets(action_type: String, event_data) -> Array:
	if action_type != "lingering_malice" or not model.has_tile_effect(&"cursed_mark", event_data, piece_id):
		return []
	var targets: Array = [coordinate] # Selecting the King's square declines the optional step.
	for coord in model.get_adjacent_squares(coordinate):
		var occupant: ModelPiece = model.board[coord.x][coord.y]
		if occupant == null or occupant.color != color:
			targets.append(coord)
	return targets

func _on_special_target_selected(coord: Vector2i):
	model.remove_tile_effect(&"cursed_mark", coordinate, piece_id)
	if coord == coordinate:
		return
	var occupant: ModelPiece = model.board[coord.x][coord.y]
	if occupant == null:
		await model.actually_move_piece(self, coord)
	elif occupant.color != color:
		await model.handle_combat(self, coord)
