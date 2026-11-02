extends RefCounted
class_name WraithAiPolicy

const MOVE_INTERVAL_ROUNDS := 3


static func material_value(type_id: StringName, is_king := false) -> float:
	if is_king: return 12.0
	match type_id:
		&"queen": return 9.0
		&"rook": return 5.0
		&"bishop", &"knight": return 3.0
	return 1.0


static func damage_pressure(type_id: StringName, current_hp: int, is_king: bool, rounds_until_hit: int) -> float:
	var value := material_value(type_id, is_king)
	var impact := 35.0 if is_king else (value * 8.0 if current_hp <= 1 else value * 2.5)
	return impact / (1.0 + 0.12 * float(maxi(0, rounds_until_hit)))


static func travel_rounds(from: Vector2i, to: Vector2i, first_wait := MOVE_INTERVAL_ROUNDS) -> int:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	if steps <= 0: return maxi(0, first_wait)
	return maxi(0, first_wait) + maxi(0, steps - 1) * MOVE_INTERVAL_ROUNDS


static func entity_pressure(type_id: StringName, current_hp: int, is_king: bool, entity_coordinate: Vector2i, target_coordinate: Vector2i, rounds_to_next_step: int) -> float:
	return damage_pressure(type_id, current_hp, is_king, travel_rounds(entity_coordinate, target_coordinate, rounds_to_next_step))
