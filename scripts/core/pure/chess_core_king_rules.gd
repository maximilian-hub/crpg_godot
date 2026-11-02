extends RefCounted
class_name ChessCoreKingRules

const ArakneRules := preload("res://scripts/core/pure/arakne_core_rules.gd")
const NecromancerRules := preload("res://scripts/core/pure/necromancer_core_rules.gd")
const MinotaurRules := preload("res://scripts/core/pure/minotaur_core_rules.gd")


static func for_type(type_id: StringName):
	match type_id:
		&"arakne_king": return ArakneRules
		&"necromancer_king": return NecromancerRules
		&"minotaur_king": return MinotaurRules
		_: return null


static func is_supported_king(type_id: StringName) -> bool:
	return type_id == &"classic_king" or for_type(type_id) != null


static func base_cooldown(type_id: StringName) -> int:
	var rules = for_type(type_id)
	return int(rules.base_cooldown()) if rules != null else 0
