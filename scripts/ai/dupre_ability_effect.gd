extends RefCounted
class_name DupreAbilityEffect

enum Trigger { ACTIVE, REACTION, SCHEDULED }
enum Kind { DAMAGE, FORCED_MOVEMENT, DISPLACEMENT, STUN, SUMMON, BLOCK }
enum Certainty { CERTAIN, CONDITIONAL, SIMULATION_REQUIRED }

var source_piece_id := ""
var source_color := ""
var ability_id: StringName = &""
var target_piece_id := ""
var target_coordinate := Vector2i(-1, -1)
var destination := Vector2i(-1, -1)
var ready_in_turn_entries := 0
var trigger := Trigger.ACTIVE
var kind := Kind.DAMAGE
var damage := 0
var lethal := false
var certainty := Certainty.CERTAIN
var material_delta := 0.0
var metadata: Dictionary = {}


func is_valid() -> bool:
	return not source_piece_id.is_empty() and ability_id != &"" and (not target_piece_id.is_empty() or target_coordinate.x >= 0)


func to_diagnostic() -> Dictionary:
	return {
		"source_piece_id": source_piece_id,
		"ability_id": ability_id,
		"target_piece_id": target_piece_id,
		"target_coordinate": target_coordinate,
		"destination": destination,
		"ready_in_turn_entries": ready_in_turn_entries,
		"trigger": trigger,
		"kind": kind,
		"damage": damage,
		"lethal": lethal,
		"certainty": certainty,
		"material_delta": material_delta,
		"metadata": metadata.duplicate(true),
	}
