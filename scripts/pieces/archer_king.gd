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
	if model == null:
		return false
	for row in range(maxi(0, coordinate.x - 1), mini(model.board.size(), coordinate.x + 2)):
		for column in range(maxi(0, coordinate.y - 1), mini(model.board[row].size(), coordinate.y + 2)):
			var piece: ModelPiece = model.board[row][column]
			if piece != null and piece.color != color:
				return true
	return false

func can_begin_charge() -> bool:
	return uses_charge() and charge_level == 0 and not is_suppressed()

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

func get_legal_moves() -> Array:
	var moves: Array = []
	if uses_draw_mechanic() and draw_target != Vector2i(-1, -1):
		return moves
	var attack_position := get_live_attack_position()
	for row in range(model.board.size()):
		for column in range(model.board[row].size()):
			var target := Vector2i(row, column)
			var distance := maxi(absi(target.x - coordinate.x), absi(target.y - coordinate.y))
			var occupant: ModelPiece = model.board[row][column]
			if distance == 1 and occupant == null:
				moves.append(target)
			elif can_natively_attack_square(coordinate, target, attack_position) and occupant != null and occupant.color != color:
				moves.append(target)
	return moves

func can_natively_attack_square(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	if is_suppressed():
		return false
	if uses_quiver() and arrows <= 0:
		return false
	if not position.is_in_bounds(target):
		return false
	var delta := target - origin
	var distance := maxi(absi(delta.x), absi(delta.y))
	var minimum_range := 2
	var maximum_range := 3
	if uses_charge():
		if charge_level <= 0:
			return false
		maximum_range = charge_level + 1
	if distance < minimum_range or distance > maximum_range:
		return false
	return position.get_visibility_map(origin).has(target)

func has_active_ability() -> bool:
	return not is_suppressed()

func get_active_ability_targets() -> Array:
	return [] if is_suppressed() else [coordinate]

func active_target_selected(target: Vector2i) -> void:
	if target != coordinate:
		return
	schedule_cooldown()
	await model.resolve_archer_volley(self)

func begin_draw(target: Vector2i) -> void:
	draw_target = target
	var target_piece: ModelPiece = model.board[target.x][target.y] if model != null and model.is_in_bounds(target.x, target.y) else null
	draw_target_piece_id = target_piece.piece_id if target_piece != null else ""
	model.announce_archer_state(self, &"drawing", "Drawing Bow")

func begin_charge() -> void:
	charge_level = 1
	model.announce_archer_state(self, &"drawing", "Drawing Bow")

func cancel_draw(message := "") -> void:
	draw_target = Vector2i(-1, -1)
	draw_target_piece_id = ""
	charge_level = 0
	model.announce_archer_state(self, &"idle", message)

func advance_charge() -> void:
	if charge_level <= 0 or charge_level >= 3:
		return
	charge_level += 1
	model.announce_archer_state(self, &"drawing", "Charge Level MAX" if charge_level == 3 else "Charge Level 2")

func capture_custom_state() -> Dictionary:
	return {"draw_target": [draw_target.x, draw_target.y], "draw_target_piece_id": draw_target_piece_id, "charge_level": charge_level, "arrows": arrows}

func restore_custom_state(state: Dictionary) -> void:
	var target = state.get("draw_target", [-1, -1])
	if target is Array and target.size() == 2:
		draw_target = Vector2i(int(target[0]), int(target[1]))
	draw_target_piece_id = String(state.get("draw_target_piece_id", ""))
	charge_level = clampi(int(state.get("charge_level", 0)), 0, 3)
	arrows = clampi(int(state.get("arrows", 2)), 0, 2)

func incoming_damage_multiplier() -> int:
	return 2 if is_drawing() else 1
